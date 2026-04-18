import Foundation
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
		(-100, BLESignalStrength.weak),
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
		(TransportType.serial, "Serial"),
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
		NavigationState.Tab.settings,
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
		let view = CircleText(text: "AB", color: .blue)
		#expect(view.text == "AB")
		#expect(view.circleSize == 45)
	}

	@Test func customCircleSize() {
		let view = CircleText(text: "XY", color: .red, circleSize: 90)
		#expect(view.text == "XY")
		#expect(view.circleSize == 90)
	}

	@Test func emojiText() {
		let view = CircleText(text: "😝", color: .orange, circleSize: 80)
		#expect(view.text == "😝")
		#expect(view.circleSize == 80)
	}
}

// MARK: - BatteryCompact View Tests

@Suite("BatteryCompact")
struct BatteryCompactTests {

	@Test func creationWithLevel() {
		let view = BatteryCompact(batteryLevel: 75, font: .caption, iconFont: .callout, color: .accentColor)
		#expect(view.batteryLevel == 75)
	}

	@Test func creationWithNilLevel() {
		let view = BatteryCompact(batteryLevel: nil, font: .caption, iconFont: .callout, color: .accentColor)
		#expect(view.batteryLevel == nil)
	}

	@Test func pluggedInLevel() {
		let view = BatteryCompact(batteryLevel: 101, font: .caption, iconFont: .callout, color: .accentColor)
		#expect(view.batteryLevel! > 100)
	}

	@Test func chargingLevel() {
		let view = BatteryCompact(batteryLevel: 100, font: .caption, iconFont: .callout, color: .accentColor)
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
