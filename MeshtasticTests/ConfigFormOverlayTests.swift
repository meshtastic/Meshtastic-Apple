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
			"meshtastic.Config.DeviceConfig": (1, 0),           // role picker with its warning
			"meshtastic.Config.DisplayConfig": (0, 2),          // compass control by firmware version
			"meshtastic.ModuleConfig.AmbientLightingConfig": (1, 0), // one colour picker for three channels
			"meshtastic.ModuleConfig.ExternalNotificationConfig": (0, 0),
			"meshtastic.ModuleConfig.NeighborInfoConfig": (0, 0),
			"meshtastic.ModuleConfig.SerialConfig": (0, 0),
			"meshtastic.ModuleConfig.TelemetryConfig": (0, 2)   // device-telemetry toggle by firmware version
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
}
