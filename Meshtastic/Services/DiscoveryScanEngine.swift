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
import SwiftData
import SwiftUI

// MARK: - Scan State

enum DiscoveryScanState: Equatable {
	case idle
	case shifting
	case reconnecting
	case dwell
	case analysis
	case complete
	case paused
	case restoring
}

// MARK: - DiscoveryScanEngine

@MainActor @Observable
final class DiscoveryScanEngine {

	// MARK: Published State

	var currentState: DiscoveryScanState = .idle
	var activePreset: ModemPresets?
	var dwellTimeRemaining: TimeInterval = 0
	var selectedPresets: [ModemPresets] = []
	var dwellDuration: TimeInterval = 900 // 15 minutes default
	var session: DiscoverySessionEntity?
	var errorMessage: String?

	// MARK: Internal State

	private var homePreset: ModemPresets?
	private var presetQueue: [ModemPresets] = []
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
			Logger.discovery.warning("📡 [Discovery] Cannot start scan — not idle (state: \(String(describing: self.currentState)))")
			return
		}
		guard !selectedPresets.isEmpty else {
			Logger.discovery.warning("📡 [Discovery] Cannot start scan — no presets selected")
			return
		}
		guard let accessoryManager, accessoryManager.isConnected else {
			Logger.discovery.warning("📡 [Discovery] Cannot start scan — radio not connected")
			return
		}
		guard let context = modelContext else {
			Logger.discovery.error("📡 [Discovery] Cannot start scan — no model context")
			return
		}

		// Clear any previous error
		errorMessage = nil

		// Record home preset from current LoRa config
		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		let connectedNode = getNodeInfo(id: connectedNodeNum, context: context)
		if let loraConfig = connectedNode?.loRaConfig {
			homePreset = ModemPresets(rawValue: Int(loraConfig.modemPreset))
		}

		// Create session
		let newSession = DiscoverySessionEntity()
		newSession.presetsScanned = selectedPresets.map(\.name).joined(separator: ",")
		newSession.homePreset = homePreset?.name ?? ""
		newSession.completionStatus = "inProgress"

		// Record user position if available
		if let position = connectedNode?.positions.last {
			newSession.userLatitude = position.latitude ?? 0.0
			newSession.userLongitude = position.longitude ?? 0.0
		}

		context.insert(newSession)
		session = newSession

		// Build preset queue
		presetQueue = selectedPresets
		deviceMetricsHistory = [:]

		Logger.discovery.info("📡 [Discovery] Scan started with \(self.selectedPresets.count) presets, dwell: \(self.dwellDuration)s")

		// Register engine with AccessoryManager for packet forwarding
		accessoryManager.discoveryScanEngine = self

		// Observe connection state changes
		observeConnectionState()

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

		let nextPreset = presetQueue.removeFirst()
		activePreset = nextPreset
		transitionTo(.shifting)

		// Create preset result
		let presetResult = DiscoveryPresetResultEntity()
		presetResult.presetName = nextPreset.name
		presetResult.dwellDurationSeconds = Int(dwellDuration)
		presetResult.session = session
		session?.presetResults.append(presetResult)
		currentPresetResult = presetResult
		modelContext?.insert(presetResult)

		Logger.discovery.info("📡 [Discovery] Shifting to preset: \(nextPreset.name)")

		// Check if already on this preset (skip config change)
		if accessoryManager != nil, let context = modelContext {
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
		await sendPresetChange(nextPreset)
	}

	// MARK: - Send Preset Change

	private func sendPresetChange(_ preset: ModemPresets) async {
		guard let accessoryManager, let context = modelContext else { return }

		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		guard let connectedNode = getNodeInfo(id: connectedNodeNum, context: context),
			  let fromUser = connectedNode.user,
			  let toUser = connectedNode.user else {
			Logger.discovery.error("📡 [Discovery] Cannot send preset change — no connected node/user")
			return
		}

		var loraConfig = Config.LoRaConfig()
		loraConfig.modemPreset = preset.protoEnumValue()

		// Copy existing config values if available
		if let existingConfig = connectedNode.loRaConfig {
			loraConfig.region = Config.LoRaConfig.RegionCode(rawValue: Int(existingConfig.regionCode)) ?? .unset
			loraConfig.hopLimit = UInt32(existingConfig.hopLimit)
			loraConfig.txEnabled = existingConfig.txEnabled
			loraConfig.txPower = existingConfig.txPower
			loraConfig.usePreset = existingConfig.usePreset
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

	private func startReconnectTimeout() {
		reconnectTimeoutTask?.cancel()
		reconnectTimeoutTask = Task { [weak self] in
			do {
				try await Task.sleep(for: .seconds(120))
				guard let self, self.currentState == .reconnecting else { return }
				Logger.discovery.warning("📡 [Discovery] Reconnect timeout (120s) → Paused")
				self.transitionTo(.paused)
			} catch {
				// Cancelled — expected when reconnection succeeds
			}
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
			let existingNode = session?.discoveredNodes.first(where: { $0.nodeNum == nodeNum && $0.presetName == activePreset?.name ?? "" })

			if existingNode == nil {
				let discoveredNode = DiscoveredNodeEntity()
				discoveredNode.nodeNum = nodeNum
				discoveredNode.neighborType = "mesh"
				discoveredNode.snr = neighbor.snr
				discoveredNode.presetName = activePreset?.name ?? ""
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
		var discoveredNode = session?.discoveredNodes.first(where: { $0.nodeNum == fromNodeNum && $0.presetName == activePreset?.name ?? "" })

		if discoveredNode == nil {
			let newNode = DiscoveredNodeEntity()
			newNode.nodeNum = fromNodeNum
			newNode.neighborType = hopsAway <= 1 ? "direct" : "mesh"
			newNode.hopCount = hopsAway
			newNode.snr = packet.rxSnr
			newNode.rssi = Int(packet.rxRssi)
			newNode.presetName = activePreset?.name ?? ""
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
		transitionTo(.restoring)

		// Save partial results
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
		guard let homePreset, let accessoryManager, let context = modelContext else {
			Logger.discovery.info("📡 [Discovery] No home preset to restore → Idle")
			cleanupAndIdle()
			return
		}

		let connectedNodeNum = Int64(UserDefaults.preferredPeripheralNum)
		guard let connectedNode = getNodeInfo(id: connectedNodeNum, context: context),
			  let fromUser = connectedNode.user,
			  let toUser = connectedNode.user else {
			Logger.discovery.error("📡 [Discovery] Cannot restore home preset — no connected node")
			cleanupAndIdle()
			return
		}

		var loraConfig = Config.LoRaConfig()
		loraConfig.modemPreset = homePreset.protoEnumValue()

		if let existingConfig = connectedNode.loRaConfig {
			loraConfig.region = Config.LoRaConfig.RegionCode(rawValue: Int(existingConfig.regionCode)) ?? .unset
			loraConfig.hopLimit = UInt32(existingConfig.hopLimit)
			loraConfig.txEnabled = existingConfig.txEnabled
			loraConfig.txPower = existingConfig.txPower
			loraConfig.usePreset = existingConfig.usePreset
		}

		do {
			_ = try await accessoryManager.saveLoRaConfig(config: loraConfig, fromUser: fromUser, toUser: toUser)
			Logger.discovery.info("📡 [Discovery] Restored home preset: \(homePreset.name)")
		} catch {
			Logger.discovery.error("📡 [Discovery] Failed to restore home preset: \(error.localizedDescription)")
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
		Logger.discovery.info("📡 [Discovery] State: \(String(describing: oldState)) → \(String(describing: newState))")
	}

	private func cleanupAndIdle() {
		dwellTask?.cancel()
		reconnectTimeoutTask?.cancel()
		connectionObserver?.cancel()
		accessoryManager?.discoveryScanEngine = nil
		deviceMetricsHistory = [:]
		awaitingDisconnect = false
		interruptedDwellRemaining = nil
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

		// Read most recent local stats (metricsType == 4) persisted by MeshPackets
		let localStatsTelemetry = connectedNode.telemetries
			.filter { $0.metricsType == 4 }
			.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }

		guard let latest = localStatsTelemetry.last else {
			Logger.discovery.info("📡 [Discovery] No local stats telemetry found for connected node")
			return
		}

		// Channel utilization and airtime
		if let channelUtil = latest.channelUtilization {
			result.averageChannelUtilization = Double(channelUtil)
		}
		if let airtime = latest.airUtilTx {
			result.averageAirtimeRate = Double(airtime)
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

		Logger.discovery.info("📡 [Discovery] Local stats captured — Ch Util: \(latest.channelUtilization ?? 0)%, Airtime: \(latest.airUtilTx ?? 0)%, Tx: \(totalTx), Rx: \(totalRx), Bad: \(badRx)")
	}
}
