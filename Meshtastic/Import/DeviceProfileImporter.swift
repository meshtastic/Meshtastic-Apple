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
}

// MARK: - Result

/// The outcome of an import run. `failed` is set for the first item that failed (the run stops there);
/// `skipped` lists items that were never attempted as a result.
struct DeviceProfileImportResult {
	var applied: [ImportItemKind] = []
	var skipped: [ImportItemKind] = []
	var failed: (kind: ImportItemKind, message: String)? = nil
	/// True when a reboot-causing item (Channels & LoRa) was applied — the radio will disconnect briefly.
	var rebooting: Bool = false
	/// True when the run stopped because it was cancelled (user tapped Cancel or the task was cancelled)
	/// rather than failing. The current and remaining items are recorded as `skipped`, not `failed`.
	var wasCancelled: Bool = false

	var isCompleteSuccess: Bool { failed == nil && !wasCancelled }
}

// MARK: - Engine

enum DeviceProfileImporter {

	/// Applies the selected sections of a plan, in order, aborting on the first failure.
	/// - Parameters:
	///   - plan: the parsed import plan.
	///   - selection: the sections the user chose to import.
	///   - gateway: the send seam (production or mock).
	///   - progress: called just before each item is sent, with (item, zero-based index, total count).
	/// - Returns: what was applied, skipped, or failed, and whether the radio is rebooting.
	@MainActor
	static func apply(
		plan: DeviceProfileImportPlan,
		selection: Set<ImportSection>,
		gateway: ProfileApplyGateway,
		progress: ((ImportItem, Int, Int) -> Void)? = nil
	) async -> DeviceProfileImportResult {
		var result = DeviceProfileImportResult()
		let items = plan.items(for: selection)

		for (index, item) in items.enumerated() {
			// Cancellation (user tapped Cancel, or the surrounding task was cancelled): stop cleanly,
			// treating the current and remaining items as not-applied rather than failed.
			if Task.isCancelled {
				result.wasCancelled = true
				result.skipped = items[index...].map(\.kind)
				return result
			}

			// A disconnect before the terminal reboot step is a genuine partial failure — record it and
			// mark the untried items skipped rather than blindly sending into a dead link.
			guard gateway.isConnected else {
				result.failed = (item.kind, "The radio disconnected before this step could be applied.")
				// The current item is the failure, not a skip; only the items after it were never attempted.
				if index + 1 < items.count {
					result.skipped = items[(index + 1)...].map(\.kind)
				}
				return result
			}

			progress?(item, index, items.count)

			do {
				try await gateway.apply(item)
				result.applied.append(item.kind)
				if item.causesReboot { result.rebooting = true }
			} catch is CancellationError {
				// A cancellation-aware send observed the cancel — same handling as the loop-top check.
				result.wasCancelled = true
				result.skipped = items[index...].map(\.kind)
				return result
			} catch {
				result.failed = (item.kind, error.localizedDescription)
				// Everything after the failed item never ran.
				if index + 1 < items.count {
					result.skipped = items[(index + 1)...].map(\.kind)
				}
				return result
			}
		}

		return result
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
