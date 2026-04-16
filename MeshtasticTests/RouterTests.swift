import Foundation
import Testing

@testable import Meshtastic

@Suite("Router")
struct RouterTests {

	// MARK: - Initialization

	@Test func defaultInitialState() async {
		let router = await Router()
		let state = await router.navigationState
		#expect(state.selectedTab == .connect)
		#expect(state.messages == nil)
		#expect(state.nodeListSelectedNodeNum == nil)
		#expect(state.map == nil)
		#expect(state.settings == nil)
	}

	@Test func customInitialState() async {
		let custom = NavigationState(selectedTab: .map, map: .waypoint(42))
		let router = await Router(navigationState: custom)
		let state = await router.navigationState
		#expect(state == custom)
	}

	// MARK: - Invalid URL Handling

	@Test func invalidSchemeIsIgnored() async throws {
		let router = await Router()
		let url = try #require(URL(string: "https:///messages"))
		await router.route(url: url)
		let tab = await router.navigationState.selectedTab
		#expect(tab == .connect)
	}

	@Test func unknownPathIsIgnored() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///unknown"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state == NavigationState(selectedTab: .connect))
	}

	// MARK: - Connect

	@Test func routeConnect() async throws {
		try await assertRoute(
			"meshtastic:///connect",
			NavigationState(selectedTab: .connect)
		)
	}

	// MARK: - Messages

	@Test func routeMessages() async throws {
		try await assertRoute(
			"meshtastic:///messages",
			NavigationState(selectedTab: .messages)
		)
	}

	@Test func routeMessagesWithChannelIdAndMessageId() async throws {
		try await assertRoute(
			"meshtastic:///messages?channelId=0&messageId=1122334455",
			NavigationState(
				selectedTab: .messages,
				messages: .channels(channelId: 0, messageId: 1122334455)
			)
		)
	}

	@Test func routeMessagesWithChannelIdOnly() async throws {
		try await assertRoute(
			"meshtastic:///messages?channelId=5",
			NavigationState(
				selectedTab: .messages,
				messages: .channels(channelId: 5, messageId: nil)
			)
		)
	}

	@Test func routeMessagesWithUserNumAndMessageId() async throws {
		try await assertRoute(
			"meshtastic:///messages?userNum=123456789&messageId=9876543210",
			NavigationState(
				selectedTab: .messages,
				messages: .directMessages(userNum: 123456789, messageId: 9876543210)
			)
		)
	}

	@Test func routeMessagesWithUserNumOnly() async throws {
		try await assertRoute(
			"meshtastic:///messages?userNum=42",
			NavigationState(
				selectedTab: .messages,
				messages: .directMessages(userNum: 42, messageId: nil)
			)
		)
	}

	@Test func routeMessagesWithOnlyMessageIdIgnoresIt() async throws {
		try await assertRoute(
			"meshtastic:///messages?messageId=999",
			NavigationState(selectedTab: .messages)
		)
	}

	@Test func routeMessagesWithNonNumericParamsIgnoresThem() async throws {
		try await assertRoute(
			"meshtastic:///messages?channelId=abc&messageId=xyz",
			NavigationState(selectedTab: .messages)
		)
	}

	// MARK: - Nodes

	@Test func routeNodes() async throws {
		try await assertRoute(
			"meshtastic:///nodes",
			NavigationState(selectedTab: .nodes)
		)
	}

	@Test func routeNodesWithNodeNum() async throws {
		try await assertRoute(
			"meshtastic:///nodes?nodenum=1234567890",
			NavigationState(selectedTab: .nodes, nodeListSelectedNodeNum: 1234567890)
		)
	}

	@Test func routeNodesWithNonNumericNodeNum() async throws {
		try await assertRoute(
			"meshtastic:///nodes?nodenum=abc",
			NavigationState(selectedTab: .nodes)
		)
	}

	// MARK: - Map

	@Test func routeMap() async throws {
		try await assertRoute(
			"meshtastic:///map",
			NavigationState(selectedTab: .map)
		)
	}

	@Test func routeMapWithWaypointId() async throws {
		try await assertRoute(
			"meshtastic:///map?waypointId=123456",
			NavigationState(selectedTab: .map, map: .waypoint(123456))
		)
	}

	@Test func routeMapWithNodeNum() async throws {
		try await assertRoute(
			"meshtastic:///map?nodenum=1234567890",
			NavigationState(selectedTab: .map, map: .selectedNode(1234567890))
		)
	}

	@Test func routeMapWithBothNodeNumAndWaypointIdPrefersNode() async throws {
		try await assertRoute(
			"meshtastic:///map?nodenum=111&waypointId=222",
			NavigationState(selectedTab: .map, map: .selectedNode(111))
		)
	}

	@Test func routeMapWithNonNumericParamsIgnoresThem() async throws {
		try await assertRoute(
			"meshtastic:///map?nodenum=abc&waypointId=xyz",
			NavigationState(selectedTab: .map)
		)
	}

	// MARK: - Settings

	@Test func routeSettings() async throws {
		try await assertRoute(
			"meshtastic:///settings",
			NavigationState(selectedTab: .settings)
		)
	}

	@Test(arguments: [
		("about", SettingsNavigationState.about),
		("appSettings", SettingsNavigationState.appSettings),
		("routes", SettingsNavigationState.routes),
		("routeRecorder", SettingsNavigationState.routeRecorder),
		("lora", SettingsNavigationState.lora),
		("channels", SettingsNavigationState.channels),
		("shareQRCode", SettingsNavigationState.shareQRCode),
		("user", SettingsNavigationState.user),
		("bluetooth", SettingsNavigationState.bluetooth),
		("device", SettingsNavigationState.device),
		("display", SettingsNavigationState.display),
		("network", SettingsNavigationState.network),
		("position", SettingsNavigationState.position),
		("power", SettingsNavigationState.power),
		("ambientLighting", SettingsNavigationState.ambientLighting),
		("cannedMessages", SettingsNavigationState.cannedMessages),
		("detectionSensor", SettingsNavigationState.detectionSensor),
		("externalNotification", SettingsNavigationState.externalNotification),
		("mqtt", SettingsNavigationState.mqtt),
		("rangeTest", SettingsNavigationState.rangeTest),
		("paxCounter", SettingsNavigationState.paxCounter),
		("ringtone", SettingsNavigationState.ringtone),
		("serial", SettingsNavigationState.serial),
		("security", SettingsNavigationState.security),
		("storeAndForward", SettingsNavigationState.storeAndForward),
		("telemetry", SettingsNavigationState.telemetry),
		("debugLogs", SettingsNavigationState.debugLogs),
		("appFiles", SettingsNavigationState.appFiles),
		("firmwareUpdates", SettingsNavigationState.firmwareUpdates),
		("tak", SettingsNavigationState.tak)
	])
	func routeSettingsPage(path: String, expected: SettingsNavigationState) async throws {
		try await assertRoute(
			"meshtastic:///settings/\(path)",
			NavigationState(selectedTab: .settings, settings: expected)
		)
	}

	@Test func routeSettingsInvalidSetting() async throws {
		try await assertRoute(
			"meshtastic:///settings/invalidSetting",
			NavigationState(selectedTab: .settings)
		)
	}

	// MARK: - navigateToNodeDetail

	@Test func navigateToNodeDetail() async {
		let router = await Router()
		await router.navigateToNodeDetail(nodeNum: 9876543210)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == 9876543210)
	}

	// MARK: - State Transitions

	@Test func routingToNewTabClearsPreviousState() async throws {
		let router = await Router()

		// First, route to messages with channel state
		let messagesURL = try #require(URL(string: "meshtastic:///messages?channelId=1&messageId=100"))
		await router.route(url: messagesURL)
		let messagesState = await router.navigationState
		#expect(messagesState.selectedTab == .messages)
		#expect(messagesState.messages != nil)

		// Then route to map — messages state should remain but tab changes
		let mapURL = try #require(URL(string: "meshtastic:///map?waypointId=42"))
		await router.route(url: mapURL)
		let mapState = await router.navigationState
		#expect(mapState.selectedTab == .map)
		#expect(mapState.map == .waypoint(42))
	}

	@Test func consecutiveRoutesUpdateState() async throws {
		let router = await Router()

		let nodesURL = try #require(URL(string: "meshtastic:///nodes?nodenum=111"))
		await router.route(url: nodesURL)
		let first = await router.navigationState
		#expect(first.selectedTab == .nodes)
		#expect(first.nodeListSelectedNodeNum == 111)

		let nodesURL2 = try #require(URL(string: "meshtastic:///nodes?nodenum=222"))
		await router.route(url: nodesURL2)
		let second = await router.navigationState
		#expect(second.selectedTab == .nodes)
		#expect(second.nodeListSelectedNodeNum == 222)
	}

	@Test func invalidSchemeDoesNotMutateExistingState() async throws {
		let initial = NavigationState(selectedTab: .map, map: .waypoint(99))
		let router = await Router(navigationState: initial)
		let badURL = try #require(URL(string: "https:///messages"))
		await router.route(url: badURL)
		let state = await router.navigationState
		#expect(state == initial)
	}

	// MARK: - Helpers

	private func assertRoute(
		_ urlString: String,
		_ destination: NavigationState
	) async throws {
		let router = await Router()
		let url = try #require(URL(string: urlString))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state == destination)
	}
}
