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
			"meshtastic.Config.PowerConfig": (1, 2),                    // ADC override; power saving and battery rows by architecture
			"meshtastic.ModuleConfig.CannedMessageConfig": (0, 3),      // three sections locked while a preset is chosen
			"meshtastic.ModuleConfig.ExternalNotificationConfig": (0, 0),
			"meshtastic.ModuleConfig.MQTTConfig": (4, 1),               // proxy, consent, precision, root topic; TLS by firmware
			"meshtastic.ModuleConfig.NeighborInfoConfig": (0, 0),
			"meshtastic.ModuleConfig.SerialConfig": (0, 0),
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
		MQTTConfig.reconcile(&edited, tlsRequired: true)
		#expect(edited.username == "me", "a private server keeps its own credentials")
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
}
