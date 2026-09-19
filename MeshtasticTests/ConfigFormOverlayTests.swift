//
//  ConfigFormOverlayTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import Testing
import MeshtasticProtobufs
@testable import Meshtastic

/// Keeps the screen overlays honest against the schema and the registry.
@Suite("Configuration form overlays")
struct ConfigFormOverlayTests {

	@Test("Every migrated overlay lays out or omits every renderable field, with labels for all of them")
	func overlaysAreComplete() throws {
		for overlay in ConfigFormOverlays.all {
			let problems = overlay.problems()
			#expect(problems.isEmpty, "\(overlay.protoName):\n\(problems.joined(separator: "\n"))")
		}
	}

	@Test("Every message with a settings screen is either on the generic form or listed as bespoke")
	func everyScreenIsAccountedFor() throws {
		let migrated = Set(ConfigFormOverlays.all.map(\.protoName))
		let bespoke = Set(ConfigFormOverlays.bespoke.keys)
		#expect(migrated.isDisjoint(with: bespoke), "a message is in both lists: \(migrated.intersection(bespoke))")
		for message in SettingsSearchIndex.screens.keys {
			#expect(migrated.contains(message) || bespoke.contains(message),
					"\(message) has a settings screen but is in neither ConfigFormOverlays.all nor .bespoke")
		}
	}

	@Test("Escape hatches are used deliberately")
	func escapeHatchesArePinned() throws {
		// Grow these numbers in the pull request that adds the hatch, so it is reviewed as one.
		let expected: [String: (custom: Int, environment: Int)] = [
			"meshtastic.Config.BluetoothConfig": (1, 0),                // the six-digit PIN field
			"meshtastic.Config.DeviceConfig": (1, 0),                   // role picker with its warning
			"meshtastic.Config.DisplayConfig": (0, 2),                  // compass control by firmware version
			"meshtastic.Config.PowerConfig": (1, 2),                    // ADC override; power saving and battery rows by architecture
			"meshtastic.ModuleConfig.AmbientLightingConfig": (1, 0),    // one colour picker for three channels
			"meshtastic.ModuleConfig.CannedMessageConfig": (0, 3),      // three sections locked while a preset is chosen
			"meshtastic.ModuleConfig.ExternalNotificationConfig": (0, 0),
			"meshtastic.ModuleConfig.MQTTConfig": (4, 1),               // proxy, consent, precision, root topic; TLS by firmware
			"meshtastic.ModuleConfig.NeighborInfoConfig": (0, 0),
			"meshtastic.ModuleConfig.PaxcounterConfig": (0, 0),
			"meshtastic.ModuleConfig.RangeTestConfig": (0, 1),          // save needs WiFi
			"meshtastic.ModuleConfig.SerialConfig": (0, 0),
			"meshtastic.ModuleConfig.StoreForwardConfig": (0, 0),
			"meshtastic.ModuleConfig.TelemetryConfig": (0, 2),          // device-telemetry toggle by firmware version
			"meshtastic.ModuleConfig.TrafficManagementConfig": (0, 4)   // four feature sections behind the main switch
		]
		for overlay in ConfigFormOverlays.all {
			let pinned = try #require(expected[overlay.protoName], "\(overlay.protoName) has no pinned hatch counts")
			#expect(overlay.customControlCount == pinned.custom, "\(overlay.protoName) custom controls")
			#expect(overlay.environmentConditionCount == pinned.environment, "\(overlay.protoName) environment conditions")
		}
	}

	@Test("Conditions read the field they name")
	func conditionsEvaluate() throws {
		typealias F = ModuleConfig.NeighborInfoConfig.Fields
		var message = ModuleConfig.NeighborInfoConfig()
		let env = ConfigFormEnvironment(node: nil, isConnected: true, isConnectedNode: true, isDIYHardware: false,
										hasWifi: false, hasEthernet: false, hasXeddsa: false, firmwareAtLeast: { _ in true })
		let enabled = ConfigFormCondition<ModuleConfig.NeighborInfoConfig>.isTrue(F.enabled)
		#expect(!enabled.evaluate(message, env))
		message.enabled = true
		#expect(enabled.evaluate(message, env))
		#expect(!ConfigFormCondition<ModuleConfig.NeighborInfoConfig>.not(enabled).evaluate(message, env))
		let interval = ConfigFormCondition<ModuleConfig.NeighborInfoConfig>.nonZero(F.updateInterval)
		#expect(!interval.evaluate(message, env))
		message.updateInterval = 900
		#expect(interval.evaluate(message, env))
		#expect(ConfigFormCondition<ModuleConfig.NeighborInfoConfig>.firmware(atLeast: "2.8.0").isEnvironmental)
		#expect(!enabled.isEnvironmental)
	}

	@Test("The entity bridge carries every field the screen shows")
	func entityBridgeRoundTrips() throws {
		let entity = SerialConfigEntity()
		entity.enabled = true
		entity.echo = true
		entity.rxd = 5
		entity.txd = 6
		entity.baudRate = Int32(ModuleConfig.SerialConfig.Serial_Baud.baud115200.rawValue)
		entity.timeout = 30
		entity.mode = Int32(ModuleConfig.SerialConfig.Serial_Mode.nmea.rawValue)
		entity.overrideConsoleSerialPort = true
		let message = ModuleConfig.SerialConfig(entity: entity)
		#expect(message.enabled && message.echo)
		#expect(message.rxd == 5 && message.txd == 6)
		#expect(message.baud == .baud115200)
		#expect(message.timeout == 30)
		#expect(message.mode == .nmea)
		#expect(message.overrideConsoleSerialPort, "the old screen dropped this; the bridge must not")
	}

	@Test("A search result finds the row its field is laid out in")
	func overlayFindsTheRowForAField() throws {
		let serial = SerialConfig.overlay()
		let baud = ModuleConfig.SerialConfig.Fields.baud
		#expect(serial.rowID(for: baud.identity) == baud.name)
		// A field this screen omits has no row to scroll to.
		#expect(serial.rowID(for: ModuleConfig.SerialConfig.Fields.overrideConsoleSerialPort.identity) == nil)
		// Nor does a field belonging to another message, whose tags would otherwise collide.
		#expect(serial.rowID(for: FieldIdentity(messageName: "meshtastic.Config.DeviceConfig", tag: baud.tag)) == nil)
	}

	@Test("A search result for a migrated screen lands on a control, not just the screen")
	func searchResultsResolveToRows() throws {
		// The point of the deep link: a result that opens the right screen but cannot
		// name a row scrolls nowhere. Every indexed field whose screen is on the generic
		// form has to resolve, or the result silently degrades to screen-level.
		let byName = Dictionary(uniqueKeysWithValues: ConfigFormOverlays.all.map { ($0.protoName, $0) })
		var checked = 0
		for entry in SettingsSearchIndex.entries {
			guard let field = entry.field, let overlay = byName[field.messageName] else { continue }
			checked += 1
			// Either the screen has a row for it, or it deliberately omits it - a field
			// folded into another control names that control with `coveredBy`, and one
			// the client does not offer at all has nothing to scroll to by design.
			#expect(overlay.rowID(for: field) != nil || overlay.omits(field),
					"\(field.messageName)#\(field.tag) (\(entry.label)) is indexed but the form neither shows nor omits it")
		}
		#expect(checked > 0, "no indexed field reached a migrated screen; the lookup is not being exercised")
	}

	@Test("Traffic Management's main switch derives from the values and clears them")
	func trafficManagementMainSwitch() {
		var message = ModuleConfig.TrafficManagementConfig()
		#expect(!TrafficManagementConfig.isActive(message))
		message.rateLimitWindowSecs = 60
		message.rateLimitMaxPackets = 20
		#expect(TrafficManagementConfig.isActive(message))
		#expect(!TrafficManagementConfig.isActive(TrafficManagementConfig.cleared(message)))
		// A cleared window takes the packet count with it.
		message.rateLimitWindowSecs = 0
		TrafficManagementConfig.reconcile(&message)
		#expect(message.rateLimitMaxPackets == 0)
	}

	@Test("MQTT keeps the old screen's load-time rules")
	func mqttNormalise() {
		var message = ModuleConfig.MQTTConfig()
		message.address = "MQTT.meshtastic.org"
		message.mapReportSettings.positionPrecision = 11
		message.mapReportSettings.publishIntervalSecs = 60
		let normalised = MQTTConfig.normalize(message, tlsRequired: true)
		#expect(normalised.mapReportSettings.positionPrecision == 14)
		#expect(normalised.mapReportSettings.publishIntervalSecs == 3600)
		#expect(normalised.tlsEnabled, "the public server needs TLS on firmware that requires it")
		#expect(!MQTTConfig.normalize(message, tlsRequired: false).tlsEnabled)
		var edited = normalised
		MQTTConfig.reconcile(&edited, tlsRequired: true)
		#expect(edited.username == "meshdev" && edited.password == "large4cats")
		edited.address = "broker.example.org"
		edited.username = "me"
		edited.password = "hunter2"
		MQTTConfig.reconcile(&edited, tlsRequired: true)
		#expect(edited.username == "me", "a private server keeps its own credentials")
		#expect(edited.password == "hunter2", "and its own password")
		// A host that merely starts with the public one belongs to somebody else.
		#expect(!MQTTConfig.usesPublicServer("mqtt.meshtastic.org.example.com"))
		#expect(MQTTConfig.usesPublicServer("mqtt.meshtastic.org"))
		#expect(MQTTConfig.usesPublicServer("MQTT.Meshtastic.org:1883"), "host match ignores case and port")
	}

	@Test("Canned Messages presets fill in the hardware they name")
	func cannedMessagesPresets() {
		var message = ModuleConfig.CannedMessageConfig()
		CannedMessagesConfig.apply(.rakRotaryEncoder, to: &message)
		#expect(message.updown1Enabled && !message.rotary1Enabled)
		#expect(message.inputbrokerPinA == 4 && message.inputbrokerPinB == 10 && message.inputbrokerPinPress == 9)
		#expect(message.inputbrokerEventCw == .down && message.inputbrokerEventCcw == .up && message.inputbrokerEventPress == .select)
		CannedMessagesConfig.apply(.cardKB, to: &message)
		#expect(!message.updown1Enabled && message.inputbrokerPinA == 0 && message.inputbrokerEventPress == .none)
	}

	@Test("Device's inverted and retired values bridge and normalise as the old screen did")
	func deviceBridgeAndNormalise() throws {
		let entity = DeviceConfigEntity()
		entity.tripleClickAsAdHocPing = true
		entity.ledHeartbeatEnabled = false
		entity.role = Int32(Config.DeviceConfig.Role.routerClient.rawValue)
		entity.nodeInfoBroadcastSecs = 600
		let message = Config.DeviceConfig(entity: entity)
		#expect(!message.disableTripleClick, "the entity stores the positive sense")
		#expect(message.ledHeartbeatDisabled)
		let normalised = DeviceConfig.normalize(message)
		#expect(normalised.role == .clientMute)
		#expect(normalised.nodeInfoBroadcastSecs == 10800)
	}

	@Test("Telemetry reads Int32.max as off only on firmware without the toggle")
	func telemetryLegacyOff() {
		var message = ModuleConfig.TelemetryConfig()
		message.deviceUpdateInterval = UInt32(Int32.max)
		message.deviceTelemetryEnabled = true
		#expect(!TelemetryConfig.normalize(message, legacy: true).deviceTelemetryEnabled)
		#expect(TelemetryConfig.normalize(message, legacy: false).deviceTelemetryEnabled)
		message.deviceUpdateInterval = 1800
		#expect(TelemetryConfig.normalize(message, legacy: true).deviceTelemetryEnabled)
	}

	@Test("The irregular entity names bridge to the right proto fields")
	func irregularEntityNamesBridge() throws {
		let store = StoreForwardConfigEntity()
		store.isRouter = true
		store.historyReturnWindow = 7200
		let sf = ModuleConfig.StoreForwardConfig(entity: store)
		#expect(sf.isServer, "the entity calls is_server isRouter")
		#expect(sf.historyReturnWindow == 7200)

		let bt = BluetoothConfigEntity()
		bt.mode = Int32(Config.BluetoothConfig.PairingMode.fixedPin.rawValue)
		bt.fixedPin = 654321
		let bluetooth = Config.BluetoothConfig(entity: bt)
		#expect(bluetooth.mode == .fixedPin)
		#expect(bluetooth.fixedPin == 654321)

		let pax = PaxCounterConfigEntity()
		pax.wifiThreshold = -70
		pax.updateInterval = 900
		let counter = ModuleConfig.PaxcounterConfig(entity: pax)
		#expect(counter.wifiThreshold == -70 && counter.paxcounterUpdateInterval == 900)
	}

	@Test("Bluetooth waits for the sixth PIN digit before it will save")
	func bluetoothShortPinHoldsSave() {
		var message = Config.BluetoothConfig()
		message.mode = .fixedPin
		#expect(!BluetoothConfig.canSave(message, pinIsComplete: false), "a short PIN must not save the previous one")
		#expect(BluetoothConfig.canSave(message, pinIsComplete: true))
		// The PIN is only used for fixed-pin pairing, so it cannot block the other modes.
		message.mode = .randomPin
		#expect(BluetoothConfig.canSave(message, pinIsComplete: false))
	}

	@Test("The MQTT bridge keeps a flag the old screen always cleared")
	func mqttBridgeKeepsJSONEnabled() {
		let entity = MQTTConfigEntity()
		entity.jsonEnabled = true
		entity.address = "broker.example.org"
		// The hand-written screen built its message from scratch and never wrote this,
		// so every save turned it off. It round-trips now.
		#expect(ModuleConfig.MQTTConfig(entity: entity).jsonEnabled)
	}

	@Test("Canned Messages sends only what changed, on the right admin message")
	func cannedMessagesSendOnlyWhatChanged() {
		let entity = CannedMessageConfigEntity()
		entity.sendBell = true
		entity.messages = "Hello|Yes"
		let stored = ModuleConfig.CannedMessageConfig(entity: entity)

		// Editing the text must not send the module config, which does not carry it.
		let textOnly = CannedMessagesConfig.pending(config: stored, stored: entity,
													messages: "Hello|Yes|No", loadedMessages: "Hello|Yes")
		#expect(textOnly.messages && !textOnly.config)

		// Editing a control must not re-send the text as a second admin message.
		var edited = stored
		edited.sendBell = false
		let configOnly = CannedMessagesConfig.pending(config: edited, stored: entity,
													  messages: "Hello|Yes", loadedMessages: "Hello|Yes")
		#expect(configOnly.config && !configOnly.messages)

		// Nothing changed: nothing to send.
		let quiet = CannedMessagesConfig.pending(config: stored, stored: entity,
												 messages: "Hello|Yes", loadedMessages: "Hello|Yes")
		#expect(!quiet.config && !quiet.messages)
	}

	@Test("A focus request does not outlive the navigation that made it")
	@MainActor
	func focusRequestDoesNotGoStale() {
		let router = Router()
		let baud = ModuleConfig.SerialConfig.Fields.baud.identity
		router.navigate(toSetting: .serial, focusing: baud)
		#expect(router.settingsFieldFocus == baud)

		// Opening a settings screen any other way drops it, so a screen that happens to
		// own the field cannot pick up a request meant for an earlier navigation.
		router.navigate(toSetting: .lora)
		#expect(router.settingsFieldFocus == nil)

		router.navigate(toSetting: .serial, focusing: baud)
		router.popToRoot(tab: .settings)
		#expect(router.settingsFieldFocus == nil)

		router.navigate(toSetting: .serial, focusing: baud)
		router.clearSettingsFieldFocus()
		#expect(router.settingsFieldFocus == nil, "the screen that honours it takes it")
	}
}
