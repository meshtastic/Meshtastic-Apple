// MARK: DiscoveryScanEngine
//
//  DiscoveryScanEngine.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Combine
import Foundation
import MapKit
import MeshtasticProtobufs
import OSLog
@preconcurrency import SwiftData
import SwiftUI

// MARK: - Scan State

enum DiscoveryScanState: Equatable, CustomStringConvertible {
	case idle
	case shifting
	case reconnecting
	case dwell
	case analysis
	case complete
	case paused
	case restoring

	var description: String {
		switch self {
		case .idle: "idle"
		case .shifting: "shifting"
		case .reconnecting: "reconnecting"
		case .dwell: "dwell"
		case .analysis: "analysis"
		case .complete: "complete"
		case .paused: "paused"
		case .restoring: "restoring"
		}
	}
}

// MARK: - Scan Target

/// A single dwell target for the scan. Manual selections and public-channel beacons leave
/// `channelName` nil and run on the scan's default public channel; a custom-channel beacon carries
/// the advertised channel (name + PSK) so the scan tunes the radio to that mesh's frequency and can
/// decode it. An optional region override lets a beacon steer the scan to the region it runs in.
struct ScanTarget: Equatable {
	let preset: ModemPresets
	let regionRaw: Int?
	let channelName: String?
	let channelPSK: Data?

	init(preset: ModemPresets, regionRaw: Int? = nil, channelName: String? = nil, channelPSK: Data? = nil) {
		self.preset = preset
		self.regionRaw = regionRaw
		self.channelName = channelName
		self.channelPSK = channelPSK
	}

	/// True when the target names a specific (non-public) channel the scan must tune to.
	var isCustomChannel: Bool { (channelName?.isEmpty == false) }

	/// The name shown in results and used to key discovered nodes. Custom-channel targets append the
	/// channel so two targets on the same preset (public vs. a beacon's channel) don't collide.
	var label: String {
		if let name = channelName, !name.isEmpty { return "\(preset.name) · \(name)" }
		return preset.name
	}
}

// MARK: - DiscoveryScanEngine

@MainActor @Observable
final class DiscoveryScanEngine {

	// MARK: Published State

	var currentState: DiscoveryScanState = .idle
	var activePreset: ModemPresets?
	/// The full target currently dwelling (preset + optional region + custom channel). `activePreset`
	/// mirrors `activeTarget?.preset` for display; `activeTargetLabel` keys results/nodes.
	var activeTarget: ScanTarget?
	private var activeTargetLabel: String = ""
	/// True while the scan has the radio tuned to a beacon's custom channel, so the next
	/// public/manual target knows to switch back to the default public channel first.
	private var scanChannelIsCustom = false
	var dwellTimeRemaining: TimeInterval = 0
	var selectedPresets: [ModemPresets] = []
	/// Custom-channel targets the user pre-selected in the scan setup (from beacons that advertised
	/// a channel). Queued alongside `selectedPresets` when the scan starts, so a beacon's private
	/// mesh can be included up front instead of only being auto-queued if its beacon is heard again.
	var selectedBeaconTargets: [ScanTarget] = []
	var dwellDuration: TimeInterval = 900 // 15 minutes default
	var session: DiscoverySessionEntity?
	var errorMessage: String?

	// MARK: Internal State

	private var homePreset: ModemPresets?
	/// Full snapshot of the LoRa config as it was before the scan started, so every field
	/// (frequency slot, overrides, MQTT flags, …) can be restored exactly afterward (#1952).
	private var homeLoRaConfig: Config.LoRaConfig?
	/// Snapshot of the user's primary channel, captured only when the scan temporarily switches its
	/// key to the default so the radio can decode the public mesh. Restored verbatim when the scan
	/// finishes. Channel changes don't reboot the radio, so this is applied before — and restored
	/// after — the LoRa preset changes, while the connection is still up.
	private var homePrimaryChannel: Channel?
	private var presetQueue: [ScanTarget] = []
	private var currentPresetResult: DiscoveryPresetResultEntity?
	private var dwellTask: Task<Void, Never>?
	private var reconnectTimeoutTask: Task<Void, Never>?
	private var connectionObserver: AnyCancellable?
	private var configCompleteObserver: AnyCancellable?
	private var modelContext: ModelContext?
	private weak var accessoryManager: AccessoryManager?

	/// Tracks whether we're waiting for a disconnect after sending a config change.
	/// Prevents premature "reconnection" detection when BLE hasn't disconnected yet.
	private var awaitingDisconnect = false

	/// Tracks remaining dwell time when dwell is interrupted by a connection drop.
	/// Used to resume the dwell with the correct remaining time instead of restarting.
	private var interruptedDwellRemaining: TimeInterval?

	/// DeviceMetrics tracking for 2-packet rule
	struct DeviceMetricsEntry {
		let timestamp: Date
		let channelUtil: Double
		let airUtilTx: Double
	}
	private var deviceMetricsHistory: [Int64: [DeviceMetricsEntry]] = [:]

	/// When the current preset's dwell began. Local-stats telemetry from the connected node that
	/// arrives at/after this time reflects the preset's frequency, so it's used to window the
	/// noise-floor / channel-utilization samples captured for the preset result.
	private var presetDwellStart: Date?

	/// Set for a "current preset" scan: seed the preset's results from everything already in
	/// SwiftData at dwell start (so the run reflects all accumulated data, not just packets that
	/// arrive during this dwell) and consider the full local-stats history for RF metrics.
	private var seedFromExistingData = false

	/// Short dwell used by `startCurrentPresetScan()` — the report is built from seeded history,
	/// so it only needs a brief window to fold in any live packets before finalizing.
	static let currentPresetScanDwell: TimeInterval = 60

	/// The well-known public/default channel key (single byte `0x01`, i.e. "AQ=="). A primary
	/// channel using this key — or no key at all — can decode the public mesh.
	private static let defaultChannelKey = Data([0x01])

	/// Paces the animated reveal of seeded nodes onto the map during a current-preset scan.
	private var seedTask: Task<Void, Never>?

	var isScanning: Bool {
		switch currentState {
		case .shifting, .reconnecting, .dwell, .paused, .restoring:
			return true
		case .idle, .analysis, .complete:
			return false
		}
	}

	// MARK: - Init

	func configure(accessoryManager: AccessoryManager, modelContext: ModelContext) {
		self.accessoryManager = accessoryManager
		self.modelContext = modelContext
		Logger.discovery.info("📡 [Discovery] Engine configured")
	}

	// MARK: - Start Scan (T014)

	func startScan() async {
		guard currentState == .idle else {
			Logger.discovery.warning("📡 [Discovery] Cannot start scan — not idle (state: \(self.currentState))")
			return
		}
		guard !selectedPresets.isEmpty || !selectedBeaconTargets.isEmpty else {
			Logger.discovery.warning("📡 [Discovery] Cannot start scan — no presets or beacon channels selected")
			return
		}
		// A normal multi-preset scan drives the radio through each preset, so it requires a live
		// connection. The seeded "Analyze Current Preset" pass (seedFromExistingData) is built
		// entirely from local SwiftData and sends nothing to the radio, so it may run offline —
		// e.g. reviewing your mesh with no radio connected. Only that seeded path is exempt from
		// the connection requirement.
		let isConnected = accessoryManager?.isConnected ?? false
		guard seedFromExistingData || isConnected else {
			Logger.discovery.warning("📡 [Discovery] Cannot start scan — radio not connected")
			return
		}
		guard let context = modelContext else {
			Logger.discovery.error("📡 [Discovery] Cannot start scan — no model context")
			return
		}

		// Clear any previous error
		errorMessage = nil

		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		let connectedNode = getNodeInfo(id: connectedNodeNum, context: context)

		// Connection-only setup: snapshot the home LoRa config and, if needed, temporarily switch
		// the primary channel to the default public channel. Skipped entirely when running offline —
		// the seeded pass never sends config, so there is nothing to snapshot, switch, or restore.
		if isConnected {
			// Record home preset from current LoRa config
			if let loraConfig = connectedNode?.loRaConfig, !loraConfig.isDeleted {
				homePreset = ModemPresets(rawValue: Int(loraConfig.modemPreset))
				// Snapshot the complete config so restore puts back the frequency slot and all
				// other LoRa settings exactly — not just the modem preset (#1952). Each scan preset
				// is sent on the default frequency slot (see sendPresetChange); this snapshot is what
				// returns the user to their real slot when the scan finishes.
				homeLoRaConfig = loRaConfigProto(from: loraConfig, presetOverride: nil)
			}

			// If the primary channel isn't the default public channel, temporarily switch it (key + name)
			// so the radio can decode the public mesh and derive its frequency during the scan. Channel
			// changes don't reboot the radio, so this is sent now (while connected) ahead of any preset
			// change, and restored before teardown.
			await prepareDefaultPublicChannel(connectedNode: connectedNode)
		}

		// Create session
		let newSession = DiscoverySessionEntity()
		newSession.presetsScanned = (selectedPresets.map(\.name) + selectedBeaconTargets.map(\.label)).joined(separator: ",")
		newSession.homePreset = homePreset?.name ?? ""
		newSession.completionStatus = "inProgress"

		// Record user position if available
		if let position = connectedNode?.positions.last {
			newSession.userLatitude = position.latitude ?? 0.0
			newSession.userLongitude = position.longitude ?? 0.0
		}

		context.insert(newSession)
		session = newSession

		// Build preset queue — manual selections run on the default public channel. Custom-channel
		// targets the user pre-selected (from beacons) are queued next; further beacon targets are
		// still appended dynamically as beacons arrive during dwells.
		presetQueue = selectedPresets.map { ScanTarget(preset: $0) }
		for target in selectedBeaconTargets where !presetQueue.contains(target) {
			presetQueue.append(target)
		}
		deviceMetricsHistory = [:]

		Logger.discovery.info("📡 [Discovery] Scan started with \(self.selectedPresets.count) presets, dwell: \(self.dwellDuration)s")

		// Register engine with AccessoryManager for packet forwarding.
		accessoryManager?.discoveryScanEngine = self

		// Observe connection state changes — only when connected. A seeded offline pass has no
		// link to watch, and the reconnect/dwell-interruption machinery (which would otherwise
		// see "disconnected" and pause the dwell) must not fire for it.
		if isConnected {
			observeConnectionState()
		}

		// Start first preset
		await shiftToNextPreset()
	}

	// MARK: - Shift to Next Preset

	private func shiftToNextPreset() async {
		guard !presetQueue.isEmpty else {
			// All presets complete → analysis
			Logger.discovery.info("📡 [Discovery] All presets complete → Analysis")
			transitionTo(.analysis)
			await finalizeSession()
			transitionTo(.restoring)
			await restoreHomePreset()
			return
		}

		let target = presetQueue.removeFirst()
		let nextPreset = target.preset
		activeTarget = target
		activeTargetLabel = target.label
		activePreset = nextPreset
		transitionTo(.shifting)

		// Create preset result
		let presetResult = DiscoveryPresetResultEntity()
		presetResult.presetName = target.label
		presetResult.dwellDurationSeconds = Int(dwellDuration)
		presetResult.session = session
		session?.presetResults.append(presetResult)
		currentPresetResult = presetResult
		modelContext?.insert(presetResult)

		// Start the local-stats window for this preset. The radio is offline during the config
		// change/reboot, so no stale samples land before the new frequency is active.
		presetDwellStart = Date()

		// "Current preset" scan: fold in everything already collected for this preset so the run
		// reflects accumulated history, and widen the local-stats window to the full history. The
		// seeded nodes are revealed onto the map progressively over the dwell (accelerated
		// playback) rather than all at once.
		if seedFromExistingData {
			presetDwellStart = nil
			seedTask?.cancel()
			seedTask = Task { [weak self] in await self?.revealSeededNodesFromDatabase() }

			// The seeded "Analyze Current Preset" pass never changes the radio's preset — it dwells
			// on the preset the radio already uses (or, when offline, the last-known/default preset)
			// and builds the report from local data plus any live packets. Skip the config change and
			// all of its reconnect/reboot machinery, and begin dwelling immediately. This also lets
			// the pass run with no radio connected — there is nothing to send.
			Logger.discovery.info("📡 [Discovery] Seeded current-preset pass — dwelling on \(nextPreset.name) without a config change")
			transitionTo(.dwell)
			startDwellTimer()
			return
		}

		Logger.discovery.info("📡 [Discovery] Shifting to target: \(target.label)")

		// Tune the primary channel for this target before the (rebooting) preset change: a
		// custom-channel beacon target switches to its channel; a public/manual target switches
		// back to the default public channel only if a previous custom target left us tuned away.
		await applyChannel(for: target)

		// Skip the config change only for a plain public target we're already sitting on (no region
		// override, no custom channel). Custom-channel / region-override targets always re-send.
		if !target.isCustomChannel, target.regionRaw == nil, accessoryManager != nil, let context = modelContext {
			let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
			let node = getNodeInfo(id: connectedNodeNum, context: context)
			if let currentModemPreset = node?.loRaConfig?.modemPreset,
			   ModemPresets(rawValue: Int(currentModemPreset)) == nextPreset {
				Logger.discovery.info("📡 [Discovery] Already on preset \(nextPreset.name) — skipping config change")
				transitionTo(.dwell)
				startDwellTimer()
				return
			}
		}

		// Send config change
		await sendPresetChange(for: target)
	}

	// MARK: - LoRa Config Helper

	/// Builds a complete `Config.LoRaConfig` proto from the stored entity, preserving every
	/// field. `saveLoRaConfig` replaces the device's entire LoRa config, so any field left at
	/// its proto default is written as 0/false on the radio — e.g. `channelNum` (frequency
	/// slot) → 0, which silently moves the radio off the user's frequency and wipes their
	/// settings. The discovery scan only needs to change the modem preset, so everything else
	/// must be carried through (#1952).
	/// - Parameter presetOverride: when set, replaces the modem preset (used while shifting
	///   presets); when `nil`, the entity's own preset is used (used to snapshot/restore home).
	///
	/// Internal (not private) so the field-preservation guarantee can be unit-tested.
	func loRaConfigProto(from entity: LoRaConfigEntity, presetOverride: ModemPresets?) -> Config.LoRaConfig {
		var config = Config.LoRaConfig()
		if let resolvedPreset = presetOverride ?? ModemPresets(rawValue: Int(entity.modemPreset)) {
			config.modemPreset = resolvedPreset.protoEnumValue()
		}
		config.region = Config.LoRaConfig.RegionCode(rawValue: Int(entity.regionCode)) ?? .unset
		config.usePreset = entity.usePreset
		config.hopLimit = UInt32(entity.hopLimit)
		config.txEnabled = entity.txEnabled
		config.txPower = entity.txPower
		config.channelNum = UInt32(entity.channelNum)
		config.bandwidth = UInt32(entity.bandwidth)
		config.codingRate = UInt32(entity.codingRate)
		config.spreadFactor = UInt32(entity.spreadFactor)
		config.frequencyOffset = entity.frequencyOffset
		config.overrideFrequency = entity.overrideFrequency
		config.overrideDutyCycle = entity.overrideDutyCycle
		config.sx126XRxBoostedGain = entity.sx126xRxBoostedGain
		config.ignoreMqtt = entity.ignoreMqtt
		config.configOkToMqtt = entity.okToMqtt
		return config
	}

	// MARK: - Send Preset Change

	private func sendPresetChange(for target: ScanTarget) async {
		let preset = target.preset
		guard let accessoryManager, let context = modelContext else { return }

		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		guard let connectedNode = getNodeInfo(id: connectedNodeNum, context: context),
			  let fromUser = connectedNode.user,
			  let toUser = connectedNode.user else {
			Logger.discovery.error("📡 [Discovery] Cannot send preset change — no connected node/user")
			return
		}

		// Carry through EVERY existing LoRa field, changing only the modem preset. The device
		// applies the whole config, so building a partial one zeroes the omitted fields —
		// notably bandwidth/codingRate/spreadFactor and the MQTT/override flags — which would
		// silently wipe the user's settings (#1952).
		//
		// The one field we deliberately DON'T carry through is the frequency slot: the scan must
		// run on the default slot (0) so the firmware auto-derives each preset's frequency from
		// the primary channel. A user's custom frequency slot can't be translated across presets,
		// so scanning on it would listen on the wrong frequency and find nothing. The user's real
		// slot is snapshotted in `homeLoRaConfig` and restored verbatim when the scan finishes.
		let loraConfig: Config.LoRaConfig
		if let existingConfig = connectedNode.loRaConfig, !existingConfig.isDeleted {
			var scanConfig = loRaConfigProto(from: existingConfig, presetOverride: preset)
			scanConfig.channelNum = 0
			// A beacon may advertise the region its mesh runs in; apply it so the derived frequency
			// matches. Manual/public targets carry no override and keep the user's current region.
			if let regionRaw = target.regionRaw, let region = RegionCodes(rawValue: regionRaw) {
				scanConfig.region = region.protoEnumValue()
			}
			loraConfig = scanConfig
		} else {
			var minimal = Config.LoRaConfig()
			minimal.modemPreset = preset.protoEnumValue()
			if let regionRaw = target.regionRaw, let region = RegionCodes(rawValue: regionRaw) {
				minimal.region = region.protoEnumValue()
			}
			loraConfig = minimal
			Logger.discovery.warning("📡 [Discovery] No existing LoRa config to copy — sending preset-only config")
		}

		do {
			_ = try await accessoryManager.saveLoRaConfig(config: loraConfig, fromUser: fromUser, toUser: toUser)
			Logger.discovery.info("📡 [Discovery] Sent LoRa config change to preset: \(preset.name)")

			// Determine transport type for reconnection strategy
			let transportType = await accessoryManager.activeConnection?.connection.type

			// Mark that we're awaiting a disconnect — prevents premature reconnection detection
			awaitingDisconnect = true
			interruptedDwellRemaining = nil
			transitionTo(.reconnecting)

			if transportType == .tcp || transportType == .serial {
				// TCP/Serial: connection stays open but device reboots — wait 60s then check
				Logger.discovery.info("📡 [Discovery] TCP/Serial transport — waiting 60s for device reboot")
				startRebootWaitTimer()
			} else {
				// BLE: device reboots and BLE disconnects naturally — rely on connection observer
				Logger.discovery.info("📡 [Discovery] BLE transport — waiting for reconnection")
				startReconnectTimeout()
			}
		} catch {
			Logger.discovery.error("📡 [Discovery] Failed to send preset change: \(error.localizedDescription)")
			errorMessage = "Failed to change preset: \(error.localizedDescription)"
		}
	}

	// MARK: - Reconnection Handling (T015)

	private func observeConnectionState() {
		connectionObserver = accessoryManager?.objectWillChange.sink { [weak self] _ in
			Task { @MainActor [weak self] in
				guard let self else { return }
				self.handleConnectionStateChange()
			}
		}
	}

	private func handleConnectionStateChange() {
		guard let accessoryManager else { return }

		switch currentState {
		case .reconnecting:
			if !accessoryManager.isConnected {
				// Device has actually disconnected — clear the flag so we accept the next reconnection
				if awaitingDisconnect {
					awaitingDisconnect = false
					Logger.discovery.info("📡 [Discovery] Device disconnected after config change — awaiting reconnection")
				}
			} else if accessoryManager.isConnected && accessoryManager.state == .subscribed && !awaitingDisconnect {
				Logger.discovery.info("📡 [Discovery] Reconnected after preset change → Dwell")
				reconnectTimeoutTask?.cancel()
				transitionTo(.dwell)
				startDwellTimer()
			}
		case .paused:
			if accessoryManager.isConnected && accessoryManager.state == .subscribed {
				Logger.discovery.info("📡 [Discovery] Connection restored while paused → Resuming dwell")
				awaitingDisconnect = false
				transitionTo(.dwell)
				startDwellTimer()
			}
		case .dwell:
			if !accessoryManager.isConnected {
				// Save remaining time so we can resume if connection is restored
				interruptedDwellRemaining = dwellTimeRemaining
				Logger.discovery.warning("📡 [Discovery] Connection lost during dwell (\(Int(self.dwellTimeRemaining))s remaining) — entering reconnecting state")
				dwellTask?.cancel()
				transitionTo(.reconnecting)
				startReconnectTimeout()
			}
		default:
			break
		}
	}

	/// Seconds to wait for the device to reboot before we stop requiring an observed BLE
	/// disconnect (see `awaitingDisconnect`). A reboot+reconnect normally completes within this.
	private static let reconnectGraceSeconds = 30
	/// Hard cap on the whole reconnect wait before giving up.
	private static let reconnectTimeoutSeconds = 120

	/// Once the post-preset-change reconnect window elapses, decide where a still-`.reconnecting`
	/// scan should go: connected & subscribed → resume dwelling (covers a missed disconnect edge
	/// or a recovered link); otherwise the link is genuinely down → pause. Pure for testability.
	nonisolated static func reconnectTimeoutResolution(isConnected: Bool, isSubscribed: Bool) -> DiscoveryScanState {
		(isConnected && isSubscribed) ? .dwell : .paused
	}

	private func startReconnectTimeout() {
		reconnectTimeoutTask?.cancel()
		reconnectTimeoutTask = Task { [weak self] in
			// Grace period: give the device time to reboot and BLE to cycle. If we never observe
			// the disconnect edge (missed event, or a reconnect faster than the observer can see
			// it), stop requiring it — otherwise the scan hangs on this preset forever and never
			// rotates (#1952 item 3).
			do { try await Task.sleep(for: .seconds(Self.reconnectGraceSeconds)) } catch { return }
			guard let self, self.currentState == .reconnecting else { return }

			// After the grace period we no longer require an observed disconnect edge.
			if self.awaitingDisconnect {
				self.awaitingDisconnect = false
				Logger.discovery.warning("📡 [Discovery] No disconnect observed \(Self.reconnectGraceSeconds)s after preset change — no longer requiring one")
			}
			// If the device is back — whether or not we ever saw the disconnect, and whether or
			// not the observer's subscribe edge fired — proceed to dwell now rather than waiting
			// out the full timeout. (Checked regardless of awaitingDisconnect: the observer
			// clears it on the disconnect edge, so gating this on it would skip the fast path in
			// exactly the missed-subscribe-edge case it exists to handle.)
			let connected = self.accessoryManager?.isConnected ?? false
			let subscribed = self.accessoryManager.map { $0.state == .subscribed } ?? false
			if connected && subscribed {
				Logger.discovery.info("📡 [Discovery] Connected & subscribed after grace → Dwell")
				self.transitionTo(.dwell)
				self.startDwellTimer()
				return
			}

			// Still not back: wait out the remaining window. With `awaitingDisconnect` now clear,
			// the connection observer will advance us to dwell the instant we reconnect. If the
			// window fully elapses, recover if we're somehow connected, else pause.
			let remaining = Self.reconnectTimeoutSeconds - Self.reconnectGraceSeconds
			do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
			guard self.currentState == .reconnecting else { return }
			let resolution = Self.reconnectTimeoutResolution(
				isConnected: self.accessoryManager?.isConnected ?? false,
				isSubscribed: self.accessoryManager.map { $0.state == .subscribed } ?? false
			)
			Logger.discovery.warning("📡 [Discovery] Reconnect window elapsed (\(Self.reconnectTimeoutSeconds)s) → \(resolution)")
			self.transitionTo(resolution)
			if resolution == .dwell { self.startDwellTimer() }
		}
	}

	/// TCP/Serial: wait 60s for device reboot, then transition to dwell if still connected
	private func startRebootWaitTimer() {
		reconnectTimeoutTask?.cancel()
		reconnectTimeoutTask = Task { [weak self] in
			do {
				try await Task.sleep(for: .seconds(60))
				guard let self, self.currentState == .reconnecting else { return }
				guard let accessoryManager, accessoryManager.isConnected else {
					Logger.discovery.warning("📡 [Discovery] TCP/Serial not connected after reboot wait → Paused")
					self.transitionTo(.paused)
					return
				}
				Logger.discovery.info("📡 [Discovery] TCP/Serial reboot wait complete — connected → Dwell")
				self.transitionTo(.dwell)
				self.startDwellTimer()
			} catch {
				// Cancelled
			}
		}
	}

	// MARK: - Dwell Timer (T016)

	private func startDwellTimer() {
		// If resuming an interrupted dwell, use remaining time; otherwise use full duration
		let effectiveDuration: TimeInterval
		if let remaining = interruptedDwellRemaining, remaining > 0 {
			effectiveDuration = remaining
			Logger.discovery.info("📡 [Discovery] Resuming dwell with \(Int(remaining))s remaining")
		} else {
			effectiveDuration = dwellDuration
		}
		interruptedDwellRemaining = nil
		dwellTimeRemaining = effectiveDuration
		dwellTask?.cancel()

		dwellTask = Task { [weak self] in
			guard let self else { return }
			let startTime = Date()

			while dwellTimeRemaining > 0 {
				do {
					try await Task.sleep(for: .seconds(1))
					guard !Task.isCancelled else { return }
					let elapsed = Date().timeIntervalSince(startTime)
					dwellTimeRemaining = max(0, effectiveDuration - elapsed)
				} catch {
					return // Task cancelled
				}
			}

			guard !Task.isCancelled else { return }
			Logger.discovery.info("📡 [Discovery] Dwell complete for preset: \(self.activePreset?.name ?? "unknown")")

			// Make sure the animated seed reveal has finished so every node is counted.
			await self.seedTask?.value

			// Finalize preset result
			self.finalizePresetResult()

			if self.presetQueue.isEmpty {
				Logger.discovery.info("📡 [Discovery] Last preset complete → Analysis")
				self.transitionTo(.analysis)
				await self.finalizeSession()
				self.transitionTo(.restoring)
				await self.restoreHomePreset()
			} else {
				await self.shiftToNextPreset()
			}
		}
	}

	// MARK: - Packet Ingestion (T017)

	func handleNeighborInfo(_ neighborInfo: NeighborInfo, packet: MeshPacket) {
		guard currentState == .dwell, let context = modelContext else { return }

		Logger.discovery.info("📡 [Discovery] NeighborInfo from node \(neighborInfo.nodeID): \(neighborInfo.neighbors.count) neighbors")

		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		for neighbor in neighborInfo.neighbors {
			let nodeNum = Int64(neighbor.nodeID)
			// Skip the scanning node itself
			guard nodeNum != connectedNodeNum else { continue }
			let existingNode = session?.discoveredNodes.first(where: { $0.nodeNum == nodeNum && $0.presetName == activeTargetLabel })

			if existingNode == nil {
				let discoveredNode = DiscoveredNodeEntity()
				discoveredNode.nodeNum = nodeNum
				discoveredNode.neighborType = "mesh"
				discoveredNode.snr = neighbor.snr
				discoveredNode.presetName = activeTargetLabel
				discoveredNode.session = session
				discoveredNode.presetResult = currentPresetResult
				context.insert(discoveredNode)
				session?.discoveredNodes.append(discoveredNode)
				currentPresetResult?.nodes.append(discoveredNode)

				// Try to populate name/position from existing NodeInfo
				if let knownNode = getNodeInfo(id: nodeNum, context: context) {
					discoveredNode.shortName = knownNode.user?.shortName ?? ""
					discoveredNode.longName = knownNode.user?.longName ?? ""
					if let pos = knownNode.positions.last {
						discoveredNode.latitude = pos.latitude ?? 0.0
						discoveredNode.longitude = pos.longitude ?? 0.0
					}
				}
			}
		}
	}

	/// Store a MESH_BEACON_APP beacon heard during a dwell and auto-add the mesh it advertises to
	/// the scan so this run also dwells on it. A public-channel beacon adds its modem preset (the
	/// scan already listens on the default public channel); a custom-channel beacon adds a target
	/// carrying the offered channel (name + PSK) so the scan tunes to that mesh's frequency and can
	/// decode it — scanning the bare preset on the public channel would be the wrong frequency.
	func handleBeacon(_ beacon: MeshBeacon, packet: MeshPacket) {
		guard currentState == .dwell, let context = modelContext else { return }

		let fromNodeNum = Int64(packet.from)
		// Skip beacons from the scanning node itself.
		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		guard fromNodeNum != connectedNodeNum else { return }

		let hasCustomChannel = beacon.hasOfferChannel && !beacon.offerChannel.name.isEmpty

		let entity = DiscoveredBeaconEntity()
		entity.nodeNum = fromNodeNum
		entity.message = beacon.message
		entity.offerRegion = beacon.offerRegion != .unset ? beacon.offerRegion.rawValue : 0
		entity.offerPreset = beacon.hasOfferPreset ? beacon.offerPreset.rawValue : -1
		entity.hasOfferChannel = hasCustomChannel
		entity.offerChannelName = hasCustomChannel ? beacon.offerChannel.name : ""
		entity.offerChannelPSK = hasCustomChannel ? beacon.offerChannel.psk : Data()
		entity.snr = packet.rxSnr
		entity.rssi = Int(packet.rxRssi)
		entity.timestamp = Date()
		entity.heardOnPresetName = activeTargetLabel
		entity.session = session
		entity.presetResult = currentPresetResult

		if let knownNode = getNodeInfo(id: fromNodeNum, context: context) {
			entity.shortName = knownNode.user?.shortName ?? ""
			entity.longName = knownNode.user?.longName ?? ""
		}

		context.insert(entity)
		session?.beacons.append(entity)
		currentPresetResult?.beacons.append(entity)

		Logger.discovery.info("📡 [Discovery] Beacon from \(fromNodeNum, privacy: .private) — offerPreset \(entity.offerPreset), offerRegion \(entity.offerRegion), customChannel \(hasCustomChannel)")

		autoQueueBeacon(beacon)
	}

	/// Append the mesh a beacon advertises to the scan queue when it isn't the active target,
	/// already queued, or already dwelled this session. `shiftToNextPreset()` consumes the queue
	/// with `removeFirst()`, so appending only extends future dwells and never disrupts the current
	/// one. Custom-channel targets carry the offered channel so the dwell tunes to that mesh.
	private func autoQueueBeacon(_ beacon: MeshBeacon) {
		guard beacon.hasOfferPreset, let preset = ModemPresets(rawValue: beacon.offerPreset.rawValue) else { return }
		let regionRaw = beacon.offerRegion != .unset ? beacon.offerRegion.rawValue : nil
		let hasCustomChannel = beacon.hasOfferChannel && !beacon.offerChannel.name.isEmpty
		let target = ScanTarget(
			preset: preset,
			regionRaw: regionRaw,
			channelName: hasCustomChannel ? beacon.offerChannel.name : nil,
			channelPSK: hasCustomChannel ? beacon.offerChannel.psk : nil
		)

		if activeTarget == target { return }
		if presetQueue.contains(target) { return }
		if session?.presetResults.contains(where: { $0.presetName == target.label }) == true { return }

		presetQueue.append(target)
		// Reflect public-preset targets in the user-visible selection; custom-channel targets are a
		// (preset + channel) pair that the ModemPresets-only selection can't represent.
		if !target.isCustomChannel, !selectedPresets.contains(preset) { selectedPresets.append(preset) }
		Logger.discovery.info("📡 [Discovery] Auto-queued beacon target: \(target.label)")
	}

	func handleMeshPacket(_ packet: MeshPacket, portNum: PortNum) {
		guard currentState == .dwell, let context = modelContext else { return }

		let fromNodeNum = Int64(packet.from)

		// Skip packets from the scanning node itself
		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		guard fromNodeNum != connectedNodeNum else { return }

		let hopLimit = Int(packet.hopLimit)
		let hopStart = Int(packet.hopStart)
		let hopsAway = hopStart > 0 ? hopStart - hopLimit : 0

		// Find or create discovered node for this preset
		var discoveredNode = session?.discoveredNodes.first(where: { $0.nodeNum == fromNodeNum && $0.presetName == activeTargetLabel })

		if discoveredNode == nil {
			let newNode = DiscoveredNodeEntity()
			newNode.nodeNum = fromNodeNum
			newNode.neighborType = hopsAway <= 1 ? "direct" : "mesh"
			newNode.hopCount = hopsAway
			newNode.snr = packet.rxSnr
			newNode.rssi = Int(packet.rxRssi)
			newNode.presetName = activeTargetLabel
			newNode.session = session
			newNode.presetResult = currentPresetResult
			context.insert(newNode)
			session?.discoveredNodes.append(newNode)
			currentPresetResult?.nodes.append(newNode)

			// Populate from existing NodeInfo
			if let knownNode = getNodeInfo(id: fromNodeNum, context: context) {
				newNode.shortName = knownNode.user?.shortName ?? ""
				newNode.longName = knownNode.user?.longName ?? ""
				// Infrastructure roles: Router (2), Router Late (11), Client Base (12)
				let role = Int(knownNode.user?.role ?? 0)
				newNode.isInfrastructure = [2, 11, 12].contains(role)
				if let pos = knownNode.positions.last {
					newNode.latitude = pos.latitude ?? 0.0
					newNode.longitude = pos.longitude ?? 0.0
				}
			}
			discoveredNode = newNode
		} else {
			// Update SNR/RSSI with latest
			discoveredNode?.snr = packet.rxSnr
			discoveredNode?.rssi = Int(packet.rxRssi)
			if hopsAway <= 1 {
				discoveredNode?.neighborType = "direct"
			}
		}

		// Classify by port number
		switch portNum {
		case .textMessageApp, .textMessageCompressedApp:
			discoveredNode?.messageCount += 1
			Logger.discovery.debug("📡 [Discovery] Text message from \(fromNodeNum)")
		case .telemetryApp:
			// Check for environment, air quality, detection sensor vs device metrics
			if let telemetry = try? Telemetry(serializedBytes: packet.decoded.payload) {
				switch telemetry.variant {
				case .environmentMetrics:
					discoveredNode?.sensorPacketCount += 1
					Logger.discovery.debug("📡 [Discovery] Environment telemetry from \(fromNodeNum)")
				case .airQualityMetrics:
					discoveredNode?.sensorPacketCount += 1
					Logger.discovery.debug("📡 [Discovery] Air quality telemetry from \(fromNodeNum)")
				case .deviceMetrics(let metrics):
					// 2-packet rule for DeviceMetrics (FR-008)
					var history = deviceMetricsHistory[fromNodeNum] ?? []
					history.append(DeviceMetricsEntry(
						timestamp: Date(),
						channelUtil: Double(metrics.channelUtilization),
						airUtilTx: Double(metrics.airUtilTx)
					))
					deviceMetricsHistory[fromNodeNum] = history
					Logger.discovery.debug("📡 [Discovery] DeviceMetrics from \(fromNodeNum) (count: \(history.count))")
				default:
					break
				}
			}
		case .positionApp:
			if let position = try? Position(serializedBytes: packet.decoded.payload) {
				let lat = Double(position.latitudeI) / 1e7
				let lon = Double(position.longitudeI) / 1e7
				if lat != 0.0 || lon != 0.0 {
					discoveredNode?.latitude = lat
					discoveredNode?.longitude = lon

					// Calculate distance from user
					if let userLat = session?.userLatitude, let userLon = session?.userLongitude,
					   userLat != 0.0, userLon != 0.0 {
						let userLocation = CLLocation(latitude: userLat, longitude: userLon)
						let nodeLocation = CLLocation(latitude: lat, longitude: lon)
						discoveredNode?.distanceFromUser = userLocation.distance(from: nodeLocation)
					}
				}
			}
		case .nodeinfoApp:
			if let nodeInfo = try? User(serializedBytes: packet.decoded.payload) {
				discoveredNode?.shortName = nodeInfo.shortName
				discoveredNode?.longName = nodeInfo.longName
			}
		case .detectionSensorApp:
			discoveredNode?.sensorPacketCount += 1
			Logger.discovery.debug("📡 [Discovery] Detection sensor from \(fromNodeNum)")
		case .adminApp:
			// LocalStats handling
			if let adminMsg = try? AdminMessage(serializedBytes: packet.decoded.payload),
			   case .getDeviceMetadataResponse = adminMsg.payloadVariant {
				// Stats data captured from device metadata
			}
		default:
			break
		}
	}

	// MARK: - Stop Scan (T018)

	func stopScan() async {
		guard isScanning else {
			Logger.discovery.warning("📡 [Discovery] Cannot stop scan — not scanning")
			return
		}

		Logger.discovery.info("📡 [Discovery] Stopping scan...")
		dwellTask?.cancel()
		reconnectTimeoutTask?.cancel()
		seedTask?.cancel()
		transitionTo(.restoring)

		// Save partial results (whatever was revealed so far)
		finalizePresetResult()
		session?.completionStatus = "stopped"

		// Restore home preset
		await restoreHomePreset()
	}
}

// MARK: - DiscoveryScanEngine + Finalization

extension DiscoveryScanEngine {

	// MARK: - Restore Home Preset

	func restoreHomePreset() async {
		// Restore the primary channel FIRST, while the link is up — channel changes don't reboot,
		// so this must happen before the LoRa restore below (which does reboot the radio). No-op
		// unless the scan switched the key to the default.
		await restorePrimaryChannel()

		// Restore the full config snapshot captured at scan start — preset, frequency slot,
		// overrides and all — rather than rebuilding a partial config that would drop the
		// user's frequency slot and other settings (#1952).
		guard let homeLoRaConfig, let accessoryManager, let context = modelContext else {
			Logger.discovery.info("📡 [Discovery] No home config to restore → Idle")
			cleanupAndIdle()
			return
		}

		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		guard let connectedNode = getNodeInfo(id: connectedNodeNum, context: context),
			  let fromUser = connectedNode.user,
			  let toUser = connectedNode.user else {
			Logger.discovery.error("📡 [Discovery] Cannot restore home config — no connected node")
			cleanupAndIdle()
			return
		}

		do {
			_ = try await accessoryManager.saveLoRaConfig(config: homeLoRaConfig, fromUser: fromUser, toUser: toUser)
			Logger.discovery.info("📡 [Discovery] Restored home LoRa config — preset: \(self.homePreset?.name ?? "unknown"), frequency slot: \(homeLoRaConfig.channelNum)")
		} catch {
			Logger.discovery.error("📡 [Discovery] Failed to restore home config: \(error.localizedDescription)")
		}

		cleanupAndIdle()
	}

	// MARK: - Session Finalization (T019)

	private func finalizePresetResult() {
		guard let result = currentPresetResult else { return }

		let presetNodes = result.nodes
		result.uniqueNodesFound = presetNodes.count
		result.directNeighborCount = presetNodes.filter { $0.neighborType == "direct" }.count
		result.meshNeighborCount = presetNodes.filter { $0.neighborType == "mesh" }.count
		result.infrastructureNodeCount = presetNodes.filter { $0.isInfrastructure }.count
		result.messageCount = presetNodes.reduce(0) { $0 + $1.messageCount }
		result.sensorPacketCount = presetNodes.reduce(0) { $0 + $1.sensorPacketCount }

		// Read local stats from SwiftData (already persisted by main telemetry pipeline)
		captureLocalStats()

		// Compute channel utilization and airtime from 2-packet rule data (supplements local stats)
		var channelUtils: [Double] = []
		var airtimeRates: [Double] = []

		for nodeNum in presetNodes.map(\.nodeNum) {
			if let history = deviceMetricsHistory[nodeNum], history.count >= 2 {
				let last = history[history.count - 1]
				let prev = history[history.count - 2]
				channelUtils.append(last.channelUtil)
				let elapsed = last.timestamp.timeIntervalSince(prev.timestamp)
				if elapsed > 0 {
					let rate = (last.airUtilTx - prev.airUtilTx) / elapsed
					airtimeRates.append(rate)
				}
			}
		}

		// Only overwrite with 2-packet rule data if available; preserve local stats values otherwise
		if !channelUtils.isEmpty {
			result.averageChannelUtilization = channelUtils.reduce(0, +) / Double(channelUtils.count)
		}
		if !airtimeRates.isEmpty {
			result.averageAirtimeRate = airtimeRates.reduce(0, +) / Double(airtimeRates.count)
		}

		Logger.discovery.info("📡 [Discovery] Preset \(result.presetName) finalized: \(result.uniqueNodesFound) nodes, \(result.directNeighborCount) direct, \(result.meshNeighborCount) mesh")
	}

	private func finalizeSession() async {
		guard let session else { return }

		// Finalize current preset if needed
		finalizePresetResult()

		// Compute session-level aggregates
		let allNodes = session.discoveredNodes
		let uniqueNodeNums = Set(allNodes.map(\.nodeNum))
		session.totalUniqueNodes = uniqueNodeNums.count
		session.totalTextMessages = allNodes.reduce(0) { $0 + $1.messageCount }
		session.totalSensorPackets = allNodes.reduce(0) { $0 + $1.sensorPacketCount }
		session.furthestNodeDistance = allNodes.map(\.distanceFromUser).max() ?? 0.0

		let presetUtils = session.presetResults.map(\.averageChannelUtilization).filter { $0 > 0 }
		session.averageChannelUtilization = presetUtils.isEmpty ? 0.0 : presetUtils.reduce(0, +) / Double(presetUtils.count)

		session.completionStatus = "complete"

		try? modelContext?.save()

		Logger.discovery.info("📡 [Discovery] Session finalized: \(session.totalUniqueNodes) unique nodes across \(session.presetResults.count) presets")

		transitionTo(.complete)
	}

	// MARK: - App Termination Edge Case (T020)

	func checkForInterruptedSessions(context: ModelContext) {
		let descriptor = FetchDescriptor<DiscoverySessionEntity>(
			predicate: #Predicate { $0.completionStatus == "inProgress" }
		)
		if let interrupted = try? context.fetch(descriptor) {
			for session in interrupted {
				session.completionStatus = "interrupted"
				Logger.discovery.warning("📡 [Discovery] Marked interrupted session from \(session.timestamp)")
			}
			try? context.save()
		}
	}

	// MARK: - State Transitions

	private func transitionTo(_ newState: DiscoveryScanState) {
		let oldState = currentState
		currentState = newState
		Logger.discovery.info("📡 [Discovery] State: \(oldState) → \(newState)")
	}

	private func cleanupAndIdle() {
		dwellTask?.cancel()
		reconnectTimeoutTask?.cancel()
		connectionObserver?.cancel()
		accessoryManager?.discoveryScanEngine = nil
		deviceMetricsHistory = [:]
		presetDwellStart = nil
		seedFromExistingData = false
		seedTask?.cancel()
		seedTask = nil
		awaitingDisconnect = false
		interruptedDwellRemaining = nil
		// Clear both home snapshots together so a later scan that starts without a readable
		// LoRa config doesn't inherit a stale preset/config from a previous scan (#1952).
		homePreset = nil
		homeLoRaConfig = nil
		homePrimaryChannel = nil
		activeTarget = nil
		activeTargetLabel = ""
		scanChannelIsCustom = false
		transitionTo(.idle)
	}

	// MARK: - Read Local Stats from SwiftData

	private func captureLocalStats() {
		guard let context = modelContext, let result = currentPresetResult else { return }

		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		guard let connectedNode = getNodeInfo(id: connectedNodeNum, context: context) else {
			Logger.discovery.warning("📡 [Discovery] Cannot read local stats — no connected node")
			return
		}

		// All local stats (metricsType == 4) persisted by MeshPackets, oldest → newest.
		let allLocalStats = connectedNode.telemetries
			.filter { $0.metricsType == 4 }
			.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }

		// Prefer the samples that arrived during THIS preset's dwell — they reflect the preset's
		// frequency. Fall back to the single most recent sample if none landed in the window.
		let windowStart = presetDwellStart ?? .distantPast
		let windowed = allLocalStats.filter { ($0.time ?? .distantPast) >= windowStart }
		let samples = windowed.isEmpty ? Array(allLocalStats.suffix(1)) : windowed

		guard let latest = samples.last else {
			Logger.discovery.info("📡 [Discovery] No local stats telemetry found for connected node")
			return
		}

		// Channel utilization and airtime — average the point-in-time readings over the window.
		let channelUtils = samples.compactMap { $0.channelUtilization.map(Double.init) }
		if !channelUtils.isEmpty {
			result.averageChannelUtilization = channelUtils.reduce(0, +) / Double(channelUtils.count)
		}
		let airtimes = samples.compactMap { $0.airUtilTx.map(Double.init) }
		if !airtimes.isEmpty {
			result.averageAirtimeRate = airtimes.reduce(0, +) / Double(airtimes.count)
		}

		// Noise floor (dBm) — average over the window when the local-stats packets carry it.
		// Frequency-specific, so this characterizes how quiet the preset's channel was.
		let noiseFloors = samples.compactMap { $0.noiseFloor.map(Double.init) }
		if !noiseFloors.isEmpty {
			result.averageNoiseFloor = noiseFloors.reduce(0, +) / Double(noiseFloors.count)
			result.noiseFloorSampleCount = noiseFloors.count
		}

		// Raw local stats — counters are cumulative, so use the latest sample.
		result.numPacketsTx = Int(latest.numPacketsTx)
		result.numPacketsRx = Int(latest.numPacketsRx)
		result.numPacketsRxBad = Int(latest.numPacketsRxBad)
		result.numRxDupe = Int(latest.numRxDupe)
		result.numTxRelay = Int(latest.numTxRelay)
		result.numTxRelayCanceled = Int(latest.numTxRelayCanceled)
		result.numOnlineNodes = Int(latest.numOnlineNodes)
		result.numTotalNodes = Int(latest.numTotalNodes)
		if let uptime = latest.uptimeSeconds {
			result.uptimeSeconds = Int(uptime)
		}

		// Packet success/failure rates
		let totalTx = Int(latest.numPacketsTx)
		let totalRx = Int(latest.numPacketsRx)
		let badRx = Int(latest.numPacketsRxBad)
		let totalPackets = totalTx + totalRx
		if totalPackets > 0 {
			let goodPackets = totalTx + totalRx - badRx
			result.packetSuccessRate = Double(goodPackets) / Double(totalPackets)
			result.packetFailureRate = Double(badRx) / Double(totalPackets)
		}

		let noiseFloorLog = result.noiseFloorSampleCount > 0 ? String(format: "%.0f dBm (%d samples)", result.averageNoiseFloor, result.noiseFloorSampleCount) : "n/a"
		Logger.discovery.info("📡 [Discovery] Local stats captured (\(samples.count) sample(s)) — Ch Util: \(String(format: "%.1f", result.averageChannelUtilization))%, Airtime: \(String(format: "%.2f", result.averageAirtimeRate))%, Noise Floor: \(noiseFloorLog), Tx: \(totalTx), Rx: \(totalRx), Bad: \(badRx)")
	}
}

// MARK: - DiscoveryScanEngine + Current Preset Scan

extension DiscoveryScanEngine {

	/// True while the active run is a seeded "Analyze Current Preset" pass — built from the full
	/// local history rather than a live multi-preset scan. Read-only mirror of the private
	/// `seedFromExistingData` flag so the setup/progress UI can show the collected-data span
	/// alongside the short (~60s) dwell timer.
	var isSeededRun: Bool { seedFromExistingData }

	/// Starts a discovery scan limited to the radio's CURRENT modem preset, seeded with everything
	/// already in SwiftData. The radio is already on this preset, so there's no config change or
	/// reboot — the dwell begins immediately and `seedDiscoveredNodesFromDatabase()` folds in all
	/// accumulated data so the run reflects "one long run" on the current preset, then live packets
	/// during the dwell keep refining it.
	func startCurrentPresetScan() async {
		guard currentState == .idle else {
			Logger.discovery.warning("📡 [Discovery] Cannot start current-preset scan — not idle")
			return
		}
		guard let context = modelContext else {
			Logger.discovery.error("📡 [Discovery] Cannot start current-preset scan — no model context")
			return
		}

		// Prefer the connected node's live LoRa preset. When no node/config is available — e.g.
		// running offline with no radio connected — fall back to the last preset the app persisted
		// in UserDefaults, then to LongFast. This lets "Analyze Current Preset" work fully offline.
		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		let preset = (getNodeInfo(id: connectedNodeNum, context: context)?.loRaConfig?.modemPreset)
			.flatMap { ModemPresets(rawValue: Int($0)) }
			?? ModemPresets(rawValue: UserDefaults.modemPreset)
			?? .longFast

		selectedPresets = [preset]
		seedFromExistingData = true
		// The report comes from seeded history — only dwell briefly to fold in live packets.
		dwellDuration = Self.currentPresetScanDwell
		Logger.discovery.info("📡 [Discovery] Starting current-preset scan on \(preset.name, privacy: .public) (seeded; \(Int(Self.currentPresetScanDwell))s dwell)")
		await startScan()
	}

	/// Reveals a discovered node for every node already known in SwiftData onto the map
	/// progressively over the dwell — an accelerated playback of the accumulated history rather
	/// than dumping them all at once. Names, hops/role, last position, and per-node message/sensor
	/// counts are filled in; nodes a live packet already added this dwell are skipped. Used by
	/// `startCurrentPresetScan()`.
	func revealSeededNodesFromDatabase() async {
		guard let context = modelContext, let session, let result = currentPresetResult else { return }
		let presetName = activePreset?.name ?? result.presetName
		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)

		// Per-node text-message counts (single fetch, grouped by sender).
		var messageCounts: [Int64: Int] = [:]
		if let messages = try? context.fetch(FetchDescriptor<MessageEntity>()) {
			for msg in messages {
				if let from = msg.fromUser?.num { messageCounts[from, default: 0] += 1 }
			}
		}

		let allNodes = (try? context.fetch(FetchDescriptor<NodeInfoEntity>())) ?? []
		// Skip the connected node and any node a live packet already added this dwell.
		let candidates = allNodes.filter { node in
			node.num != connectedNodeNum
				&& !session.discoveredNodes.contains(where: { $0.nodeNum == node.num && $0.presetName == presetName })
		}
		guard !candidates.isEmpty else { return }

		let userLat = session.userLatitude
		let userLon = session.userLongitude

		// Snapshot every value the reveal needs in one synchronous pass, BEFORE the timed loop.
		// The loop below awaits between batches for most of the dwell; live ingestion keeps
		// mutating the store the whole time, and touching a `NodeInfoEntity`/`PositionEntity`
		// whose row was pruned mid-reveal traps in SwiftData's persisted-property accessor
		// (reproduced under a 100 pkt/s TCP stress replay). Plain values can't be invalidated.
		struct SeededNodeSnapshot {
			let nodeNum: Int64
			let shortName: String
			let longName: String
			let hopCount: Int
			let snr: Float
			let rssi: Int
			let isInfrastructure: Bool
			let latitude: Double
			let longitude: Double
			let messageCount: Int
			let sensorPacketCount: Int
		}
		let snapshots: [SeededNodeSnapshot] = candidates.map { node in
			SeededNodeSnapshot(
				nodeNum: node.num,
				shortName: node.user?.shortName ?? "",
				longName: node.user?.longName ?? "",
				hopCount: Int(node.hopsAway),
				snr: node.snr,
				rssi: Int(node.rssi),
				// Infrastructure roles: Router (2), Router Late (11), Client Base (12)
				isInfrastructure: [2, 11, 12].contains(Int(node.user?.role ?? 0)),
				latitude: node.latestPosition?.latitude ?? 0.0,
				longitude: node.latestPosition?.longitude ?? 0.0,
				messageCount: messageCounts[node.num] ?? 0,
				// Sensor packets ≈ environment (1) + air-quality (3) telemetry the node has reported,
				// matching the live scan's sensorPacketCount (.environmentMetrics + .airQualityMetrics).
				sensorPacketCount: node.telemetries.filter { $0.metricsType == 1 || $0.metricsType == 3 }.count
			)
		}

		// Spread the reveal across ~85% of the dwell (so it finishes before finalize), in batches
		// over ~120 ticks for a smooth, accelerated fill regardless of mesh size.
		let revealWindow = max(2.0, dwellDuration * 0.85)
		let ticks = 120.0
		let tick = max(0.08, revealWindow / ticks)
		let batchSize = max(1, Int((Double(snapshots.count) / ticks).rounded(.up)))

		var index = 0
		var seeded = 0
		while index < snapshots.count {
			if Task.isCancelled { break }
			// A device switch can reset the container mid-scan; the session/result entities die
			// with it. Stop revealing rather than trap on the next relationship write.
			guard session.modelContext != nil, result.modelContext != nil else { break }
			let end = min(index + batchSize, snapshots.count)
			for snapshot in snapshots[index..<end] {
				let dn = DiscoveredNodeEntity()
				dn.nodeNum = snapshot.nodeNum
				dn.shortName = snapshot.shortName
				dn.longName = snapshot.longName
				dn.hopCount = snapshot.hopCount
				dn.neighborType = snapshot.hopCount <= 1 ? "direct" : "mesh"
				dn.snr = snapshot.snr
				dn.rssi = snapshot.rssi
				dn.isInfrastructure = snapshot.isInfrastructure
				dn.latitude = snapshot.latitude
				dn.longitude = snapshot.longitude
				if userLat != 0.0 || userLon != 0.0, snapshot.latitude != 0.0 || snapshot.longitude != 0.0 {
					let userLocation = CLLocation(latitude: userLat, longitude: userLon)
					let nodeLocation = CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
					dn.distanceFromUser = userLocation.distance(from: nodeLocation)
				}
				dn.messageCount = snapshot.messageCount
				dn.sensorPacketCount = snapshot.sensorPacketCount
				dn.presetName = presetName
				dn.session = session
				dn.presetResult = result
				context.insert(dn)
				session.discoveredNodes.append(dn)
				result.nodes.append(dn)
				seeded += 1
			}
			index = end
			if index < snapshots.count {
				try? await Task.sleep(for: .seconds(tick))
			}
		}

		Logger.discovery.info("📡 [Discovery] Revealed \(seeded) seeded node(s) onto the map for \(presetName, privacy: .public)")
	}
}

// MARK: - DiscoveryScanEngine + Primary Channel

extension DiscoveryScanEngine {

	/// Builds a complete `Channel` proto from a stored `ChannelEntity`, preserving name, key,
	/// up/downlink, and position precision so a saved copy round-trips the user's channel exactly.
	/// Internal (not private) so the snapshot/restore fidelity can be unit-tested.
	func channelProto(from entity: ChannelEntity) -> Channel {
		var channel = Channel()
		channel.index = entity.index
		channel.role = Channel.Role(rawValue: Int(entity.role)) ?? .secondary
		channel.settings.name = entity.name ?? ""
		channel.settings.psk = entity.psk ?? Data()
		channel.settings.uplinkEnabled = entity.uplinkEnabled
		channel.settings.downlinkEnabled = entity.downlinkEnabled
		channel.settings.moduleSettings.positionPrecision = UInt32(entity.positionPrecision)
		return channel
	}

	/// Whether the primary channel is already the default public channel — i.e. both the default key
	/// (none, empty, or the single `0x01` byte) AND the default (empty) name. The public mesh uses
	/// the empty name (the firmware renders it as "LongFast"); a custom name produces a different
	/// channel hash and a different derived frequency, so it must be defaulted for the scan too.
	private static func isDefaultPublicChannel(_ channel: ChannelEntity) -> Bool {
		let keyIsDefault = channel.psk == nil || channel.psk?.isEmpty == true || channel.psk == defaultChannelKey
		let nameIsDefault = channel.name == nil || channel.name?.isEmpty == true
		return keyIsDefault && nameIsDefault
	}

	/// If the connected radio's primary channel isn't the default public channel, snapshot it and
	/// send a copy with the default key AND default (empty) name so the scan can both decode the
	/// public mesh and derive the public-mesh frequency for each preset (the firmware derives the
	/// frequency from the primary channel name + preset). A no-op when the primary is already the
	/// default public channel. `saveChannel` doesn't reboot the radio, so this applies immediately
	/// while the link is up; `restorePrimaryChannel()` puts the original channel back when the scan
	/// finishes.
	private func prepareDefaultPublicChannel(connectedNode: NodeInfoEntity?) async {
		guard let accessoryManager,
			  let connectedNode,
			  let fromUser = connectedNode.user,
			  let primary = connectedNode.myInfo?.channels.first(where: { $0.role == 1 }) else { return }

		guard !Self.isDefaultPublicChannel(primary) else { return }

		// Snapshot the real primary channel so it can be restored verbatim after the scan.
		homePrimaryChannel = channelProto(from: primary)

		var scanChannel = channelProto(from: primary)
		scanChannel.settings.psk = Self.defaultChannelKey
		scanChannel.settings.name = ""
		do {
			_ = try await accessoryManager.saveChannel(channel: scanChannel, fromUser: fromUser, toUser: fromUser)
			Logger.discovery.info("📡 [Discovery] Primary channel temporarily switched to the default public channel for the scan")
		} catch {
			// Leave the snapshot in place so restore still runs; surface the failure.
			Logger.discovery.error("📡 [Discovery] Failed to set default public channel: \(error.localizedDescription)")
		}
	}

	/// Tunes the primary channel for a scan target. Custom-channel beacon targets switch the radio
	/// to the offered channel (name + PSK) so the dwell lands on that mesh's frequency and can
	/// decode it; public/manual targets switch back to the default public channel only when a
	/// previous custom target left the radio tuned away. Channel changes don't reboot, so this runs
	/// while the link is up, ahead of the (rebooting) preset change. The user's real channel is
	/// snapshotted the first time we tune away and restored verbatim in `restorePrimaryChannel()`.
	private func applyChannel(for target: ScanTarget) async {
		guard let accessoryManager, let context = modelContext else { return }
		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		guard let connectedNode = getNodeInfo(id: connectedNodeNum, context: context),
			  let fromUser = connectedNode.user,
			  let primary = connectedNode.myInfo?.channels.first(where: { $0.role == 1 }) else { return }

		if target.isCustomChannel, let name = target.channelName, let psk = target.channelPSK {
			// Snapshot the real primary once so restore returns to it, even if we began the scan on
			// the default public channel (where prepareDefaultPublicChannel took no snapshot).
			if homePrimaryChannel == nil { homePrimaryChannel = channelProto(from: primary) }
			var channel = channelProto(from: primary)
			channel.settings.name = name
			channel.settings.psk = psk
			do {
				_ = try await accessoryManager.saveChannel(channel: channel, fromUser: fromUser, toUser: fromUser)
				scanChannelIsCustom = true
				Logger.discovery.info("📡 [Discovery] Tuned primary channel to beacon channel for the scan")
			} catch {
				Logger.discovery.error("📡 [Discovery] Failed to set beacon channel: \(error.localizedDescription)")
			}
		} else if scanChannelIsCustom {
			// Public/manual target following a custom one: revert to the default public channel so the
			// dwell hears the public mesh again.
			var channel = channelProto(from: primary)
			channel.settings.name = ""
			channel.settings.psk = Self.defaultChannelKey
			do {
				_ = try await accessoryManager.saveChannel(channel: channel, fromUser: fromUser, toUser: fromUser)
				scanChannelIsCustom = false
				Logger.discovery.info("📡 [Discovery] Reverted primary channel to the default public channel")
			} catch {
				Logger.discovery.error("📡 [Discovery] Failed to revert to public channel: \(error.localizedDescription)")
			}
		}
	}

	/// Restores the user's original primary channel captured in `prepareDefaultKeyChannel`. No-op
	/// unless the scan switched the key. Called before the LoRa restore (which reboots) so it lands
	/// while the link is up.
	private func restorePrimaryChannel() async {
		guard let homePrimaryChannel, let accessoryManager, let context = modelContext else { return }
		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		guard let connectedNode = getNodeInfo(id: connectedNodeNum, context: context),
			  let fromUser = connectedNode.user else {
			Logger.discovery.error("📡 [Discovery] Cannot restore primary channel — no connected node")
			self.homePrimaryChannel = nil
			return
		}
		do {
			_ = try await accessoryManager.saveChannel(channel: homePrimaryChannel, fromUser: fromUser, toUser: fromUser)
			Logger.discovery.info("📡 [Discovery] Restored the primary channel key after the scan")
		} catch {
			Logger.discovery.error("📡 [Discovery] Failed to restore primary channel: \(error.localizedDescription)")
		}
		self.homePrimaryChannel = nil
	}
}
