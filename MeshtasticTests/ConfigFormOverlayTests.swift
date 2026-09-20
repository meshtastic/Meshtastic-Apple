//
//  ConfigFormOverlayTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import Testing
import SwiftUI
import MeshtasticProtobufs
@testable import Meshtastic

/// An environment for a radio on `version`, comparing the way `checkIsVersionSupported`
/// does. Pass nil for a node whose firmware the app does not know.
private func testEnvironment(firmware version: String?) -> ConfigFormEnvironment {
	ConfigFormEnvironment(
		node: nil, isConnected: version != nil, isConnectedNode: version != nil, isDIYHardware: false,
		hasWifi: false, hasEthernet: false, hasXeddsa: false,
		firmwareAtLeast: { required in
			guard let version else { return true }
			return required.compare(version, options: .numeric) != .orderedDescending
		},
		isFirmwareKnown: version != nil)
}

/// An environment for a radio the app has identified as `hwModel`, for the rows gated
/// on hardware neither the schema nor the radio describes.
@MainActor
private func environment(hwModel: Int32) -> ConfigFormEnvironment {
	let node = NodeInfoEntity()
	let user = UserEntity()
	user.hwModelId = hwModel
	node.user = user
	return ConfigFormEnvironment(
		node: node, isConnected: true, isConnectedNode: true, isDIYHardware: false,
		hasWifi: false, hasEthernet: false, hasXeddsa: false,
		firmwareAtLeast: { _ in true }, isFirmwareKnown: true)
}

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
			"meshtastic.ModuleConfig.AudioConfig": (0, 0),
			"meshtastic.ModuleConfig.DetectionSensorConfig": (1, 2),      // role picker folded onto the enable row; two sections by that role
			"meshtastic.Config.DeviceConfig": (1, 0),                   // role picker with its warning
			"meshtastic.Config.DisplayConfig": (0, 0),                  // no hatches: every row reads its own field
			"meshtastic.Config.PositionConfig": (1, 0),                 // fixed position confirms before it sends
			"meshtastic.Config.PowerConfig": (1, 3),                    // ADC override; power saving, Bluetooth wait and battery rows by architecture
			"meshtastic.ModuleConfig.AmbientLightingConfig": (1, 0),    // one colour picker for three channels
			"meshtastic.ModuleConfig.CannedMessageConfig": (0, 3),      // three sections locked while a preset is chosen
			"meshtastic.ModuleConfig.ExternalNotificationConfig": (0, 0),
			"meshtastic.Config.LoRaConfig": (4, 1),                    // region, preset, bandwidth and coding rate all constrain each other; the PA fan by hardware
			"meshtastic.ModuleConfig.MQTTConfig": (4, 2),               // proxy, consent, precision, root topic; TLS by firmware, consent kept on older firmware
			"meshtastic.Config.NetworkConfig": (0, 6),                  // every section turns on hardware the schema cannot see
			"meshtastic.ModuleConfig.NeighborInfoConfig": (0, 0),
			"meshtastic.ModuleConfig.PaxcounterConfig": (0, 0),
			"meshtastic.ModuleConfig.RangeTestConfig": (0, 1),          // save needs WiFi
			"meshtastic.Config.SecurityConfig": (4, 0),                 // every key row, and managed mode needing one
			"meshtastic.ModuleConfig.SerialConfig": (0, 0),
			"meshtastic.ModuleConfig.StoreForwardConfig": (0, 0),
			"meshtastic.ModuleConfig.TAKConfig": (0, 0),
			"meshtastic.ModuleConfig.TelemetryConfig": (0, 1),          // the interval stands alone where there is no toggle
			"meshtastic.ModuleConfig.TrafficManagementConfig": (0, 4)   // four feature sections behind the main switch
		]
		// Without this, moving a screen to `bespoke` would silently stop checking its
		// hatches: the loop below would just not visit it.
		#expect(Set(ConfigFormOverlays.all.map(\.protoName)) == Set(expected.keys),
				"the pinned table and the registered overlays have drifted apart")
		for overlay in ConfigFormOverlays.all {
			let pinned = try #require(expected[overlay.protoName], "\(overlay.protoName) has no pinned hatch counts")
			#expect(overlay.customControlCount == pinned.custom, "\(overlay.protoName) custom controls")
			#expect(overlay.environmentConditionCount == pinned.environment, "\(overlay.protoName) environment conditions")
		}
	}

	@Test("Display offers the compass orientation picker and not the toggle it replaced")
	func displayOffersCompassOrientation() throws {
		typealias F = Config.DisplayConfig.Fields
		let overlay = DisplayConfig.overlay()
		#expect(overlay.rowID(for: F.compassOrientation.identity) != nil,
				"the orientation picker should have a row on every supported firmware")
		#expect(overlay.rowID(for: F.compassNorthTop.identity) == nil,
				"the north-up toggle it replaced should not be rendered")
		#expect(overlay.omits(F.compassNorthTop.identity),
				"the north-up toggle should be listed as omitted, with its reason")
	}

	@Test("Position's flag toggles nest on the bit they depend on")
	func positionFlagsNest() throws {
		typealias F = Config.PositionConfig.Fields
		let overlay = PositionConfig.overlay()
		let row = try #require(overlay.sections.flatMap(\.fields).first { $0.id == "position_flags" })
		guard case .flags(let flags) = row.control else {
			Issue.record("position_flags should render as a bitfield"); return
		}
		#expect(flags.count == 10, "every bit the screen offers")
		#expect(flags.allSatisfy { $0.label() != nil }, "every flag takes its label from the schema")

        let env = testEnvironment(firmware: "2.8.0")
		var config = Config.PositionConfig()

		// The two altitude refinements and the HDOP/VDOP choice are meaningless on their
		// own, so they appear only once the bit they qualify is set.
		func shown(_ bit: PositionFlags) -> Bool {
			guard let flag = flags.first(where: { $0.rawValue == bit.rawValue }) else { return false }
			return flag.shownWhen?.evaluate(config, env) ?? true
		}
		#expect(!shown(.AltitudeMsl))
		#expect(!shown(.GeoidalSeparation))
		#expect(!shown(.Hvdop))
		#expect(shown(.Altitude), "the bits they depend on are always offered")
		#expect(shown(.Dop))

		config.positionFlags = UInt32(PositionFlags.Altitude.rawValue | PositionFlags.Dop.rawValue)
		#expect(shown(.AltitudeMsl))
		#expect(shown(.GeoidalSeparation))
		#expect(shown(.Hvdop))
	}

	@Test("Toggling one position flag leaves the others alone")
	func flagBitsRoundTrip() {
		// The bit arithmetic the flags rows bind to. Without this the suite would pass
		// with the renderer deleted, because the rest only reads overlay metadata.
		var word = 0
		word = ConfigFormFlagBits.setting(PositionFlags.Altitude.rawValue, to: true, in: word)
		word = ConfigFormFlagBits.setting(PositionFlags.Dop.rawValue, to: true, in: word)
		#expect(word == PositionFlags.Altitude.rawValue | PositionFlags.Dop.rawValue)
		#expect(ConfigFormFlagBits.isSet(PositionFlags.Altitude.rawValue, in: word))
		#expect(ConfigFormFlagBits.isSet(PositionFlags.Dop.rawValue, in: word))
		#expect(!ConfigFormFlagBits.isSet(PositionFlags.Speed.rawValue, in: word))

		// Clearing one bit must not disturb its neighbours.
		word = ConfigFormFlagBits.setting(PositionFlags.Altitude.rawValue, to: false, in: word)
		#expect(word == PositionFlags.Dop.rawValue)

		// Setting a bit that is already set is not a toggle.
		let twice = ConfigFormFlagBits.setting(PositionFlags.Dop.rawValue, to: true, in: word)
		#expect(twice == word)

		// The high bit the screen offers survives the round trip.
		var high = ConfigFormFlagBits.setting(PositionFlags.Heading.rawValue, to: true, in: 0)
		#expect(high == 512)
		high = ConfigFormFlagBits.setting(PositionFlags.Heading.rawValue, to: false, in: high)
		#expect(high == 0)
	}

	@Test("Conditions read the field they name")
	func conditionsEvaluate() throws {
		typealias F = ModuleConfig.NeighborInfoConfig.Fields
		var message = ModuleConfig.NeighborInfoConfig()
		let env = ConfigFormEnvironment(node: nil, isConnected: true, isConnectedNode: true, isDIYHardware: false,
										hasWifi: false, hasEthernet: false, hasXeddsa: false, firmwareAtLeast: { _ in true },
			isFirmwareKnown: false)
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

	@Test("A control is only a scroll target once the values say it is on screen")
	func focusNeedsTheLoadedValues() {
		let overlay = NeighborInfoConfig.overlay()
		let interval = ModuleConfig.NeighborInfoConfig.Fields.updateInterval.identity
		let env = ConfigFormEnvironment(
			node: nil, isConnected: true, isConnectedNode: true, isDIYHardware: false,
			hasWifi: false, hasEthernet: false, hasXeddsa: false, firmwareAtLeast: { _ in true },
			isFirmwareKnown: false)

		// The empty message a form holds before the radio's values arrive. Deciding here
		// is what made search open the screen and scroll nowhere.
		var config = ModuleConfig.NeighborInfoConfig()
		#expect(overlay.rowID(for: interval) != nil, "the screen does lay the interval out")
		#expect(overlay.visibleRowID(for: interval, in: config, env) == nil, "but not while the module reads as off")

		config.enabled = true
		#expect(overlay.visibleRowID(for: interval, in: config, env) != nil)

		// A control with no condition is a target either way.
		let enabled = ModuleConfig.NeighborInfoConfig.Fields.enabled.identity
		#expect(overlay.visibleRowID(for: enabled, in: ModuleConfig.NeighborInfoConfig(), env) != nil)
	}

	@Test("A search result lands on the control, or on the section that explains its absence")
	func focusRowFollowsTheValues() {
		let overlay = MQTTConfig.overlay()
		let password = ModuleConfig.MQTTConfig.Fields.password.identity
		let env = ConfigFormEnvironment(
			node: nil, isConnected: true, isConnectedNode: true, isDIYHardware: false,
			hasWifi: false, hasEthernet: false, hasXeddsa: false, firmwareAtLeast: { _ in true },
			isFirmwareKnown: false)

		// A private broker shows its credentials, so the control itself is the target.
		var config = ModuleConfig.MQTTConfig()
		config.address = "broker.example.org"
		#expect(overlay.focusRowID(for: password, in: config, env) == "password")

		// The public server hides them. Deciding this against an empty message - which
		// is what the form holds before the radio's values arrive - picks a row that is
		// about to be removed, and scrolling to a removed row does nothing at all.
		config.address = "mqtt.meshtastic.org"
		#expect(overlay.visibleRowID(for: password, in: config, env) == nil)
		#expect(overlay.focusRowID(for: password, in: config, env) == "address",
				"falls back to the first row of the section the control lives in")

		// A whole section that is hidden has nothing worth showing.
		let interval = ModuleConfig.NeighborInfoConfig.Fields.updateInterval.identity
		#expect(NeighborInfoConfig.overlay().focusRowID(for: interval, in: ModuleConfig.NeighborInfoConfig(), env) == nil)

		// And a screen must not answer for a field it does not lay out: both of these
		// screens have a Password, and each has to leave the other's alone.
		let wifiPassword = FieldIdentity(messageName: "meshtastic.Config.NetworkConfig", tag: 4)
		#expect(overlay.rowID(for: wifiPassword) == nil)
	}

	// MARK: - Firmware versions from the schema

	@Test("A focus request waits for a stored config, and survives one that never comes")
	func focusWaitsForStoredValues() {
		typealias Form = MetadataConfigForm<ModuleConfig.MQTTConfig, EmptyView, EmptyView>

		// Nothing stored: the empty message is what the screen is showing, so its rows
		// are the right ones to scroll to.
		#expect(Form.readiness(hasStoredConfig: false, loaded: false, waitedOut: false) == .resolveNow)
		#expect(Form.readiness(hasStoredConfig: false, loaded: false, waitedOut: true) == .resolveNow)

		// Stored and still arriving: wait, because which rows exist depends on it.
		#expect(Form.readiness(hasStoredConfig: true, loaded: false, waitedOut: false) == .waitForValues)
		#expect(Form.readiness(hasStoredConfig: true, loaded: true, waitedOut: false) == .resolveNow)

		// Stored but never arrived: leave the request for the next appearance rather
		// than resolving against defaults and scrolling to a row the values may remove.
		#expect(Form.readiness(hasStoredConfig: true, loaded: false, waitedOut: true) == .leaveForLater)
	}
}

/// The rows that turn on something outside the message: the board the radio runs on,
/// and the region it is set to.
@Suite("Configuration form hardware and region gates")
struct ConfigFormGateTests {

	@Test("LoRa offers the duty cycle override and the PA fan toggle")
	func loRaOffersDutyCycleOverride() throws {
		typealias F = Config.LoRaConfig.Fields
		let overlay = LoRaConfig.overlay(node: nil)
		#expect(overlay.rowID(for: F.overrideDutyCycle.identity) != nil)
		#expect(overlay.rowID(for: F.paFanDisabled.identity) != nil)
	}

	@Test("The duty cycle override is offered only where there is a duty cycle")
	func dutyCycleOverrideIsRegionGated() throws {
		typealias F = Config.LoRaConfig.Fields
		let overlay = LoRaConfig.overlay(node: nil)
		let row = try #require(overlay.sections.flatMap(\.fields)
			.first { $0.id == F.overrideDutyCycle.name })
		let condition = try #require(row.shownWhen, "the override should be region gated")
		let env = testEnvironment(firmware: "2.8.0")

		func shown(_ region: Config.LoRaConfig.RegionCode) -> Bool {
			var config = Config.LoRaConfig()
			config.region = region
			return condition.evaluate(config, env)
		}

		// Every region the app records an hourly limit for, derived rather than listed
		// so a change to RegionCodes.dutyCycle carries here.
		let restricted = RegionCodes.allCases.filter { $0.dutyCycle > 0 && $0.dutyCycle < 100 }
		#expect(!restricted.isEmpty, "the app should know of at least one restricted region")
		for code in restricted {
			let region = try #require(Config.LoRaConfig.RegionCode(rawValue: code.rawValue))
			#expect(shown(region), "\(code) has a \(code.dutyCycle)% duty cycle")
		}

		#expect(!shown(.us))
		#expect(!shown(.anz))
		#expect(!shown(.jp))
		// Unset has no limit to exceed either, so there is nothing to override yet.
		#expect(!shown(.unset))
	}

	@Test("The PA fan toggle is offered only on the boards that drive one")
	@MainActor func paFanIsHardwareGated() throws {
		typealias F = Config.LoRaConfig.Fields
		let overlay = LoRaConfig.overlay(node: nil)
		let row = try #require(overlay.sections.flatMap(\.fields)
			.first { $0.id == F.paFanDisabled.name })
		let condition = try #require(row.shownWhen, "the fan row should be hardware gated")
		let config = Config.LoRaConfig()

		// The four firmware variants that define RF95_FAN_EN.
		#expect(LoRaConfig.paFanHardware == [45, 64, 74, 122])

		for hwModel in LoRaConfig.paFanHardware {
			#expect(condition.evaluate(config, environment(hwModel: hwModel)),
					"hardware \(hwModel) drives a PA fan")
		}
		for hwModel: Int32 in [4, 43, 63, 123] {
			#expect(!condition.evaluate(config, environment(hwModel: hwModel)),
					"hardware \(hwModel) has no PA fan")
		}
		// Hardware the app has not identified hides the row rather than guessing.
		#expect(!condition.evaluate(config, testEnvironment(firmware: "2.8.0")))
	}

	@Test("The Bluetooth wait is offered on ESP32 boards only")
	func powerOffersBluetoothWaitOnESP32() throws {
		typealias F = Config.PowerConfig.Fields
		let env = testEnvironment(firmware: "2.8.0")
		let config = Config.PowerConfig()

		for architecture in [Architecture.esp32, .esp32S3, .esp32C3, .esp32C6] {
			let overlay = PowerConfig.overlay(architecture: architecture)
			let row = try #require(overlay.sections.flatMap(\.fields)
				.first { $0.id == F.waitBluetoothSecs.name })
			#expect(row.shownWhen?.evaluate(config, env) ?? true, "\(architecture) should show it")
			guard case .interval(let intervals) = row.control else {
				Issue.record("the Bluetooth wait should render as an interval picker"); return
			}
			#expect(intervals == .waitBluetooth)
		}

		for architecture in [Architecture.nrf52840, .rp2040] {
			let overlay = PowerConfig.overlay(architecture: architecture)
			let row = try #require(overlay.sections.flatMap(\.fields)
				.first { $0.id == F.waitBluetoothSecs.name })
			#expect(!(row.shownWhen?.evaluate(config, env) ?? true), "\(architecture) should hide it")
		}
	}

}

/// The schema's firmware window: which releases read a field, and what the form does
/// on either side of that.
@Suite("Configuration form firmware windows")
struct ConfigFormFirmwareWindowTests {

	@Test("A field is offered only on firmware that reads it")
	func firmwareWindowDecidesVisibility() {
		let since = FieldMetadata(sinceFirmware: "2.7.13")
		#expect(!testEnvironment(firmware: "2.7.12").firmwareReads(since))
		#expect(testEnvironment(firmware: "2.7.13").firmwareReads(since))
		#expect(testEnvironment(firmware: "2.8.0").firmwareReads(since))

		// Deprecation is the other end of the same window: the firmware below it still
		// reads the field, so that is where the control belongs.
		let until = FieldMetadata(deprecated: true, deprecatedSince: "2.7.1")
		#expect(testEnvironment(firmware: "2.7.0").firmwareReads(until))
		#expect(!testEnvironment(firmware: "2.7.1").firmwareReads(until))
		#expect(!testEnvironment(firmware: "2.8.0").firmwareReads(until))

		// Nothing is hidden on a guess: with no radio, neither attribute applies.
		#expect(testEnvironment(firmware: nil).firmwareReads(since))
		#expect(testEnvironment(firmware: nil).firmwareReads(until))
		// Nor when a connected radio has not reported a version, which reads as current.
		#expect(testEnvironment(firmware: "2.8.0").firmwareReads(nil))

		// The same rule over the real registry. Firmware force-writes canned_message.enabled
		// true from 2.7.4, so the version has to decide this and not the stored value.
		let cannedEnabled = FieldIdentity(messageName: "meshtastic.ModuleConfig.CannedMessageConfig", tag: 9).metadata
		#expect(cannedEnabled?.deprecatedSince == "2.7.0")
		#expect(testEnvironment(firmware: "2.6.9").firmwareReads(cannedEnabled))
		#expect(!testEnvironment(firmware: "2.7.4").firmwareReads(cannedEnabled))
	}

	@Test("An unknown firmware version hides nothing")
	func unknownFirmwareShowsEverything() throws {
		// A node the app has never heard metadata from, and the same node once it has.
		// Guessing wrong here takes a setting away from somebody who came to change it.
		let unknown = ConfigFormEnvironment(
			node: nil, isConnected: true, isConnectedNode: true, isDIYHardware: false,
			hasWifi: false, hasEthernet: false, hasXeddsa: false,
			firmwareAtLeast: { _ in false }, isFirmwareKnown: false)
		let clock = Config.DisplayConfig.Fields.use12HClock.metadata
		#expect(clock?.sinceFirmware == "2.5.22", "the schema still dates this field")
		#expect(unknown.firmwareReads(clock), "no known version means the window does not apply")

		let known = testEnvironment(firmware: "2.5.21")
		#expect(!known.firmwareReads(clock), "once the version is known, the window applies")
	}

	@Test("Public-server TLS waits for the firmware that accepts it")
	func mqttTlsFollowsTheServerRule() throws {
		// Up to 2.7.3 the radio rejects the whole MQTT config when TLS is on with the
		// default server, so locking the toggle on there would make the save fail.
		#expect(MQTTConfig.tlsRequiredFirmware == "2.7.4",
				"2.7.3 still refuses TLS to the default server")

		let overlay = MQTTConfig.overlay()
		let tls = try #require(overlay.sections.flatMap(\.fields).first { $0.id == "tls_enabled" })
		var config = ModuleConfig.MQTTConfig()
		config.address = MQTTConfig.publicServer

		#expect(!overlay.isVisible(tls, in: config, testEnvironment(firmware: "2.7.3")),
				"the public server refuses TLS on 2.7.3, so the row has nothing to offer")
		#expect(overlay.isVisible(tls, in: config, testEnvironment(firmware: "2.7.4")),
				"2.7.4 accepts it, so the row appears locked on")
	}

	@Test("The device telemetry toggle appears on the firmware that reads it, not one before")
	func telemetryToggleFollowsTheSchema() throws {
		let overlay = TelemetryConfig.overlay()
		let toggle = try #require(overlay.sections.flatMap(\.fields).first { $0.id == "device_telemetry_enabled" })
		let interval = try #require(overlay.sections.flatMap(\.fields).first { $0.id == "device_update_interval" })
		#expect(TelemetryConfig.deviceToggleFirmware == "2.7.13", "the schema says 2.7.13; 2.7.12 has no read of the field")

		// 2.7.12 shipped the toggle in the proto but nothing in the firmware reads it, so
		// the app used to draw a switch that did nothing. The interval alone stands there.
		var config = ModuleConfig.TelemetryConfig()
		let old = testEnvironment(firmware: "2.7.12")
		#expect(!overlay.isVisible(toggle, in: config, old))
		#expect(overlay.isVisible(interval, in: config, old), "with no toggle the interval is the only control")
		#expect(TelemetryConfig.isLegacy(isConnected: true, firmwareAtLeast: old.firmwareAtLeast))

		let current = testEnvironment(firmware: "2.7.13")
		#expect(overlay.isVisible(toggle, in: config, current))
		#expect(!overlay.isVisible(interval, in: config, current), "the interval waits on the toggle once there is one")
		config.deviceTelemetryEnabled = true
		#expect(overlay.isVisible(interval, in: config, current))
		#expect(!TelemetryConfig.isLegacy(isConnected: true, firmwareAtLeast: current.firmwareAtLeast))

		// Without a radio the screen is read, not guessed at: both controls are there.
		let offline = testEnvironment(firmware: nil)
		#expect(overlay.isVisible(toggle, in: ModuleConfig.TelemetryConfig(), offline))
		#expect(!TelemetryConfig.isLegacy(isConnected: false, firmwareAtLeast: { _ in false }))
	}

	@Test("A screen hides a control the connected firmware is too old for")
	func schemaHidesControlsOlderFirmwareIgnores() throws {
		// The 12-hour clock is read from 2.5.22; no overlay says so.
		let overlay = DisplayConfig.overlay()
		let clock = try #require(overlay.sections.flatMap(\.fields).first { $0.id == "use_12h_clock" })
		let config = Config.DisplayConfig()
		#expect(!overlay.isVisible(clock, in: config, testEnvironment(firmware: "2.5.21")))
		#expect(overlay.isVisible(clock, in: config, testEnvironment(firmware: "2.5.22")))
		#expect(overlay.isVisible(clock, in: config, testEnvironment(firmware: nil)))
	}

	@Test("A row that means something to the app stays on firmware without the field")
	func consentRowSurvivesOlderFirmware() throws {
		// map_report_settings.should_report_location is read from 2.6.8, but the toggle is
		// also the app's own consent record and the proxy honours it on every firmware.
		// Hiding it would take the privacy text and the interval and precision with it.
		let overlay = MQTTConfig.overlay()
		let consent = try #require(overlay.sections.flatMap(\.fields)
			.first { $0.id == "map_report_settings.should_report_location" })
		let interval = try #require(overlay.sections.flatMap(\.fields)
			.first { $0.id == "map_report_settings.publish_interval_secs" })
		#expect(consent.shownDespiteFirmware != nil, "kept on purpose, with the reason stated")

		var config = ModuleConfig.MQTTConfig()
		config.mapReportingEnabled = true
		let old = testEnvironment(firmware: "2.6.7")
		#expect(overlay.isVisible(consent, in: config, old))
		config.mapReportSettings.shouldReportLocation = true
		#expect(overlay.isVisible(interval, in: config, old))
	}

}
