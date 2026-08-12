//
//  DeviceProfileImporter.swift
//  Meshtastic
//
//  The effectful half of "Import Device Configuration": walks a `DeviceProfileImportPlan` in order and
//  sends each item to the radio. All ordering, abort-on-failure, and terminal-reboot logic lives in the
//  engine here; the `ProfileApplyGateway` seam turns each item into the matching AccessoryManager admin
//  send, so the engine can be unit-tested with a mock gateway and no device.
//

import Foundation
import MeshtasticProtobufs
import OSLog

// MARK: - Gateway seam

/// Turns a single `ImportItem` into an admin send. The production conformer forwards to the existing
/// `save*Config` / `saveUser` / `saveChannelSet` / `setFixedPosition` calls; tests use a mock to assert
/// order and abort behavior. All work happens on the main actor because it drives `AccessoryManager`.
@MainActor
protocol ProfileApplyGateway {
	/// Whether the radio is currently connected. The engine checks this before each send.
	var isConnected: Bool { get }
	/// Applies one item, throwing on a genuine failure. Reboot-induced disconnects for the terminal
	/// Channels & LoRa item are absorbed by the conformer, so a throw here always means a real failure.
	func apply(_ item: ImportItem) async throws
	/// Opens the firmware edit transaction (`begin_edit_settings`). While one is open the firmware
	/// defers every config save, reboot, and Bluetooth teardown until the commit.
	func beginEditSettings() async throws
	/// Closes the transaction (`commit_edit_settings`), which performs a single save and one reboot.
	func commitEditSettings() async throws
}

// MARK: - Result

/// The outcome of an import run. `failed` is set for the first item that failed (the run stops there);
/// `skipped` lists items that were never attempted as a result.
struct DeviceProfileImportResult {
	var applied: [ImportItemKind] = []
	var skipped: [ImportItemKind] = []
	var failed: (kind: ImportItemKind, message: String)? = nil
	/// True when the radio will reboot as a result of this run and so will disconnect briefly.
	var rebooting: Bool = false
	/// True once `begin_edit_settings` was accepted, so the firmware deferred saves for this run.
	var usedTransaction: Bool = false
	/// True once `commit_edit_settings` was sent and either acked or dropped by the expected reboot.
	var transactionCommitted: Bool = false
	/// True when the commit could not be confirmed: either the link was already down when we tried to
	/// send it (so the radio may still hold an open transaction, deferring every later write from any
	/// client) or the send failed while still connected. Distinct from `transactionCommitted` because a
	/// lost ack during the commit's own reboot is the normal, successful path.
	var commitUnconfirmed: Bool = false
	/// Items that could not be applied because the commit tore down the transport, and which need a
	/// reconnect and a second pass. These are NOT failures: the committed profile is already safe.
	var requiresReconnect: [ImportItemKind] = []
	/// True when the run stopped because it was cancelled (user tapped Cancel or the task was cancelled)
	/// rather than failing. The current and remaining items are recorded as `skipped`, not `failed`.
	var wasCancelled: Bool = false

	var isCompleteSuccess: Bool { failed == nil && !wasCancelled }
}

// MARK: - Engine

enum DeviceProfileImporter {

	/// Pause between consecutive admin sends.
	///
	/// Measured on a Heltec V4 (ESP32-S3): an unpaced burst of 8 module-config writes over ~0.9s had
	/// only 5 processed on firmware 2.7.27 and 7 on 2.8.0, with the rest dropped and still acked. The
	/// same burst inside a transaction at roughly this spacing landed 8 of 8 across repeated runs,
	/// because deferring the flash write makes each message cheap enough for the radio to keep up.
	/// 150ms keeps a 25-item profile under ~4s while staying well clear of the drop threshold.
	static let defaultSendInterval: Duration = .milliseconds(150)

	/// Applies the selected sections of a plan inside a firmware edit transaction, aborting on the first
	/// failure.
	///
	/// The run is `begin_edit_settings` → items → `commit_edit_settings`. Without that bracket the
	/// firmware treats each send as a standalone write: it saves to flash, schedules a reboot, and tears
	/// down Bluetooth for nearly every config (AdminModule.cpp:1161, :1178, :1773, :1779), which drops the
	/// link a few items into a profile restore. With the transaction open all of that is deferred to a
	/// single save and one reboot at the commit.
	///
	/// MQTT and Serial are deliberately applied AFTER the commit. See `apply` for why.
	/// - Parameters:
	///   - plan: the parsed import plan.
	///   - selection: the sections the user chose to import.
	///   - gateway: the send seam (production or mock).
	///   - sendInterval: pause between consecutive sends. The radio drops writes it cannot process in
	///       time and still acks them, so an unpaced burst loses config silently.
	///   - sleep: injectable delay, so tests exercise the pacing logic without real time passing.
	///   - progress: called just before each item is sent, with (item, zero-based index, total count).
	/// - Returns: what was applied, skipped, or failed, and whether the radio is rebooting.
	@MainActor
	static func apply(
		plan: DeviceProfileImportPlan,
		selection: Set<ImportSection>,
		gateway: ProfileApplyGateway,
		sendInterval: Duration = defaultSendInterval,
		sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
		progress: ((ImportItem, Int, Int) -> Void)? = nil
	) async -> DeviceProfileImportResult {
		var result = DeviceProfileImportResult()
		let all = plan.items(for: selection)
		guard !all.isEmpty else { return result }

		// MQTT and Serial run AFTER the commit, outside the transaction. Firmware calls disableBluetooth()
		// for exactly those two regardless of an open transaction (AdminModule.cpp:1191 and :1207), unlike
		// every other config path which gates that call on !hasOpenEditTransaction. Applying them inside
		// the transaction would drop the BLE link before commit_edit_settings could arrive, and because the
		// firmware defers every save until commit, the ENTIRE import would be lost rather than just those
		// two items. Running them after the commit means the rest of the profile is already persisted
		// before the link is put at risk. Cost: a second reboot when the profile carries either one.
		let deferredKinds: Set<ImportItemKind> = [.mqtt, .serial]
		let transactional = all.filter { !deferredKinds.contains($0.kind) }
		let deferredItems = all.filter { deferredKinds.contains($0.kind) }
		let total = all.count

		// 1. Open the transaction before anything is sent.
		guard gateway.isConnected else {
			result.failed = (all[0].kind, "The radio disconnected before this step could be applied.")
			result.skipped = all.dropFirst().map(\.kind)
			return result
		}
		do {
			// Sent twice on purpose. begin_edit_settings is idempotent (the handler only sets
			// hasOpenEditTransaction = true, AdminModule.cpp:468-471) and the firmware never acks it, so a
			// dropped begin is undetectable from here and silently downgrades the whole run to untransacted:
			// every write then saves to flash, tears down Bluetooth, and schedules its own reboot. That was
			// observed on hardware. A second copy costs one packet and removes a single point of failure.
			try await gateway.beginEditSettings()
			try? await sleep(sendInterval)
			try await gateway.beginEditSettings()
			result.usedTransaction = true
		} catch is CancellationError {
			result.wasCancelled = true
			result.skipped = all.map(\.kind)
			return result
		} catch {
			result.failed = (all[0].kind,
							 "Could not open a settings transaction on the radio: \(error.localizedDescription)")
			result.skipped = all.dropFirst().map(\.kind)
			return result
		}

		// 2. Everything except MQTT/Serial, inside the transaction.
		let context = RunContext(gateway: gateway, sendInterval: sendInterval, sleep: sleep,
								 progress: progress, total: total)
		_ = await run(transactional, progressOffset: 0,
					  pendingAfter: deferredItems.map(\.kind),
					  context: context, into: &result)

		// 3. Commit unconditionally, even when step 2 stopped early. The firmware exposes no abort or
		//    rollback message, so an uncommitted transaction strands the radio in deferred-save mode where
		//    nothing any client writes afterwards is persisted. Committing a partial profile matches the
		//    pre-transaction behaviour of aborting on the first failure.
		// Whether the link was alive going in decides how to read a throw below.
		let connectedBeforeCommit = gateway.isConnected
		do {
			// Let the radio drain the last write before the commit lands on top of it.
			try? await sleep(sendInterval)
			try await gateway.commitEditSettings()
			result.transactionCommitted = true
		} catch {
			if connectedBeforeCommit && !gateway.isConnected {
				// The link dropped as the commit was processed. That is the normal path: the commit disables
				// Bluetooth and reboots (AdminModule.cpp:473-478, :2324), so the trailing ack is routinely
				// lost. The radio did receive the commit.
				result.transactionCommitted = true
				Logger.services.warning("Settings transaction commit did not ack; radio is rebooting: \(error.localizedDescription, privacy: .public)")
			} else {
				// Either the link was already down (the commit never reached the radio, which is still
				// holding an open transaction and deferring every later write) or we are still connected and
				// the send genuinely failed. Neither can be reported as a successful commit.
				result.commitUnconfirmed = true
				Logger.services.error("Settings transaction commit unconfirmed (connected before: \(connectedBeforeCommit, privacy: .public), connected now: \(gateway.isConnected, privacy: .public)): \(error.localizedDescription, privacy: .public)")
			}
		}
		// The commit itself saves every segment and reboots, so any run that got that far reboots.
		if !result.applied.isEmpty { result.rebooting = true }

		// 4. MQTT/Serial, now outside the transaction.
		//
		// On BLE this phase normally cannot run at all: the commit calls disableBluetooth(), which is a
		// hard synchronous teardown (nimbleBluetooth->deinit() / nrf52Bluetooth->shutdown(),
		// AdminModule.cpp:2324), so the transport is gone before we get here. Over TCP or serial the link
		// survives and these apply normally. Either way a miss here is NOT a failure: everything else is
		// already committed, so the items are reported as needing a reconnect and a second pass.
		guard result.failed == nil, !result.wasCancelled, !deferredItems.isEmpty else { return result }
		var deferredOutcome = DeviceProfileImportResult()
		let allDeferredApplied = await run(deferredItems, progressOffset: transactional.count,
										   pendingAfter: [], context: context, into: &deferredOutcome)
		result.applied.append(contentsOf: deferredOutcome.applied)
		if !allDeferredApplied {
			result.requiresReconnect = deferredItems.map(\.kind)
				.filter { !deferredOutcome.applied.contains($0) }
		}

		return result
	}

	/// Everything a phase needs beyond its own item list. Exists to keep `run` within the project's
	/// parameter-count limit rather than to model anything.
	@MainActor
	private struct RunContext {
		let gateway: ProfileApplyGateway
		let sendInterval: Duration
		let sleep: (Duration) async throws -> Void
		let progress: ((ImportItem, Int, Int) -> Void)?
		let total: Int
	}

	/// Applies one ordered run of items, mutating `result`. Returns true when every item was applied.
	/// On an early stop the current item is recorded as failed (or the run as cancelled) and everything
	/// after it, including `pendingAfter`, is recorded as skipped.
	@MainActor
	private static func run(
		_ items: [ImportItem],
		progressOffset: Int,
		pendingAfter: [ImportItemKind],
		context: RunContext,
		into result: inout DeviceProfileImportResult
	) async -> Bool {
		let gateway = context.gateway
		let progress = context.progress
		let total = context.total
		for (index, item) in items.enumerated() {
			// Pace every send after the first. Not cosmetic: an unpaced burst outruns the radio, which drops
			// the overflow and still reports success, so config goes missing with no client-side signal.
			if index > 0 {
				try? await context.sleep(context.sendInterval)
			}
			// Cancellation (user tapped Cancel, or the surrounding task was cancelled): stop cleanly,
			// treating the current and remaining items as not-applied rather than failed.
			if Task.isCancelled {
				result.wasCancelled = true
				result.skipped = items[index...].map(\.kind) + pendingAfter
				return false
			}

			// A disconnect mid-run is a genuine partial failure: record it and mark the untried items
			// skipped rather than blindly sending into a dead link.
			guard gateway.isConnected else {
				result.failed = (item.kind, "The radio disconnected before this step could be applied.")
				// The current item is the failure, not a skip; only the items after it were never attempted.
				result.skipped = items[(index + 1)...].map(\.kind) + pendingAfter
				return false
			}

			progress?(item, progressOffset + index, total)

			do {
				try await gateway.apply(item)
				result.applied.append(item.kind)
				if item.mayReboot { result.rebooting = true }
			} catch is CancellationError {
				// A cancellation-aware send observed the cancel — same handling as the loop-top check.
				result.wasCancelled = true
				result.skipped = items[index...].map(\.kind) + pendingAfter
				return false
			} catch {
				result.failed = (item.kind, error.localizedDescription)
				// Everything after the failed item never ran.
				result.skipped = items[(index + 1)...].map(\.kind) + pendingAfter
				return false
			}
		}
		return true
	}
}

// MARK: - Production gateway

/// Forwards each import item to the connected node via AccessoryManager. `fromUser == toUser == node`
/// for every send (self-admin), so no session passkey is ever involved.
@MainActor
struct AccessoryProfileApplyGateway: ProfileApplyGateway {
	let accessoryManager: AccessoryManager
	/// The connected node's user; both the source and destination of every admin message.
	let node: UserEntity

	var isConnected: Bool { accessoryManager.isConnected }

	func beginEditSettings() async throws {
		try await accessoryManager.beginEditSettings(fromUser: node, toUser: node)
	}

	func commitEditSettings() async throws {
		try await accessoryManager.commitEditSettings(fromUser: node, toUser: node)
	}

	func apply(_ item: ImportItem) async throws {
		switch item.payload {
		case .owner(let user):
			_ = try await accessoryManager.saveUser(config: user, fromUser: node, toUser: node)
		case .deviceConfig(let config):
			_ = try await accessoryManager.saveDeviceConfig(config: config, fromUser: node, toUser: node)
		case .displayConfig(let config):
			_ = try await accessoryManager.saveDisplayConfig(config: config, fromUser: node, toUser: node)
		case .positionConfig(let config):
			_ = try await accessoryManager.savePositionConfig(config: config, fromUser: node, toUser: node)
		case .powerConfig(let config):
			_ = try await accessoryManager.savePowerConfig(config: config, fromUser: node, toUser: node)
		case .networkConfig(let config):
			_ = try await accessoryManager.saveNetworkConfig(config: config, fromUser: node, toUser: node)
		case .bluetoothConfig(let config):
			_ = try await accessoryManager.saveBluetoothConfig(config: config, fromUser: node, toUser: node)
		case .securityConfig(let config):
			_ = try await accessoryManager.saveSecurityConfig(config: config, fromUser: node, toUser: node)
		case .mqtt(let config):
			_ = try await accessoryManager.saveMQTTConfig(config: config, fromUser: node, toUser: node)
		case .serial(let config):
			_ = try await accessoryManager.saveSerialModuleConfig(config: config, fromUser: node, toUser: node)
		case .externalNotification(let config):
			_ = try await accessoryManager.saveExternalNotificationModuleConfig(config: config, fromUser: node, toUser: node)
		case .storeForward(let config):
			_ = try await accessoryManager.saveStoreForwardModuleConfig(config: config, fromUser: node, toUser: node)
		case .rangeTest(let config):
			_ = try await accessoryManager.saveRangeTestModuleConfig(config: config, fromUser: node, toUser: node)
		case .telemetry(let config):
			_ = try await accessoryManager.saveTelemetryModuleConfig(config: config, fromUser: node, toUser: node)
		case .cannedMessage(let config):
			_ = try await accessoryManager.saveCannedMessageModuleConfig(config: config, fromUser: node, toUser: node)
		case .audio(let config):
			_ = try await accessoryManager.saveAudioModuleConfig(config: config, fromUser: node, toUser: node)
		case .neighborInfo(let config):
			_ = try await accessoryManager.saveNeighborInfoModuleConfig(config: config, fromUser: node, toUser: node)
		case .ambientLighting(let config):
			_ = try await accessoryManager.saveAmbientLightingModuleConfig(config: config, fromUser: node, toUser: node)
		case .detectionSensor(let config):
			_ = try await accessoryManager.saveDetectionSensorModuleConfig(config: config, fromUser: node, toUser: node)
		case .paxcounter(let config):
			_ = try await accessoryManager.savePaxcounterModuleConfig(config: config, fromUser: node, toUser: node)
		case .tak(let config):
			_ = try await accessoryManager.saveTAKModuleConfig(config: config, fromUser: node, toUser: node)
		case .trafficManagement(let config):
			_ = try await accessoryManager.saveTrafficManagementModuleConfig(config: config, fromUser: node, toUser: node)
		case .statusMessage(let config):
			_ = try await accessoryManager.saveStatusMessageModuleConfig(config: config, fromUser: node, toUser: node)
		case .ringtone(let ringtone):
			_ = try await accessoryManager.saveRtttlConfig(ringtone: ringtone, fromUser: node, toUser: node)
		case .cannedMessagesText(let messages):
			_ = try await accessoryManager.saveCannedMessageModuleMessages(messages: messages, fromUser: node, toUser: node)
		case .fixedPosition(let position):
			_ = try await accessoryManager.setFixedPosition(position, fromUser: node, toUser: node)
		case .channelURL(let url):
			// saveChannelSet sends the channels + LoRa config and already tolerates the resulting reboot
			// (it swallows the post-reboot wantConfig internally), so a throw here is a real validation error.
			try await accessoryManager.saveChannelSet(base64UrlString: url, addChannels: false)
		case .loraConfig(let config):
			// saveLoRaConfig has no built-in reboot tolerance: sending it reboots the radio and the trailing
			// wantConfig/ack fails as the link drops. Only that reboot disconnect is expected success — so
			// swallow the error only when the link has actually dropped; if we're still connected the send
			// genuinely failed (e.g. serialization or a transport write error) and must surface as a failure.
			do {
				_ = try await accessoryManager.saveLoRaConfig(config: config, fromUser: node, toUser: node)
			} catch {
				if accessoryManager.isConnected { throw error }
				Logger.services.warning("LoRa config send did not complete; radio is likely rebooting: \(error.localizedDescription, privacy: .public)")
			}
		}
	}
}
