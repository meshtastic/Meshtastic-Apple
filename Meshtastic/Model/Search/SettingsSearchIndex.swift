//
//  SettingsSearchIndex.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/13/26.
//
import Foundation

/// The searchable catalogue of every control under Settings.
///
/// Two halves, joined here. Proto-backed settings take their label, description
/// and keywords from the generated `FieldMetadataRegistry`, so they cannot drift
/// from the schema every client reads. App-level settings, which have no protobuf
/// behind them, are curated in `SettingsSearchCatalogue`.
///
/// Built once and held; nothing here varies per query. Whether a result is shown,
/// dimmed or hidden is decided by `SettingsSearchEngine` from connection and node
/// state at the moment the user types.
enum SettingsSearchIndex {

	/// Every indexed control, proto-backed first.
	///
	/// A curated entry is dropped when the registry already describes a control with
	/// the same label on the same screen. Some screens are mixed — TAK Server shows
	/// `ModuleConfig.TAKConfig.team` and `.role` alongside app-only controls — and two
	/// entries with one identity are indistinguishable in results. The schema wins,
	/// since its label is the one every client shares.
	static let entries: [SettingsSearchEntry] = {
		let fromRegistry = protoBackedEntries()
		let claimed = Set(fromRegistry.map(\.id))
		return fromRegistry + SettingsSearchCatalogue.entries.filter { !claimed.contains($0.id) }
	}()

	/// Where a config message's fields live in the Settings tree.
	///
	/// The message-to-screen link is the one part of this that is machine-derivable
	/// — `ConfigHeader(title:config:)` already pairs a screen title with a keypath
	/// on `NodeInfoEntity` — but it is not exposed in a form this can read, so it is
	/// written out. The completeness test is what keeps it honest.
	struct ScreenMapping {
		let destination: SettingsNavigationState
		let title: String
		let section: SettingsListSection
	}

	static let screens: [String: ScreenMapping] = [
		"meshtastic.Config.LoRaConfig": .init(
			destination: .lora, title: String(localized: "LoRa", comment: "Settings screen"),
			section: .radioConfiguration),
		"meshtastic.Config.SecurityConfig": .init(
			destination: .security, title: String(localized: "Security", comment: "Settings screen"),
			section: .radioConfiguration),
		"meshtastic.Config.BluetoothConfig": .init(
			destination: .bluetooth, title: String(localized: "Bluetooth", comment: "Settings screen"),
			section: .deviceConfiguration),
		"meshtastic.Config.DeviceConfig": .init(
			destination: .device, title: String(localized: "Device", comment: "Settings screen"),
			section: .deviceConfiguration),
		"meshtastic.Config.DisplayConfig": .init(
			destination: .display, title: String(localized: "Display", comment: "Settings screen"),
			section: .deviceConfiguration),
		"meshtastic.Config.NetworkConfig": .init(
			destination: .network, title: String(localized: "Network", comment: "Settings screen"),
			section: .deviceConfiguration),
		"meshtastic.Config.PositionConfig": .init(
			destination: .position, title: String(localized: "Position", comment: "Settings screen"),
			section: .deviceConfiguration),
		"meshtastic.Config.PowerConfig": .init(
			destination: .power, title: String(localized: "Power", comment: "Settings screen"),
			section: .deviceConfiguration),
		"meshtastic.ModuleConfig.AmbientLightingConfig": .init(
			destination: .ambientLighting,
			title: String(localized: "Ambient Lighting", comment: "Settings screen"), section: .configure),
		"meshtastic.ModuleConfig.AudioConfig": .init(
			destination: .audio, title: String(localized: "Audio", comment: "Settings screen"),
			section: .configure),
		"meshtastic.ModuleConfig.CannedMessageConfig": .init(
			destination: .cannedMessages,
			title: String(localized: "Canned Messages", comment: "Settings screen"), section: .configure),
		"meshtastic.ModuleConfig.DetectionSensorConfig": .init(
			destination: .detectionSensor,
			title: String(localized: "Detection Sensor", comment: "Settings screen"), section: .configure),
		"meshtastic.ModuleConfig.ExternalNotificationConfig": .init(
			destination: .externalNotification,
			title: String(localized: "External Notification", comment: "Settings screen"), section: .configure),
		"meshtastic.ModuleConfig.MQTTConfig": .init(
			destination: .mqtt, title: String(localized: "MQTT", comment: "Settings screen"),
			section: .configure),
		"meshtastic.ModuleConfig.MapReportSettings": .init(
			destination: .mqtt, title: String(localized: "MQTT", comment: "Settings screen"),
			section: .configure),
		"meshtastic.ModuleConfig.MeshBeaconConfig": .init(
			destination: .meshBeacon, title: String(localized: "Mesh Beacon", comment: "Settings screen"),
			section: .configure),
		"meshtastic.ModuleConfig.NeighborInfoConfig": .init(
			destination: .neighborInfo,
			title: String(localized: "Neighbor Info", comment: "Settings screen"), section: .configure),
		"meshtastic.ModuleConfig.PaxcounterConfig": .init(
			destination: .paxCounter, title: String(localized: "PAX Counter", comment: "Settings screen"),
			section: .configure),
		"meshtastic.ModuleConfig.RangeTestConfig": .init(
			destination: .rangeTest, title: String(localized: "Range Test", comment: "Settings screen"),
			section: .configure),
		"meshtastic.ModuleConfig.SerialConfig": .init(
			destination: .serial, title: String(localized: "Serial", comment: "Settings screen"),
			section: .configure),
		"meshtastic.ModuleConfig.StoreForwardConfig": .init(
			destination: .storeAndForward,
			title: String(localized: "Store and Forward", comment: "Settings screen"), section: .configure),
		"meshtastic.ModuleConfig.TAKConfig": .init(
			destination: .tak, title: String(localized: "TAK", comment: "Settings screen"),
			section: .configure),
		"meshtastic.ModuleConfig.TelemetryConfig": .init(
			destination: .telemetry, title: String(localized: "Telemetry", comment: "Settings screen"),
			section: .configure),
		"meshtastic.ModuleConfig.TrafficManagementConfig": .init(
			destination: .trafficManagement,
			title: String(localized: "Traffic Management", comment: "Settings screen"), section: .configure)
	]

	/// Every annotated field that maps to a screen, turned into an entry.
	///
	/// Driven by the registry rather than a hand-written list, so a field annotated
	/// upstream appears here with no app change. A field whose message has no screen
	/// mapping is skipped: `RemoteHardwarePin` and friends have no UI.
	static func protoBackedEntries() -> [SettingsSearchEntry] {
		FieldMetadataRegistry.registry.compactMap { key, metadata -> SettingsSearchEntry? in
			guard let label = metadata.label, !label.isEmpty else { return nil }
			let parts = key.split(separator: "#")
			guard parts.count == 2, let tag = Int(parts[1]) else { return nil }
			let messageName = String(parts[0])
			guard let screen = screens[messageName] else { return nil }

			return SettingsSearchEntry(
				destination: screen.destination,
				screenTitle: screen.title,
				listSection: screen.section,
				label: label,
				subtitle: metadata.description,
				keywords: Self.keywords(from: metadata.keywords),
				field: FieldIdentity(messageName: messageName, tag: tag),
				requiresConnection: true
			)
		}
		// The registry is a dictionary, so iteration order is not stable. Sort, or
		// the index — and every equal-scoring result — reshuffles between launches.
		.sorted { $0.id < $1.id }
	}

	/// Splits the `|`-delimited keyword string the schema carries.
	///
	/// `FieldMetadata` attributes must be scalar, so a list has to travel as one
	/// string. `|` rather than `,` because a keyword may contain a comma.
	static func keywords(from raw: String?) -> [String] {
		guard let raw, !raw.isEmpty else { return [] }
		return raw.split(separator: "|")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}
}
