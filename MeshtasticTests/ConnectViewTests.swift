import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Meshtastic

// MARK: - Device Tests

@Suite("Device")
struct DeviceTests {

	static let testUUID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

	@Test func creation() {
		let device = Device(
			id: DeviceTests.testUUID,
			name: "Test Radio",
			transportType: .ble,
			identifier: "BLE-001"
		)
		#expect(device.id == DeviceTests.testUUID)
		#expect(device.name == "Test Radio")
		#expect(device.transportType == .ble)
		#expect(device.identifier == "BLE-001")
		#expect(device.connectionState == .disconnected)
		#expect(device.rssi == nil)
		#expect(device.num == nil)
		#expect(device.wasRestored == false)
		#expect(device.isManualConnection == false)
	}

	@Test func creationWithAllProperties() {
		let device = Device(
			id: DeviceTests.testUUID,
			name: "Full Radio",
			transportType: .tcp,
			identifier: "192.168.1.1:4403",
			connectionState: .connected,
			rssi: -60,
			num: 123456,
			wasRestored: true,
			isManualConnection: true
		)
		#expect(device.connectionState == .connected)
		#expect(device.rssi == -60)
		#expect(device.num == 123456)
		#expect(device.wasRestored == true)
		#expect(device.isManualConnection == true)
	}

	@Test(arguments: [
		(-50, BLESignalStrength.strong),
		(-64, BLESignalStrength.strong),
		(-65, BLESignalStrength.normal),
		(-80, BLESignalStrength.normal),
		(-84, BLESignalStrength.normal),
		(-85, BLESignalStrength.weak),
		(-100, BLESignalStrength.weak)
	])
	func signalStrength(rssi: Int, expected: BLESignalStrength) {
		let device = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001",
			rssi: rssi
		)
		#expect(device.getSignalStrength() == expected)
	}

	@Test func signalStrengthNilWhenNoRSSI() {
		let device = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001"
		)
		#expect(device.getSignalStrength() == nil)
	}

	@Test func rssiStringWithValue() {
		var device = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001",
			rssi: -72
		)
		#expect(device.rssiString == "-72 dBm")

		device.rssi = -100
		#expect(device.rssiString == "-100 dBm")
	}

	@Test func rssiStringWithoutValue() {
		let device = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001"
		)
		#expect(device.rssiString == "n/a")
	}

	@Test func descriptionWithBothNames() {
		var device = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001"
		)
		device.shortName = "TST"
		device.longName = "Test Node"
		#expect(device.description == "Test Node (TST)")
	}

	@Test func descriptionWithShortNameOnly() {
		var device = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001"
		)
		device.shortName = "TST"
		#expect(device.description == "TST")
	}

	@Test func descriptionWithLongNameOnly() {
		var device = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001"
		)
		device.longName = "Test Node"
		#expect(device.description == "Test Node")
	}

	@Test func descriptionWithNoNames() {
		let device = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001"
		)
		#expect(device.description == "Device(id: \(DeviceTests.testUUID))")
	}

	@Test func hashEquality() {
		let device1 = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001"
		)
		let device2 = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001"
		)
		#expect(device1 == device2)
		#expect(device1.hashValue == device2.hashValue)
	}

	@Test func codableRoundTrip() throws {
		var device = Device(
			id: DeviceTests.testUUID,
			name: "Radio",
			transportType: .ble,
			identifier: "BLE-001",
			connectionState: .connected,
			rssi: -70,
			num: 99
		)
		device.shortName = "RDO"
		device.longName = "My Radio"
		device.firmwareVersion = "2.5.0"

		let data = try JSONEncoder().encode(device)
		let decoded = try JSONDecoder().decode(Device.self, from: data)

		#expect(decoded.id == device.id)
		#expect(decoded.name == device.name)
		#expect(decoded.transportType == device.transportType)
		#expect(decoded.identifier == device.identifier)
		#expect(decoded.connectionState == device.connectionState)
		#expect(decoded.rssi == device.rssi)
		#expect(decoded.num == device.num)
		#expect(decoded.shortName == device.shortName)
		#expect(decoded.longName == device.longName)
		#expect(decoded.firmwareVersion == device.firmwareVersion)
	}
}

// MARK: - TransportType Tests

@Suite("TransportType")
struct TransportTypeTests {

	@Test func allCases() {
		let cases = TransportType.allCases
		#expect(cases.count == 3)
		#expect(cases.contains(.ble))
		#expect(cases.contains(.tcp))
		#expect(cases.contains(.serial))
	}

	@Test(arguments: [
		(TransportType.ble, "BLE"),
		(TransportType.tcp, "TCP"),
		(TransportType.serial, "Serial")
	])
	func rawValues(type: TransportType, expected: String) {
		#expect(type.rawValue == expected)
	}

	@Test func initFromRawValue() {
		#expect(TransportType(rawValue: "BLE") == .ble)
		#expect(TransportType(rawValue: "TCP") == .tcp)
		#expect(TransportType(rawValue: "Serial") == .serial)
		#expect(TransportType(rawValue: "invalid") == nil)
	}

	@Test func codableRoundTrip() throws {
		for type in TransportType.allCases {
			let data = try JSONEncoder().encode(type)
			let decoded = try JSONDecoder().decode(TransportType.self, from: data)
			#expect(decoded == type)
		}
	}
}

// MARK: - ConnectionState Tests

@Suite("ConnectionState")
struct ConnectionStateTests {

	@Test func equality() {
		#expect(ConnectionState.disconnected == .disconnected)
		#expect(ConnectionState.connecting == .connecting)
		#expect(ConnectionState.connected == .connected)
		#expect(ConnectionState.disconnected != .connected)
		#expect(ConnectionState.connecting != .disconnected)
	}

	@Test func codableRoundTrip() throws {
		let states: [ConnectionState] = [.disconnected, .connecting, .connected]
		for state in states {
			let data = try JSONEncoder().encode(state)
			let decoded = try JSONDecoder().decode(ConnectionState.self, from: data)
			#expect(decoded == state)
		}
	}
}

// MARK: - BLESignalStrength Tests

@Suite("BLESignalStrength")
struct BLESignalStrengthTests {

	@Test func rawValues() {
		#expect(BLESignalStrength.weak.rawValue == 0)
		#expect(BLESignalStrength.normal.rawValue == 1)
		#expect(BLESignalStrength.strong.rawValue == 2)
	}

	@Test func initFromRawValue() {
		#expect(BLESignalStrength(rawValue: 0) == .weak)
		#expect(BLESignalStrength(rawValue: 1) == .normal)
		#expect(BLESignalStrength(rawValue: 2) == .strong)
		#expect(BLESignalStrength(rawValue: 3) == nil)
	}
}

// MARK: - TransportStatus Tests

@Suite("TransportStatus")
struct TransportStatusTests {

	@Test func equality() {
		#expect(TransportStatus.uninitialized == .uninitialized)
		#expect(TransportStatus.ready == .ready)
		#expect(TransportStatus.discovering == .discovering)
		#expect(TransportStatus.error("test") == .error("test"))
		#expect(TransportStatus.error("a") != .error("b"))
		#expect(TransportStatus.ready != .discovering)
	}
}

// MARK: - NavigationState Tests

@Suite("NavigationState")
struct NavigationStateTests {

	@Test func defaultState() {
		let state = NavigationState()
		#expect(state.selectedTab == .connect)
		#expect(state.messages == nil)
		#expect(state.nodeListSelectedNodeNum == nil)
		#expect(state.map == nil)
		#expect(state.settings == nil)
	}

	@Test(arguments: [
		NavigationState.Tab.messages,
		NavigationState.Tab.connect,
		NavigationState.Tab.nodes,
		NavigationState.Tab.map,
		NavigationState.Tab.settings
	])
	func tabRawValues(tab: NavigationState.Tab) {
		#expect(NavigationState.Tab(rawValue: tab.rawValue) == tab)
	}

	@Test func messagesNavigationState() {
		let channels = MessagesNavigationState.channels(channelId: 1, messageId: 100)
		let directMessages = MessagesNavigationState.directMessages(userNum: 42, messageId: 200)

		let state1 = NavigationState(selectedTab: .messages, messages: channels)
		let state2 = NavigationState(selectedTab: .messages, messages: directMessages)

		#expect(state1 != state2)
		#expect(state1.messages != nil)
		#expect(state2.messages != nil)
	}

	@Test func mapNavigationState() {
		let selectedNode = MapNavigationState.selectedNode(12345)
		let waypoint = MapNavigationState.waypoint(67890)

		#expect(selectedNode != waypoint)
		#expect(MapNavigationState.selectedNode(12345) == selectedNode)
	}

	@Test func settingsNavigationState() {
		#expect(SettingsNavigationState(rawValue: "about") == .about)
		#expect(SettingsNavigationState(rawValue: "appSettings") == .appSettings)
		#expect(SettingsNavigationState(rawValue: "lora") == .lora)
		#expect(SettingsNavigationState(rawValue: "mqtt") == .mqtt)
		#expect(SettingsNavigationState(rawValue: "nonexistent") == nil)
	}

	@Test func hashable() {
		let state1 = NavigationState(selectedTab: .connect)
		let state2 = NavigationState(selectedTab: .connect)
		let state3 = NavigationState(selectedTab: .messages)

		#expect(state1 == state2)
		#expect(state1 != state3)
		#expect(state1.hashValue == state2.hashValue)
	}
}

// MARK: - Connect View Tests

/// Issue #2006 gates the connection screen's "Power Off" action behind a
/// `confirmationDialog` so a node can't be shut down by an accidental tap. The dialog
/// presentation itself (a `@State` flag + a system overlay) has no unit-test seam here —
/// there's no ViewInspector, `AccessoryManager` is a concrete type, and confirmation
/// dialogs don't render into snapshots — so that part is covered by manual/UI verification.
///
/// The safety-critical logic *is* unit-tested below: `Connect.shutdownTarget(for:)` resolves
/// the user a shutdown is sent to and must return nil for a detached/faulted node, otherwise
/// `sendShutdown` would read attributes on a faulted `@Model` and trap (the #2006 crash class).
@Suite("Connect view")
@MainActor
struct ConnectViewCreationTests {

	/// A fresh context over the shared container isolates this test's pending inserts from
	/// other suites; nothing is saved, so nothing leaks.
	private func freshContext() -> ModelContext {
		ModelContext(sharedModelContainer)
	}

	// MARK: Constructibility smoke tests

	@Test func constructsWithoutNode() async {
		let view = Connect(router: Router())
		#expect(view.node == nil)
	}

	@Test func threadsProvidedNodeThrough() async {
		let node = NodeInfoEntity()
		node.num = 42

		let view = Connect(router: Router(), node: node)
		#expect(view.node?.num == 42)
	}

	// MARK: shutdownTarget(for:expectedNum:) — resolution + faulted-node + drift guards

	@Test func shutdownTarget_nilNode_returnsNil() {
		#expect(Connect.shutdownTarget(for: nil, expectedNum: 0x5060_7080) == nil)
	}

	@Test func shutdownTarget_detachedNode_returnsNil() {
		// A node never inserted into a context has `modelContext == nil`, the same state a
		// cached node lands in after a context recreation. Resolving must skip it, not crash.
		let node = NodeInfoEntity()
		node.num = 0xDEAD_BEEF
		node.user = UserEntity()

		#expect(Connect.shutdownTarget(for: node, expectedNum: node.num) == nil)
	}

	@Test func shutdownTarget_liveNodeWithUser_returnsUser() {
		let context = freshContext()
		let node = NodeInfoEntity()
		node.num = 0x5060_7080
		let user = UserEntity()
		user.num = 0x5060_7099  // distinct sentinel so we know we got node.user back
		node.user = user
		context.insert(node)

		// withExtendedLifetime keeps `context` alive past the assertion: if ARC released it,
		// the inserted node's modelContext would go nil and falsely fail the live path. Compare
		// by `num`, not `===` — SwiftData isn't contractually required to hand back the same
		// instance for a to-one relationship after insert.
		withExtendedLifetime(context) {
			#expect(Connect.shutdownTarget(for: node, expectedNum: 0x5060_7080)?.num == 0x5060_7099)
		}
	}

	@Test func shutdownTarget_liveNodeWithoutUser_returnsNil() {
		let context = freshContext()
		let node = NodeInfoEntity()
		node.num = 0x1112_1314
		context.insert(node)

		withExtendedLifetime(context) {
			#expect(Connect.shutdownTarget(for: node, expectedNum: node.num) == nil)
		}
	}

	@Test func shutdownTarget_nilExpectedNum_returnsNil() {
		// No captured identity (menu never recorded one) must skip the shutdown rather than
		// fall through to whatever node is currently connected.
		let context = freshContext()
		let node = NodeInfoEntity()
		node.num = 0x2122_2324
		node.user = UserEntity()
		context.insert(node)

		withExtendedLifetime(context) {
			#expect(Connect.shutdownTarget(for: node, expectedNum: nil) == nil)
		}
	}

	@Test func shutdownTarget_mismatchedNum_returnsNil() {
		// The connection drifted to a different node while the dialog was up: the live node no
		// longer matches the identity captured at the long-press, so the shutdown is skipped.
		let context = freshContext()
		let node = NodeInfoEntity()
		node.num = 0x3132_3334
		node.user = UserEntity()
		context.insert(node)

		withExtendedLifetime(context) {
			#expect(Connect.shutdownTarget(for: node, expectedNum: 0x4142_4344) == nil)
		}
	}

	// MARK: liveNode(_:) — the modelContext guard the whole view relies on

	@Test func liveNode_nilAndDetached_returnNil() {
		#expect(Connect.liveNode(nil) == nil)

		let detached = NodeInfoEntity()
		detached.num = 0x2122_2324
		#expect(Connect.liveNode(detached) == nil)
	}

	@Test func liveNode_inserted_returnsNode() {
		let context = freshContext()
		let node = NodeInfoEntity()
		node.num = 0x3132_3334
		context.insert(node)

		withExtendedLifetime(context) {
			#expect(Connect.liveNode(node) === node)
		}
	}

	@Test func liveNode_insertedThenDeleted_returnsNil() throws {
		// The real #2006/#1944 path: a node that was live and then detached. Deleting it is the
		// closest reproducible analogue in a unit test to the context recreation that happens on
		// a node switch / disconnect-reconnect. The guard must skip the detached node so a later
		// `.user` read never traps on a faulted @Model.
		let context = freshContext()
		let node = NodeInfoEntity()
		node.num = 0x4142_4344
		context.insert(node)
		try context.save()
		withExtendedLifetime(context) {
			#expect(Connect.liveNode(node) === node)  // live while inserted
		}

		context.delete(node)
		try context.save()
		withExtendedLifetime(context) {
			#expect(Connect.liveNode(node) == nil)  // detached after delete → guard skips it
		}
	}
}

// MARK: - InvalidVersion View Tests

@Suite("InvalidVersion")
struct InvalidVersionTests {

	@Test func viewCreation() {
		let view = InvalidVersion(minimumVersion: "2.5.0", version: "2.3.0")
		#expect(view.minimumVersion == "2.5.0")
		#expect(view.version == "2.3.0")
	}

	@Test func viewCreationWithEmptyVersions() {
		let view = InvalidVersion(minimumVersion: "", version: "")
		#expect(view.minimumVersion == "")
		#expect(view.version == "")
	}
}

// MARK: - ConnectedDevice View Tests

@Suite("ConnectedDevice")
struct ConnectedDeviceTests {

	@Test func connectedState() {
		let view = ConnectedDevice(deviceConnected: true, name: "TEST")
		#expect(view.deviceConnected == true)
		#expect(view.name == "TEST")
		#expect(view.mqttProxyConnected == false)
		#expect(view.showActivityLights == true)
	}

	@Test func disconnectedState() {
		let view = ConnectedDevice(deviceConnected: false, name: "?")
		#expect(view.deviceConnected == false)
		#expect(view.name == "?")
	}

	@Test func withMQTTOptions() {
		let view = ConnectedDevice(
			deviceConnected: true,
			name: "MQTT",
			mqttProxyConnected: true,
			mqttUplinkEnabled: true,
			mqttDownlinkEnabled: true,
			mqttTopic: "msh/US/2/e/#"
		)
		#expect(view.mqttProxyConnected == true)
		#expect(view.mqttUplinkEnabled == true)
		#expect(view.mqttDownlinkEnabled == true)
		#expect(view.mqttTopic == "msh/US/2/e/#")
	}

	@Test func phoneOnlyMode() {
		let view = ConnectedDevice(
			deviceConnected: true,
			name: "PHON",
			phoneOnly: true,
			showActivityLights: false
		)
		#expect(view.phoneOnly == true)
		#expect(view.showActivityLights == false)
	}
}

// MARK: - CircleText View Tests

@Suite("CircleText")
struct CircleTextTests {

	@Test func defaultCircleSize() {
		let view = CircleText(text: "AB", color: Color(uiColor: .systemBlue))
		#expect(view.text == "AB")
		#expect(view.circleSize == 45)
	}

	@Test func customCircleSize() {
		let view = CircleText(text: "XY", color: Color(uiColor: .systemRed), circleSize: 90)
		#expect(view.text == "XY")
		#expect(view.circleSize == 90)
	}

	@Test func emojiText() {
		let view = CircleText(text: "😝", color: Color(uiColor: .systemOrange), circleSize: 80)
		#expect(view.text == "😝")
		#expect(view.circleSize == 80)
	}
}

// MARK: - BatteryCompact View Tests

@Suite("BatteryCompact")
struct BatteryCompactTests {

	@Test func creationWithLevel() {
		let view = BatteryCompact(batteryLevel: 75, font: .caption, iconFont: .callout, color: Color(hex: "6CB28E"))
		#expect(view.batteryLevel == 75)
	}

	@Test func creationWithNilLevel() {
		let view = BatteryCompact(batteryLevel: nil, font: .caption, iconFont: .callout, color: Color(hex: "6CB28E"))
		#expect(view.batteryLevel == nil)
	}

	@Test func pluggedInLevel() {
		let view = BatteryCompact(batteryLevel: 101, font: .caption, iconFont: .callout, color: Color(hex: "6CB28E"))
		#expect(view.batteryLevel! > 100)
	}

	@Test func chargingLevel() {
		let view = BatteryCompact(batteryLevel: 100, font: .caption, iconFont: .callout, color: Color(hex: "6CB28E"))
		#expect(view.batteryLevel == 100)
	}
}

// MARK: - SignalStrengthIndicator View Tests

@Suite("SignalStrengthIndicator")
struct SignalStrengthIndicatorTests {

	@Test func defaultDimensions() {
		let view = SignalStrengthIndicator(signalStrength: .strong)
		#expect(view.signalStrength == .strong)
		#expect(view.width == 8)
		#expect(view.height == 40)
	}

	@Test func customDimensions() {
		let view = SignalStrengthIndicator(signalStrength: .weak, width: 5, height: 20)
		#expect(view.signalStrength == .weak)
		#expect(view.width == 5)
		#expect(view.height == 20)
	}

	@Test(arguments: [BLESignalStrength.weak, .normal, .strong])
	func allStrengthLevels(strength: BLESignalStrength) {
		let view = SignalStrengthIndicator(signalStrength: strength)
		#expect(view.signalStrength == strength)
	}
}
