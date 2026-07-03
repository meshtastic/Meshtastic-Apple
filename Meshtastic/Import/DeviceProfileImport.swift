//
//  DeviceProfileImport.swift
//  Meshtastic
//
//  Pure, device-free core of the "Import Device Configuration" feature: parses an untrusted
//  `DeviceProfile` (`.cfg`) file and turns it into an ordered, selectable plan of admin sends. This is
//  the has*-gated inverse of `NodeInfoEntity.exportDeviceProfile()` — keep the two in sync when config
//  fields are added so export and import can't silently drift. Nothing here touches AccessoryManager or
//  SwiftData, so the whole plan is unit-testable without a radio.
//

import Foundation
import MeshtasticProtobufs

// MARK: - Errors

enum DeviceProfileImportError: Error, Equatable {
	/// The picked file was empty.
	case emptyFile
	/// The file was larger than a device profile could plausibly be (guards against decoding a huge blob).
	case tooLarge
	/// The bytes were not a valid `DeviceProfile` protobuf.
	case malformed
	/// The profile parsed but contained nothing this app can apply.
	case nothingToImport
}

// MARK: - Sections

/// Coarse groupings the user can toggle in the import review sheet. Each present section maps to one or
/// more admin sends. Toggling filters the plan's items; it never reorders them.
enum ImportSection: String, CaseIterable, Identifiable {
	case owner
	case radioAndDevice   // device / display / position / power / bluetooth
	case network
	case modules
	case personalization  // ringtone + canned-message text
	case fixedPosition
	case security
	case channelsAndLoRa

	var id: String { rawValue }

	var title: String {
		switch self {
		case .owner: return "Owner Name".localized
		case .radioAndDevice: return "Radio & Device".localized
		case .network: return "Network".localized
		case .modules: return "Modules".localized
		case .personalization: return "Ringtone & Canned Messages".localized
		case .fixedPosition: return "Fixed Position".localized
		case .security: return "Security & Identity".localized
		case .channelsAndLoRa: return "Channels & LoRa".localized
		}
	}

	/// Whether this section starts toggled ON in the review sheet. Everything defaults ON except
	/// Security & Identity — importing a foreign private key rewrites this node's cryptographic
	/// identity and admin-key trust, so it's a deliberate opt-in rather than part of a one-tap restore.
	var defaultsOn: Bool { self != .security }
}

// MARK: - Items

/// The kind of a single applyable unit. Stable identifier used for progress/result reporting and tests.
enum ImportItemKind: String, Equatable {
	case owner
	case deviceConfig, displayConfig, positionConfig, powerConfig, networkConfig, bluetoothConfig, securityConfig
	case mqtt, serial, externalNotification, storeForward, rangeTest, telemetry, cannedMessage, audio
	case neighborInfo, ambientLighting, detectionSensor, paxcounter, tak, trafficManagement, statusMessage
	case ringtone, cannedMessagesText, fixedPosition
	case channelURL, loraConfig

	/// Human-readable, localized label for progress and result screens (the raw case name is not
	/// user-facing). Casing matches the existing config-screen strings so translations are reused.
	var displayName: String {
		switch self {
		case .owner: return "Owner Name".localized
		case .deviceConfig: return "Device".localized
		case .displayConfig: return "Display".localized
		case .positionConfig: return "Position".localized
		case .powerConfig: return "Power".localized
		case .networkConfig: return "Network".localized
		case .bluetoothConfig: return "Bluetooth".localized
		case .securityConfig: return "Security & Identity".localized
		case .mqtt: return "MQTT".localized
		case .serial: return "Serial".localized
		case .externalNotification: return "External Notification".localized
		case .storeForward: return "Store & Forward".localized
		case .rangeTest: return "Range Test".localized
		case .telemetry: return "Telemetry".localized
		case .cannedMessage: return "Canned Message".localized
		case .audio: return "Audio".localized
		case .neighborInfo: return "Neighbor Info".localized
		case .ambientLighting: return "Ambient Lighting".localized
		case .detectionSensor: return "Detection Sensor".localized
		case .paxcounter: return "PAX Counter".localized
		case .tak: return "TAK".localized
		case .trafficManagement: return "Traffic Management".localized
		case .statusMessage: return "Status Message".localized
		case .ringtone: return "Ringtone".localized
		case .cannedMessagesText: return "Canned Messages".localized
		case .fixedPosition: return "Fixed Position".localized
		case .channelURL: return "Channels & LoRa".localized
		case .loraConfig: return "LoRa Region".localized
		}
	}
}

/// The already-built protobuf value for a single send. Holding concrete protos (not closures) keeps the
/// plan pure and lets the apply gateway stay a thin dispatcher.
enum ImportPayload {
	case owner(User)
	case deviceConfig(Config.DeviceConfig)
	case displayConfig(Config.DisplayConfig)
	case positionConfig(Config.PositionConfig)
	case powerConfig(Config.PowerConfig)
	case networkConfig(Config.NetworkConfig)
	case bluetoothConfig(Config.BluetoothConfig)
	case securityConfig(Config.SecurityConfig)
	case mqtt(ModuleConfig.MQTTConfig)
	case serial(ModuleConfig.SerialConfig)
	case externalNotification(ModuleConfig.ExternalNotificationConfig)
	case storeForward(ModuleConfig.StoreForwardConfig)
	case rangeTest(ModuleConfig.RangeTestConfig)
	case telemetry(ModuleConfig.TelemetryConfig)
	case cannedMessage(ModuleConfig.CannedMessageConfig)
	case audio(ModuleConfig.AudioConfig)
	case neighborInfo(ModuleConfig.NeighborInfoConfig)
	case ambientLighting(ModuleConfig.AmbientLightingConfig)
	case detectionSensor(ModuleConfig.DetectionSensorConfig)
	case paxcounter(ModuleConfig.PaxcounterConfig)
	case tak(ModuleConfig.TAKConfig)
	case trafficManagement(ModuleConfig.TrafficManagementConfig)
	case statusMessage(ModuleConfig.StatusMessageConfig)
	case ringtone(String)
	case cannedMessagesText(String)
	case fixedPosition(Position)
	case channelURL(String)
	case loraConfig(Config.LoRaConfig)
}

/// One applyable unit of the import: what to send, which section owns it (for toggling), a human summary,
/// and whether it carries sensitive material or reboots the radio.
struct ImportItem: Identifiable {
	let kind: ImportItemKind
	let section: ImportSection
	let summary: String
	let isSensitive: Bool
	let causesReboot: Bool
	let payload: ImportPayload

	var id: String { kind.rawValue }
}

// MARK: - Plan

/// The ordered set of admin sends that will restore a device from a `DeviceProfile`. Items are emitted in
/// a fixed apply order (see `init`); the UI filters by selected sections but must never re-sort, so the
/// reboot-prone Channels & LoRa step always stays last.
struct DeviceProfileImportPlan {

	/// Largest `.cfg` we'll attempt to decode. A real device profile is a few KB; anything past this is
	/// almost certainly not a profile and shouldn't be handed to the protobuf decoder.
	static let maxProfileBytes = 512 * 1024

	let items: [ImportItem]

	/// Parses untrusted file bytes into a `DeviceProfile`, guarding size before decode. This is the
	/// trust boundary for imported files.
	static func parseDeviceProfile(_ data: Data) throws -> DeviceProfile {
		guard !data.isEmpty else { throw DeviceProfileImportError.emptyFile }
		guard data.count <= maxProfileBytes else { throw DeviceProfileImportError.tooLarge }
		do {
			return try DeviceProfile(serializedBytes: data)
		} catch {
			throw DeviceProfileImportError.malformed
		}
	}

	/// Merges a profile's optional owner name onto the connected node's existing `User`, overriding only
	/// the long/short name and preserving id, hardware model, keys, role, and licensed/unmessagable flags.
	/// Sending a bare name-only `User` to `setOwner` would wipe those, so the base must be the live user.
	static func ownerUser(from profile: DeviceProfile, base: User) -> User {
		var user = base
		if profile.hasLongName { user.longName = profile.longName }
		if profile.hasShortName { user.shortName = profile.shortName }
		return user
	}

	/// Builds the plan as the has*-gated inverse of `exportDeviceProfile()`, emitting items in apply order.
	/// - Parameters:
	///   - profile: the parsed device profile.
	///   - currentUser: the connected node's current `User` (the merge base for the owner step); when nil,
	///     the owner step is omitted entirely.
	/// - Throws: `.nothingToImport` when the profile yields no applyable items.
	init(profile: DeviceProfile, currentUser: User?) throws {
		var items: [ImportItem] = []
		let config = profile.config
		let module = profile.moduleConfig

		// 1. Owner name (non-sensitive, no reboot). Only when the profile carries a name and we have a
		//    base user to merge onto.
		if profile.hasLongName || profile.hasShortName, let base = currentUser {
			let merged = DeviceProfileImportPlan.ownerUser(from: profile, base: base)
			let name = [profile.hasLongName ? profile.longName : merged.longName,
						profile.hasShortName ? "(\(profile.shortName))" : nil]
				.compactMap { $0 }.joined(separator: " ")
			items.append(ImportItem(kind: .owner, section: .owner, summary: name.isEmpty ? "Owner name" : name,
									isSensitive: false, causesReboot: false, payload: .owner(merged)))
		}

		// 2-5. Cheap radio/device configs (Radio & Device section). LoRa is deliberately excluded here — it
		//      belongs to the terminal Channels & LoRa step because it reboots.
		if profile.hasConfig {
			if config.hasDevice {
				items.append(ImportItem(kind: .deviceConfig, section: .radioAndDevice, summary: "Device role & behavior",
										isSensitive: false, causesReboot: false, payload: .deviceConfig(config.device)))
			}
			if config.hasDisplay {
				items.append(ImportItem(kind: .displayConfig, section: .radioAndDevice, summary: "Display settings",
										isSensitive: false, causesReboot: false, payload: .displayConfig(config.display)))
			}
			if config.hasPosition {
				items.append(ImportItem(kind: .positionConfig, section: .radioAndDevice, summary: "Position settings",
										isSensitive: false, causesReboot: false, payload: .positionConfig(config.position)))
			}
			if config.hasPower {
				items.append(ImportItem(kind: .powerConfig, section: .radioAndDevice, summary: "Power settings",
										isSensitive: false, causesReboot: false, payload: .powerConfig(config.power)))
			}
		}

		// 6. Module configs, in the same order export writes them. meshBeacon/remoteHardware are absent by
		//    design (no save function — mirrors export coverage). MQTT is flagged sensitive (password).
		if profile.hasModuleConfig {
			if module.hasMqtt {
				items.append(ImportItem(kind: .mqtt, section: .modules, summary: "MQTT",
										isSensitive: true, causesReboot: false, payload: .mqtt(module.mqtt)))
			}
			if module.hasSerial {
				items.append(ImportItem(kind: .serial, section: .modules, summary: "Serial",
										isSensitive: false, causesReboot: false, payload: .serial(module.serial)))
			}
			if module.hasExternalNotification {
				items.append(ImportItem(kind: .externalNotification, section: .modules, summary: "External Notification",
										isSensitive: false, causesReboot: false, payload: .externalNotification(module.externalNotification)))
			}
			if module.hasStoreForward {
				items.append(ImportItem(kind: .storeForward, section: .modules, summary: "Store & Forward",
										isSensitive: false, causesReboot: false, payload: .storeForward(module.storeForward)))
			}
			if module.hasRangeTest {
				items.append(ImportItem(kind: .rangeTest, section: .modules, summary: "Range Test",
										isSensitive: false, causesReboot: false, payload: .rangeTest(module.rangeTest)))
			}
			if module.hasTelemetry {
				items.append(ImportItem(kind: .telemetry, section: .modules, summary: "Telemetry",
										isSensitive: false, causesReboot: false, payload: .telemetry(module.telemetry)))
			}
			if module.hasCannedMessage {
				items.append(ImportItem(kind: .cannedMessage, section: .modules, summary: "Canned Message",
										isSensitive: false, causesReboot: false, payload: .cannedMessage(module.cannedMessage)))
			}
			if module.hasAudio {
				items.append(ImportItem(kind: .audio, section: .modules, summary: "Audio",
										isSensitive: false, causesReboot: false, payload: .audio(module.audio)))
			}
			if module.hasNeighborInfo {
				items.append(ImportItem(kind: .neighborInfo, section: .modules, summary: "Neighbor Info",
										isSensitive: false, causesReboot: false, payload: .neighborInfo(module.neighborInfo)))
			}
			if module.hasAmbientLighting {
				items.append(ImportItem(kind: .ambientLighting, section: .modules, summary: "Ambient Lighting",
										isSensitive: false, causesReboot: false, payload: .ambientLighting(module.ambientLighting)))
			}
			if module.hasDetectionSensor {
				items.append(ImportItem(kind: .detectionSensor, section: .modules, summary: "Detection Sensor",
										isSensitive: false, causesReboot: false, payload: .detectionSensor(module.detectionSensor)))
			}
			if module.hasPaxcounter {
				items.append(ImportItem(kind: .paxcounter, section: .modules, summary: "PAX Counter",
										isSensitive: false, causesReboot: false, payload: .paxcounter(module.paxcounter)))
			}
			if module.hasTak {
				items.append(ImportItem(kind: .tak, section: .modules, summary: "TAK",
										isSensitive: false, causesReboot: false, payload: .tak(module.tak)))
			}
			if module.hasTrafficManagement {
				items.append(ImportItem(kind: .trafficManagement, section: .modules, summary: "Traffic Management",
										isSensitive: false, causesReboot: false, payload: .trafficManagement(module.trafficManagement)))
			}
			if module.hasStatusmessage {
				items.append(ImportItem(kind: .statusMessage, section: .modules, summary: "Status Message",
										isSensitive: false, causesReboot: false, payload: .statusMessage(module.statusmessage)))
			}
		}

		// 7. Personalization: ringtone + canned-message text. Emitted after the Canned Message module
		//    config (step 6) so the text isn't clobbered by the module config that follows it.
		if profile.hasRingtone, !profile.ringtone.isEmpty {
			items.append(ImportItem(kind: .ringtone, section: .personalization, summary: "Ringtone",
									isSensitive: false, causesReboot: false, payload: .ringtone(profile.ringtone)))
		}
		if profile.hasCannedMessages, !profile.cannedMessages.isEmpty {
			items.append(ImportItem(kind: .cannedMessagesText, section: .personalization, summary: "Canned messages",
									isSensitive: false, causesReboot: false, payload: .cannedMessagesText(profile.cannedMessages)))
		}

		// 8. Fixed position — only when set to real coordinates (inverse of export's guard). Ordered after
		//    the position config so the fixed-position flag it carries isn't overwritten.
		if profile.hasFixedPosition,
		   profile.fixedPosition.latitudeI != 0 || profile.fixedPosition.longitudeI != 0 {
			items.append(ImportItem(kind: .fixedPosition, section: .fixedPosition, summary: "Fixed position",
									isSensitive: false, causesReboot: false, payload: .fixedPosition(profile.fixedPosition)))
		}

		// 9. Network — placed late because enabling Wi-Fi/Ethernet can drop a TCP transport mid-import.
		//    Sensitive (Wi-Fi PSK).
		if profile.hasConfig, config.hasNetwork {
			let ssid = config.network.wifiSsid
			items.append(ImportItem(kind: .networkConfig, section: .network,
									summary: ssid.isEmpty ? "Wi-Fi / Ethernet" : "Wi-Fi SSID: \(ssid)",
									isSensitive: true, causesReboot: false, payload: .networkConfig(config.network)))
		}

		// 10. Bluetooth — just before the terminal step because changing BLE mode/pin can drop the BLE
		//     transport the import runs over.
		if profile.hasConfig, config.hasBluetooth {
			items.append(ImportItem(kind: .bluetoothConfig, section: .radioAndDevice, summary: "Bluetooth settings",
									isSensitive: false, causesReboot: false, payload: .bluetoothConfig(config.bluetooth)))
		}

		// 11. Security — opt-in, sensitive. Late because admin-key/isManaged changes can restrict further
		//     local admin.
		if profile.hasConfig, config.hasSecurity {
			items.append(ImportItem(kind: .securityConfig, section: .security,
									summary: "Node identity, keys & admin access",
									isSensitive: true, causesReboot: false, payload: .securityConfig(config.security)))
		}

		// 12. TERMINAL: Channels & LoRa (reboots). Export puts the SAME LoRaConfig in both config.lora and
		//     the channel URL's ChannelSet, so exactly one owner is emitted: prefer the channel URL (it
		//     also restores channels), fall back to the standalone LoRa config. A channel URL that can't be
		//     parsed or lacks a LoRa config for replace-mode falls back to the standalone LoRa config so the
		//     region is still restored.
		var addedChannelOrLoRa = false
		if profile.hasChannelURL, !profile.channelURL.isEmpty,
		   let parsed = try? MeshtasticChannelURL.parse(profile.channelURL),
		   !parsed.addChannels, parsed.channelSet.hasLoraConfig {
			items.append(ImportItem(kind: .channelURL, section: .channelsAndLoRa,
									summary: "Channels & LoRa region (\(parsed.channelSet.settings.count) channel\(parsed.channelSet.settings.count == 1 ? "" : "s"))",
									isSensitive: true, causesReboot: true, payload: .channelURL(profile.channelURL)))
			addedChannelOrLoRa = true
		}
		if !addedChannelOrLoRa, profile.hasConfig, config.hasLora {
			items.append(ImportItem(kind: .loraConfig, section: .channelsAndLoRa,
									summary: "LoRa region: \(config.lora.region)",
									isSensitive: false, causesReboot: true, payload: .loraConfig(config.lora)))
		}

		guard !items.isEmpty else { throw DeviceProfileImportError.nothingToImport }
		self.items = items
	}

	// MARK: Selection helpers

	/// The sections actually present in this profile, in canonical order.
	var presentSections: [ImportSection] {
		ImportSection.allCases.filter { section in items.contains { $0.section == section } }
	}

	/// The items belonging to the selected sections, preserving apply order.
	func items(for selection: Set<ImportSection>) -> [ImportItem] {
		items.filter { selection.contains($0.section) }
	}

	/// Whether the selected sections include any item that overwrites sensitive material.
	func containsSensitive(in selection: Set<ImportSection>) -> Bool {
		items(for: selection).contains { $0.isSensitive }
	}

	/// Whether applying the selected sections will reboot the radio.
	func willReboot(in selection: Set<ImportSection>) -> Bool {
		items(for: selection).contains { $0.causesReboot }
	}
}
