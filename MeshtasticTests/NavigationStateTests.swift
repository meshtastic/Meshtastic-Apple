import Foundation
import Testing

@testable import Meshtastic

// MARK: - NavigationState

@Suite("NavigationState Detailed")
struct NavigationStateDetailedTests {

	@Test func defaultTab_isConnect() {
		let state = NavigationState()
		#expect(state.selectedTab == .connect)
	}

	@Test func tab_rawValues() {
		#expect(NavigationState.Tab.messages.rawValue == "messages")
		#expect(NavigationState.Tab.connect.rawValue == "connect")
		#expect(NavigationState.Tab.nodes.rawValue == "nodes")
		#expect(NavigationState.Tab.map.rawValue == "map")
		#expect(NavigationState.Tab.settings.rawValue == "settings")
	}

	@Test func tab_hashable() {
		let set: Set<NavigationState.Tab> = [.messages, .connect, .nodes, .map, .settings]
		#expect(set.count == 5)
	}

	@Test func initWithValues() {
		let state = NavigationState(
			selectedTab: .messages,
			messages: .channels(channelId: 1),
			nodeListSelectedNodeNum: 42,
			map: .selectedNode(100),
			settings: .about
		)
		#expect(state.selectedTab == .messages)
		#expect(state.messages == .channels(channelId: 1))
		#expect(state.nodeListSelectedNodeNum == 42)
		#expect(state.map == .selectedNode(100))
		#expect(state.settings == .about)
	}

	@Test func hashable() {
		let state1 = NavigationState(selectedTab: .connect)
		let state2 = NavigationState(selectedTab: .connect)
		#expect(state1 == state2)
	}

	@Test func notEqual_differentTab() {
		let state1 = NavigationState(selectedTab: .connect)
		let state2 = NavigationState(selectedTab: .messages)
		#expect(state1 != state2)
	}
}

// MARK: - MessagesNavigationState

@Suite("MessagesNavigationState")
struct MessagesNavigationStateTests {

	@Test func channels_equality() {
		let a = MessagesNavigationState.channels(channelId: 1, messageId: 10)
		let b = MessagesNavigationState.channels(channelId: 1, messageId: 10)
		#expect(a == b)
	}

	@Test func channels_inequality() {
		let a = MessagesNavigationState.channels(channelId: 1)
		let b = MessagesNavigationState.channels(channelId: 2)
		#expect(a != b)
	}

	@Test func directMessages_equality() {
		let a = MessagesNavigationState.directMessages(userNum: 42)
		let b = MessagesNavigationState.directMessages(userNum: 42)
		#expect(a == b)
	}

	@Test func directMessages_withMessageId() {
		let a = MessagesNavigationState.directMessages(userNum: 42, messageId: 100)
		let b = MessagesNavigationState.directMessages(userNum: 42, messageId: 200)
		#expect(a != b)
	}

	@Test func channels_vs_directMessages_notEqual() {
		let a = MessagesNavigationState.channels(channelId: 1)
		let b = MessagesNavigationState.directMessages(userNum: 1)
		#expect(a != b)
	}

	@Test func hashable() {
		let a = MessagesNavigationState.channels(channelId: 1)
		let b = MessagesNavigationState.channels(channelId: 1)
		#expect(a.hashValue == b.hashValue)
	}
}

// MARK: - MapNavigationState

@Suite("MapNavigationState")
struct MapNavigationStateTests {

	@Test func selectedNode_equality() {
		#expect(MapNavigationState.selectedNode(42) == .selectedNode(42))
	}

	@Test func selectedNode_inequality() {
		#expect(MapNavigationState.selectedNode(1) != .selectedNode(2))
	}

	@Test func waypoint_equality() {
		#expect(MapNavigationState.waypoint(5) == .waypoint(5))
	}

	@Test func selectedNode_vs_waypoint() {
		#expect(MapNavigationState.selectedNode(1) != .waypoint(1))
	}

	@Test func hashable() {
		let set: Set<MapNavigationState> = [.selectedNode(1), .waypoint(1), .selectedNode(2)]
		#expect(set.count == 3)
	}
}

// MARK: - SettingsNavigationState

@Suite("SettingsNavigationState")
struct SettingsNavigationStateTests {

	@Test func allRawValues() {
		let allCases: [(SettingsNavigationState, String)] = [
			(.about, "about"),
			(.appSettings, "appSettings"),
			(.routes, "routes"),
			(.routeRecorder, "routeRecorder"),
			(.lora, "lora"),
			(.channels, "channels"),
			(.shareQRCode, "shareQRCode"),
			(.user, "user"),
			(.bluetooth, "bluetooth"),
			(.device, "device"),
			(.display, "display"),
			(.network, "network"),
			(.position, "position"),
			(.power, "power"),
			(.ambientLighting, "ambientLighting"),
			(.cannedMessages, "cannedMessages"),
			(.detectionSensor, "detectionSensor"),
			(.externalNotification, "externalNotification"),
			(.mqtt, "mqtt"),
			(.rangeTest, "rangeTest"),
			(.paxCounter, "paxCounter"),
			(.ringtone, "ringtone"),
			(.serial, "serial"),
			(.security, "security"),
			(.storeAndForward, "storeAndForward"),
			(.telemetry, "telemetry"),
			(.debugLogs, "debugLogs"),
			(.appFiles, "appFiles"),
			(.firmwareUpdates, "firmwareUpdates"),
			(.tak, "tak"),
			(.takConfig, "takConfig"),
			(.tools, "tools"),
		]
		for (state, rawValue) in allCases {
			#expect(state.rawValue == rawValue)
		}
	}

	@Test func initFromRawValue() {
		#expect(SettingsNavigationState(rawValue: "about") == .about)
		#expect(SettingsNavigationState(rawValue: "mqtt") == .mqtt)
		#expect(SettingsNavigationState(rawValue: "invalid") == nil)
	}

	@Test func equality() {
		#expect(SettingsNavigationState.about == .about)
		#expect(SettingsNavigationState.about != .lora)
	}
}
