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

// MARK: - Firmware support

/// Whether the connected firmware can actually apply a given import item.
///
/// `handleSetModuleConfig` has no `default:` case: an unrecognized module config falls through the
/// switch, the radio still returns success, and nothing is applied. There is no negative ack, so the
/// only way to tell the user is to check the firmware version up front.
enum FirmwareSupport: Equatable {
	/// Applies on every firmware version the app supports (the app floor is 2.5.18).
	case always
	/// Needs at least this firmware version.
	case fromVersion(String)
	/// No firmware version implements this, including develop. The radio accepts the message, reports
	/// success, and silently discards it.
	case unimplemented
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

	/// The firmware needed to apply this item, verified against meshtastic/firmware
	/// `src/modules/AdminModule.cpp` across released tags.
	var firmwareSupport: FirmwareSupport {
		switch self {
		// First released in v2.7.20.6658ec2; absent from v2.7.19 and earlier.
		case .statusMessage: return .fromVersion("2.7.20")
		// Present only on develop; no released tag has a traffic_management case.
		case .trafficManagement: return .fromVersion("2.8.0")
		// No `case meshtastic_ModuleConfig_tak_tag` has ever existed in handleSetModuleConfig, on any tag
		// or on develop. Meshtastic-Android sends it too (InstallProfileUseCase.kt:110) and hits the same
		// silent no-op, so this is an ecosystem-wide dead path rather than an Apple gap.
		case .tak: return .unimplemented
		default: return .always
		}
	}

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
	/// Whether applying this item may reboot the radio
	/// (firmware/src/modules/AdminModule.cpp). Conservative by design: `true` means "may reboot", not
	/// "will reboot". Outside an open edit transaction the firmware reboots on nearly every write, and
	/// for device/display/power it decides via a field-by-field diff against current device state that
	/// this app cannot evaluate at plan-build time, so those are flagged `true`.
	///
	/// Only these do NOT reboot, on both firmware 2.8 (develop) and the shipped 2.7.x line:
	/// statusMessage (:1275), ringtone and cannedMessagesText (both bypass AdminModule and write their
	/// proto directly), fixedPosition (:585), and channelURL (:1398).
	///
	/// loraConfig is deliberately `true` even though firmware 2.8 never reboots for it (:1060, added by
	/// firmware #9962 "apply all LoRa config changes live without rebooting"). That change is develop-only
	/// and ships in no released tag yet: on 2.7.x, set_config(lora) skips the reboot ONLY when every radio
	/// field is unchanged, which restoring a profile does not satisfy. Being non-conservative here is the
	/// asymmetric failure (an unwarned mid-import reboot), so the flag stays `true` until the app
	/// version-gates it.
	///
	/// Note this describes the ITEM, not the run. Since the import now commits inside a firmware edit
	/// transaction, and `commit_edit_settings` always saves and reboots, every successful run reboots
	/// regardless of these flags. See DeviceProfileImportTests.flags for the full derivation.
	let mayReboot: Bool
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

	/// The items that will actually be sent. Excludes anything the connected firmware cannot apply.
	let items: [ImportItem]
	/// Items present in the profile that this firmware cannot apply, with the reason. These are never
	/// sent: the radio would accept them, report success, and silently discard them.
	let unsupported: [(item: ImportItem, support: FirmwareSupport)]

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
		// Take the profile's value when it carries one, otherwise keep the node's. Matches
		// Meshtastic-Android (InstallProfileUseCase.kt:59).
		if profile.hasIsUnmessagable { user.isUnmessagable = profile.isUnmessagable }
		// is_licensed is deliberately NOT copied. Enabling ham mode is a dedicated onboarding flow
		// (set_ham_mode rewrites the owner, disables encryption, applies tx power/frequency); a plain
		// set_owner would bypass all of it and leave the node flagged licensed without those side
		// effects. Android omits it for the same reason.
		return user
	}

	/// Merges a profile's `SecurityConfig` onto the node's current one, PRESERVING the node's existing
	/// keys whenever the profile doesn't carry them. This is the "keys" half of a partial import (the
	/// "names" half is `ownerUser`): a Meshtastic security block has no per-field presence, so an
	/// "official"/event `.cfg` that only sets flags or admin keys but leaves the identity keypair empty
	/// would otherwise WIPE this node's public/private key on import. An empty key is never a valid
	/// identity, so treating empty-as-absent is safe: a full backup (keys present) still restores the
	/// keypair, while a partial config keeps the node's own identity.
	static func securityConfig(from profile: Config.SecurityConfig, base: Config.SecurityConfig?) -> Config.SecurityConfig {
		guard let base else { return profile }
		var merged = profile
		if merged.privateKey.isEmpty { merged.privateKey = base.privateKey }
		if merged.publicKey.isEmpty { merged.publicKey = base.publicKey }
		// Admin keys are a positional repeated field. "Profile carries no admin keys" (empty, or only
		// empty placeholder slots) is treated as absent so an event config that just flips isManaged /
		// adminChannelEnabled doesn't drop the node's existing admin keys. A profile that DOES carry admin
		// keys replaces them (explicit intent).
		if merged.adminKey.allSatisfy(\.isEmpty) { merged.adminKey = base.adminKey }
		return merged
	}

	/// Builds the plan as the has*-gated inverse of `exportDeviceProfile()`, emitting items in apply order.
	/// - Parameters:
	///   - profile: the parsed device profile.
	///   - currentUser: the connected node's current `User` (the merge base for the owner step); when nil,
	///     the owner step is omitted entirely.
	///   - currentSecurity: the connected node's current `SecurityConfig`, used as the merge base so a
	///     partial profile that omits the identity keypair keeps the node's own keys (see
	///     `securityConfig(from:base:)`). When nil, the profile's security block is applied as-is.
	/// - Parameter firmwareVersion: the connected radio's firmware version, used to drop items this
	///     firmware cannot apply. Pass nil when unknown, which is permissive and assumes support,
	///     matching `AccessoryManager.checkIsVersionSupported`.
	/// - Throws: `.nothingToImport` when the profile yields no applyable items.
	init(profile: DeviceProfile, currentUser: User?, currentSecurity: Config.SecurityConfig? = nil,
		 firmwareVersion: String? = nil) throws {
		var items: [ImportItem] = []
		let config = profile.config
		let module = profile.moduleConfig

		// 1. Owner name (non-sensitive, but DOES reboot: set_owner saves with the default shouldReboot
		//    = true, AdminModule.cpp:793). Only when the profile carries a name and we have a base user
		//    to merge onto.
		if profile.hasLongName || profile.hasShortName || profile.hasIsUnmessagable, let base = currentUser {
			let merged = DeviceProfileImportPlan.ownerUser(from: profile, base: base)
			let name = [profile.hasLongName ? profile.longName : merged.longName,
						profile.hasShortName ? "(\(profile.shortName))" : nil]
				.compactMap { $0 }.joined(separator: " ")
			items.append(ImportItem(kind: .owner, section: .owner, summary: name.isEmpty ? "Owner name" : name,
									isSensitive: false, mayReboot: true, payload: .owner(merged)))
		}

		// 2-5. Radio/device configs (Radio & Device section). All of these reboot on firmware 2.8:
		//      handleSetConfig defaults requiresReboot = true (AdminModule.cpp:840); position never
		//      overrides it, and device/display/power clear it only when every relevant field is
		//      unchanged (:857/:943/:922), which restoring a different profile does not satisfy.
		//      LoRa is still excluded here and kept in the terminal step so it stays paired with the
		//      channel URL that carries the same LoRaConfig, NOT because it reboots (it does not: :1060).
		if profile.hasConfig {
			if config.hasDevice {
				items.append(ImportItem(kind: .deviceConfig, section: .radioAndDevice, summary: "Device role & behavior",
										isSensitive: false, mayReboot: true, payload: .deviceConfig(config.device)))
			}
			if config.hasDisplay {
				items.append(ImportItem(kind: .displayConfig, section: .radioAndDevice, summary: "Display settings",
										isSensitive: false, mayReboot: true, payload: .displayConfig(config.display)))
			}
			if config.hasPosition {
				items.append(ImportItem(kind: .positionConfig, section: .radioAndDevice, summary: "Position settings",
										isSensitive: false, mayReboot: true, payload: .positionConfig(config.position)))
			}
			if config.hasPower {
				items.append(ImportItem(kind: .powerConfig, section: .radioAndDevice, summary: "Power settings",
										isSensitive: false, mayReboot: true, payload: .powerConfig(config.power)))
			}
		}

		// 6. Module configs, in the same order export writes them. meshBeacon/remoteHardware are absent by
		//    design (no save function — mirrors export coverage). MQTT is flagged sensitive (password).
		if profile.hasModuleConfig {
			if module.hasMqtt {
				items.append(ImportItem(kind: .mqtt, section: .modules, summary: "MQTT",
										isSensitive: true, mayReboot: true, payload: .mqtt(module.mqtt)))
			}
			if module.hasSerial {
				items.append(ImportItem(kind: .serial, section: .modules, summary: "Serial",
										isSensitive: false, mayReboot: true, payload: .serial(module.serial)))
			}
			if module.hasExternalNotification {
				items.append(ImportItem(kind: .externalNotification, section: .modules, summary: "External Notification",
										isSensitive: false, mayReboot: true, payload: .externalNotification(module.externalNotification)))
			}
			if module.hasStoreForward {
				items.append(ImportItem(kind: .storeForward, section: .modules, summary: "Store & Forward",
										isSensitive: false, mayReboot: true, payload: .storeForward(module.storeForward)))
			}
			if module.hasRangeTest {
				items.append(ImportItem(kind: .rangeTest, section: .modules, summary: "Range Test",
										isSensitive: false, mayReboot: true, payload: .rangeTest(module.rangeTest)))
			}
			if module.hasTelemetry {
				items.append(ImportItem(kind: .telemetry, section: .modules, summary: "Telemetry",
										isSensitive: false, mayReboot: true, payload: .telemetry(module.telemetry)))
			}
			if module.hasCannedMessage {
				items.append(ImportItem(kind: .cannedMessage, section: .modules, summary: "Canned Message",
										isSensitive: false, mayReboot: true, payload: .cannedMessage(module.cannedMessage)))
			}
			if module.hasAudio {
				items.append(ImportItem(kind: .audio, section: .modules, summary: "Audio",
										isSensitive: false, mayReboot: true, payload: .audio(module.audio)))
			}
			if module.hasNeighborInfo {
				items.append(ImportItem(kind: .neighborInfo, section: .modules, summary: "Neighbor Info",
										isSensitive: false, mayReboot: true, payload: .neighborInfo(module.neighborInfo)))
			}
			if module.hasAmbientLighting {
				items.append(ImportItem(kind: .ambientLighting, section: .modules, summary: "Ambient Lighting",
										isSensitive: false, mayReboot: true, payload: .ambientLighting(module.ambientLighting)))
			}
			if module.hasDetectionSensor {
				items.append(ImportItem(kind: .detectionSensor, section: .modules, summary: "Detection Sensor",
										isSensitive: false, mayReboot: true, payload: .detectionSensor(module.detectionSensor)))
			}
			if module.hasPaxcounter {
				items.append(ImportItem(kind: .paxcounter, section: .modules, summary: "PAX Counter",
										isSensitive: false, mayReboot: true, payload: .paxcounter(module.paxcounter)))
			}
			if module.hasTak {
				// NOTE: firmware 2.8 has no `case meshtastic_ModuleConfig_tak_tag` in handleSetModuleConfig,
				// so this reboots the radio (default shouldReboot = true, AdminModule.cpp:1175) and then
				// applies nothing. Tracked as a firmware-side bug; flagged reboot-causing here regardless.
				items.append(ImportItem(kind: .tak, section: .modules, summary: "TAK",
										isSensitive: false, mayReboot: true, payload: .tak(module.tak)))
			}
			if module.hasTrafficManagement {
				items.append(ImportItem(kind: .trafficManagement, section: .modules, summary: "Traffic Management",
										isSensitive: false, mayReboot: true, payload: .trafficManagement(module.trafficManagement)))
			}
			if module.hasStatusmessage {
				// One of only two module configs the firmware does not reboot for (AdminModule.cpp:1275).
				items.append(ImportItem(kind: .statusMessage, section: .modules, summary: "Status Message",
										isSensitive: false, mayReboot: false, payload: .statusMessage(module.statusmessage)))
			}
		}

		// 7. Personalization: ringtone + canned-message text. Emitted after the Canned Message module
		//    config (step 6) so the text isn't clobbered by the module config that follows it.
		if profile.hasRingtone, !profile.ringtone.isEmpty {
			items.append(ImportItem(kind: .ringtone, section: .personalization, summary: "Ringtone",
									isSensitive: false, mayReboot: false, payload: .ringtone(profile.ringtone)))
		}
		if profile.hasCannedMessages, !profile.cannedMessages.isEmpty {
			items.append(ImportItem(kind: .cannedMessagesText, section: .personalization, summary: "Canned messages",
									isSensitive: false, mayReboot: false, payload: .cannedMessagesText(profile.cannedMessages)))
		}

		// 8. Fixed position — only when set to real coordinates (inverse of export's guard). Ordered after
		//    the position config so the fixed-position flag it carries isn't overwritten.
		if profile.hasFixedPosition,
		   profile.fixedPosition.latitudeI != 0 || profile.fixedPosition.longitudeI != 0 {
			items.append(ImportItem(kind: .fixedPosition, section: .fixedPosition, summary: "Fixed position",
									isSensitive: false, mayReboot: false, payload: .fixedPosition(profile.fixedPosition)))
		}

		// 9. Network — placed late because enabling Wi-Fi/Ethernet can drop a TCP transport mid-import.
		//    Sensitive (Wi-Fi PSK).
		if profile.hasConfig, config.hasNetwork {
			let ssid = config.network.wifiSsid
			items.append(ImportItem(kind: .networkConfig, section: .network,
									summary: ssid.isEmpty ? "Wi-Fi / Ethernet" : "Wi-Fi SSID: \(ssid)",
									isSensitive: true, mayReboot: true, payload: .networkConfig(config.network)))
		}

		// 10. Bluetooth — just before the terminal step because changing BLE mode/pin can drop the BLE
		//     transport the import runs over.
		if profile.hasConfig, config.hasBluetooth {
			items.append(ImportItem(kind: .bluetoothConfig, section: .radioAndDevice, summary: "Bluetooth settings",
									isSensitive: false, mayReboot: true, payload: .bluetoothConfig(config.bluetooth)))
		}

		// 11. Security — opt-in, sensitive. Late because admin-key/isManaged changes can restrict further
		//     local admin.
		if profile.hasConfig, config.hasSecurity {
			// Preserve the node's own keypair when the profile doesn't carry one (partial/event config).
			let mergedSecurity = DeviceProfileImportPlan.securityConfig(from: config.security, base: currentSecurity)
			let keepsIdentity = currentSecurity != nil && config.security.privateKey.isEmpty && config.security.publicKey.isEmpty
			items.append(ImportItem(kind: .securityConfig, section: .security,
									summary: keepsIdentity ? "Admin access & flags (keeps this node's keys)" : "Node identity, keys & admin access",
									isSensitive: true, mayReboot: true, payload: .securityConfig(mergedSecurity)))
		}

		// 12. TERMINAL: Channels & LoRa. The channel URL itself does not reboot (set_channel passes
		//     shouldReboot = false, AdminModule.cpp:1398). A standalone LoRa config does not reboot on
		//     firmware 2.8 (:1060) but DOES on the shipped 2.7.x line whenever a radio field changes, so it
		//     is flagged reboot-causing. Either way these stay last because they are the payload most likely
		//     to change the link the import is running over.
		//     Export puts the SAME LoRaConfig in both config.lora and
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
									isSensitive: true, mayReboot: false, payload: .channelURL(profile.channelURL)))
			addedChannelOrLoRa = true
		}
		if !addedChannelOrLoRa, profile.hasConfig, config.hasLora {
			items.append(ImportItem(kind: .loraConfig, section: .channelsAndLoRa,
									summary: "LoRa region: \(config.lora.region)",
									isSensitive: false, mayReboot: true, payload: .loraConfig(config.lora)))
		}

		// Split off anything this firmware cannot apply, so it is surfaced to the user instead of being
		// sent into a silent no-op.
		var applyable: [ImportItem] = []
		var rejected: [(item: ImportItem, support: FirmwareSupport)] = []
		for item in items {
			let support = item.kind.firmwareSupport
			if DeviceProfileImportPlan.isSupported(support, firmwareVersion: firmwareVersion) {
				applyable.append(item)
			} else {
				rejected.append((item, support))
			}
		}
		// A profile whose only contents are unsupported still has nothing we can apply.
		guard !applyable.isEmpty else { throw DeviceProfileImportError.nothingToImport }
		self.items = applyable
		self.unsupported = rejected
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
	/// Mirrors `AccessoryManager.checkIsVersionSupported`, including its permissive behaviour when the
	/// firmware version is unknown. Kept pure so the plan stays testable without a radio.
	static func isSupported(_ support: FirmwareSupport, firmwareVersion: String?) -> Bool {
		switch support {
		case .always:
			return true
		case .unimplemented:
			return false
		case .fromVersion(let required):
			// No firmware info at all: be permissive, matching the app's existing capability checks.
			guard let firmwareVersion, !firmwareVersion.isEmpty, firmwareVersion != "0.0.0" else { return true }
			let comparison = required.compare(firmwareVersion, options: .numeric)
			return comparison == .orderedAscending || comparison == .orderedSame
		}
	}

	func willReboot(in selection: Set<ImportSection>) -> Bool {
		items(for: selection).contains { $0.mayReboot }
	}
}
