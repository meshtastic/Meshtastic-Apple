//
//  MQTTConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import CoreLocation
import OSLog
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.MQTTConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, MQTTConfigEntity?> = \NodeInfoEntity.mqttConfig

	init(entity: MQTTConfigEntity) {
		self.init()
		enabled = entity.enabled
		proxyToClientEnabled = entity.proxyToClientEnabled
		address = entity.address ?? ""
		username = entity.username ?? ""
		password = entity.password ?? ""
		root = entity.root ?? "msh"
		encryptionEnabled = entity.encryptionEnabled
		// The old screen always wrote this false. It now round-trips from the entity.
		jsonEnabled = entity.jsonEnabled
		tlsEnabled = entity.tlsEnabled
		mapReportingEnabled = entity.mapReportingEnabled
		mapReportSettings.publishIntervalSecs = UInt32(truncatingIfNeeded: entity.mapPublishIntervalSecs)
		mapReportSettings.positionPrecision = UInt32(truncatingIfNeeded: entity.mapPositionPrecision)
		mapReportSettings.shouldReportLocation = entity.mapReportingShouldReportLocation
	}
}

struct MQTTConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.MQTTConfig.Fields

	static let publicServer = "mqtt.meshtastic.org"
	/// Firmware from here requires TLS to the public server; the toggle is locked on.
	static let tlsRequiredFirmware = "2.7.3"

	/// Host equality, not a substring: `mqtt.meshtastic.org.example.com` is somebody
	/// else's server, and treating it as the public one would hide the credential
	/// fields and overwrite what was typed with the public defaults. The address the
	/// firmware accepts is a host with an optional port, never a scheme or a path.
	static func usesPublicServer(_ address: String) -> Bool {
		let host = address.trimmingCharacters(in: .whitespaces)
			.lowercased()
			.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
			.first
			.map(String.init) ?? ""
		return host == publicServer
	}

	/// The load-time rules the old screen applied: the map report precision the firmware
	/// accepts, the hour floor on its interval, TLS to the public server, and the app's own
	/// record of consent to report location, which is kept across nodes.
	static func normalize(_ config: ModuleConfig.MQTTConfig, tlsRequired: Bool) -> ModuleConfig.MQTTConfig {
		var c = config
		if c.mapReportSettings.positionPrecision < 12 || c.mapReportSettings.positionPrecision > 15 {
			c.mapReportSettings.positionPrecision = 14
		}
		c.mapReportSettings.publishIntervalSecs = max(3600, c.mapReportSettings.publishIntervalSecs)
		if tlsRequired, usesPublicServer(c.address) { c.tlsEnabled = true }
		c.mapReportSettings.shouldReportLocation = UserDefaults.mapReportingOptIn
		return c
	}

	/// The public server takes one set of credentials, and TLS on firmware that requires it.
	static func reconcile(_ config: inout ModuleConfig.MQTTConfig, tlsRequired: Bool) {
		guard usesPublicServer(config.address) else { return }
		config.username = "meshdev"
		config.password = "large4cats"
		if tlsRequired { config.tlsEnabled = true }
	}

	static func overlay(node: NodeInfoEntity? = nil) -> ConfigFormOverlay<ModuleConfig.MQTTConfig> {
		typealias Condition = ConfigFormCondition<ModuleConfig.MQTTConfig>
		let publicServer = Condition.satisfies(F.address, usesPublicServer)
		let consented = Condition.all([.isTrue(F.mapReportingEnabled), .isTrue(F.mapReportSettings_shouldReportLocation)])
		return .init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.enabled, symbol: "dot.radiowaves.up.forward"),
				.init(F.proxyToClientEnabled, symbol: "iphone.radiowaves.left.and.right",
					  control: .custom { config in AnyView(MQTTProxyRows(config: config, node: node)) }),
				.init(F.encryptionEnabled, symbol: "lock.icloud")
			]),
			.init(title: String(localized: "Map Report", comment: "Settings section"), fields: [
				.init(F.mapReportingEnabled, symbol: "map"),
				.init(F.mapReportSettings_shouldReportLocation, shownWhen: .isTrue(F.mapReportingEnabled),
					  control: .custom { config in AnyView(MapReportConsent(consented: config.mapReportSettings.shouldReportLocation)) }),
				.init(F.mapReportSettings_publishIntervalSecs, shownWhen: consented, control: .interval(.broadcastMedium)),
				// Unlabelled upstream, and the precision needs its own explanation anyway.
				.init(F.mapReportSettings_positionPrecision, shownWhen: consented,
					  control: .custom { config in AnyView(MapReportPrecision(precision: config.mapReportSettings.positionPrecision)) })
			]),
			.init(title: String(localized: "Root Topic", comment: "Settings section"), fields: [
				.init(F.root, symbol: "tree", control: .custom { config in AnyView(RootTopicField(root: config.root, node: node)) })
			]),
			.init(title: String(localized: "Server", comment: "Settings section"), fields: [
				.init(F.address, symbol: "server.rack", byteCap: 63),
				.init(F.username, symbol: "person.text.rectangle", shownWhen: .not(publicServer), byteCap: 63),
				.init(F.password, symbol: "wallet.pass", shownWhen: .not(publicServer), control: .secure, byteCap: 31),
				// Locked on for the public server once the firmware requires it; hidden before that.
				.init(F.tlsEnabled, symbol: "checkmark.shield.fill",
					  shownWhen: .any([.not(publicServer), .firmware(atLeast: tlsRequiredFirmware)]),
					  enabledWhen: .not(publicServer))
			])
		], omitted: [
			.init(F.jsonEnabled, "deprecated upstream and never offered; round-trips from the entity")
		])
	}

	private var dutyCycle: Int? {
		guard let regionCode = node?.loRaConfig?.regionCode, let region = RegionCodes(rawValue: Int(regionCode)) else { return nil }
		return region.dutyCycle
	}

	var body: some View {
		let tlsRequired = accessoryManager.checkIsVersionSupported(forVersion: Self.tlsRequiredFirmware)
		MetadataConfigForm(
			node: node, title: "MQTT", overlay: Self.overlay(node: node),
			normalize: { Self.normalize($0, tlsRequired: tlsRequired) },
			reconcile: { config, env in Self.reconcile(&config, tlsRequired: env.firmwareAtLeast(Self.tlsRequiredFirmware)) },
			request: accessoryManager.requestMqttModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveMQTTConfig(config: config, fromUser: from, toUser: to)
			},
			leading: { _ in
				if let dutyCycle, dutyCycle > 0, dutyCycle < 100 {
					Text("Your region has a \(dutyCycle)% duty cycle. MQTT is not advised when you are duty cycle restricted, the extra traffic will quickly overwhelm your LoRa mesh.")
						.font(.callout)
						.foregroundColor(.red)
				}
			},
			trailing: { _ in
				Text("For all Mqtt functionality other than the map report you must also set uplink and downlink for each channel you want to bridge over Mqtt.")
					.font(.callout)
			})
		.navigationTitle("MQTT Config")
	}
}

/// The proxy toggle, and beneath it the app's own switch to connect through the phone,
/// which only appears once the radio has the proxy setting saved.
private struct MQTTProxyRows: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Binding var config: ModuleConfig.MQTTConfig
	let node: NodeInfoEntity?
	@State private var connected = false

	private static let metadata = FieldMetadataRegistry.get("meshtastic.ModuleConfig.MQTTConfig", tag: 9)

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Toggle(isOn: $config.proxyToClientEnabled) {
				Label(Self.metadata?.label ?? "MQTT Client Proxy", systemImage: "iphone.radiowaves.left.and.right")
			}
			if let description = Self.metadata?.description {
				Text(description)
					.foregroundColor(.gray)
					.font(.callout)
			}
		}
		if config.enabled, config.proxyToClientEnabled, node?.mqttConfig?.proxyToClientEnabled == true {
			Toggle(isOn: $connected) {
				Label("Connect to MQTT via Proxy", systemImage: "server.rack")
				if !accessoryManager.mqttError.isEmpty {
					Text(accessoryManager.mqttError)
						.fixedSize(horizontal: false, vertical: true)
						.foregroundColor(.red)
				}
			}
			.onAppear { connected = accessoryManager.mqttProxyConnected }
			.onChange(of: accessoryManager.mqttProxyConnected) { _, now in connected = now }
			.onChange(of: connected) { _, on in
				if on {
					if !accessoryManager.mqttProxyConnected, let node { accessoryManager.mqttManager.connectFromConfigSettings(node: node) }
				} else if accessoryManager.mqttProxyConnected {
					accessoryManager.mqttManager.disconnect()
				}
			}
		}
	}
}

/// The consent text and its toggle. The toggle writes the field and the app's own record,
/// which `normalize` reads back on load, so consent given once holds for every node.
private struct MapReportConsent: View {
	@Binding var consented: Bool

	private static let metadata = FieldMetadataRegistry.get("meshtastic.ModuleConfig.MapReportSettings", tag: 3)

	var body: some View {
		Text("Consent to Share Unencrypted Node Data via MQTT")
		Text("By enabling this feature, you acknowledge and expressly consent to the transmission of your device’s real-time geographic location over the MQTT protocol without encryption. This location data may be used for purposes such as live map reporting, device tracking, and related telemetry functions.")
			.foregroundColor(.gray)
			.font(.caption)
		Text("Please be advised that because the map report is not encrypted, your data may be stored and displayed permanently by third parties. Meshtastic does not assume responsibility for any such storage, display or disclosure of this data.")
			.foregroundColor(.gray)
			.font(.caption)
		Toggle(isOn: Binding(get: { consented }, set: { consented = $0; UserDefaults.mapReportingOptIn = $0 })) {
			Label(Self.metadata?.description ?? "I have read and understand the above. I voluntarily consent to the unencrypted transmission of my node data via MQTT.", systemImage: "hand.raised")
				.foregroundColor(.gray)
				.font(.callout)
		}
	}
}

/// The 12-15 bit precision slider with the distance each setting means.
private struct MapReportPrecision: View {
	@Binding var precision: UInt32

	private var description: String { PositionPrecision(rawValue: Int(precision))?.description ?? "" }

	var body: some View {
		VStack(alignment: .leading) {
			Label("Approximate Location", systemImage: "location.slash.circle.fill")
			Text("To comply with privacy laws like CCPA and GDPR, we avoid sharing exact location data. Instead, we use anonymized or approximate (imprecise) location information to protect your privacy.")
				.foregroundColor(.gray)
				.font(.callout)
			Slider(value: Binding(get: { Double(precision) }, set: { precision = UInt32($0) }), in: 12...15, step: 1) {
			} minimumValueLabel: {
				Image(systemName: "plus")
					.accessibilityHidden(true)
			} maximumValueLabel: {
				Image(systemName: "minus")
					.accessibilityHidden(true)
			}
			.accessibilityLabel(String(localized: "Approximate location precision", comment: "VoiceOver label for the approximate location precision slider"))
			.accessibilityValue(description)
			Text(description)
				.foregroundColor(.gray)
				.font(.callout)
		}
	}
}

/// The root topic, with the topics for the phone's own region, state, county, city and
/// neighbourhood offered beneath it.
private struct RootTopicField: View {
	@Binding var root: String
	let node: NodeInfoEntity?
	@State private var nearbyTopics: [String] = []
	@State private var selectedTopic = ""

	private static let byteCap = 31
	private static let metadata = FieldMetadataRegistry.get("meshtastic.ModuleConfig.MQTTConfig", tag: 8)

	var body: some View {
		HStack {
			Label(Self.metadata?.label ?? "Root Topic", systemImage: "tree")
			TextField(Self.metadata?.label ?? "Root Topic", text: $root)
				.foregroundColor(.gray)
				.keyboardType(.asciiCapable)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.never)
				.onChange(of: root) { _, new in
					var trimmed = new
					while trimmed.utf8.count > Self.byteCap { trimmed = String(trimmed.dropLast()) }
					if trimmed != new { root = trimmed }
				}
		}
		.listRowSeparator(.hidden)
		.onAppear(perform: findNearbyTopics)
		Text("The root topic to use for MQTT.")
			.foregroundColor(.gray)
			.font(.callout)
		if !nearbyTopics.isEmpty {
			Picker("Nearby Topics", selection: $selectedTopic) {
				ForEach(nearbyTopics, id: \.self) { Text($0) }
			}
			.pickerStyle(InlinePickerStyle())
			.listRowSeparator(.hidden)
			.onChange(of: selectedTopic) { _, topic in root = topic }
			Text("If the default region topic is too busy you can choose a more local topic.")
				.foregroundColor(.gray)
				.font(.callout)
		}
	}

	private func findNearbyTopics() {
		nearbyTopics = []
		guard let location = LocationsHandler.shared.locationsArray.first else { return }
		let region = RegionCodes(rawValue: Int(node?.loRaConfig?.regionCode ?? 0))
		let defaultTopic = "msh/" + (region?.topic ?? "UNSET")
		CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
			if let error {
				Logger.services.error("Failed to reverse geocode location: \(error.localizedDescription, privacy: .public)")
				return
			}
			guard let placemark = placemarks?.first else {
				Logger.services.debug("No Location")
				return
			}
			var topics: [String] = []
			if !(region?.isCountry ?? false) {
				topics.append(defaultTopic + "/" + (placemark.isoCountryCode ?? ""))
			}
			let state = placemark.administrativeArea ?? ""
			topics.append(defaultTopic + "/" + state)
			topics.append(defaultTopic + "/" + state + "/" + (placemark.subAdministrativeArea?.lowercased().replacingOccurrences(of: " ", with: "") ?? ""))
			topics.append(defaultTopic + "/" + state + "/" + (placemark.locality?.lowercased().replacingOccurrences(of: " ", with: "") ?? ""))
			topics.append(defaultTopic + "/" + state + "/" + (placemark.subLocality?.lowercased()
				.replacingOccurrences(of: " ", with: "")
				.replacingOccurrences(of: "'", with: "") ?? ""))
			nearbyTopics = topics.filter { !$0.isEmpty }
		}
	}
}
