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
		("audio", SettingsNavigationState.audio),
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
		("trafficManagement", SettingsNavigationState.trafficManagement),
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

	@Test func navigateToNodeDetailClearsExistingPath() async {
		let router = await Router()
		await router.navigateToNodeDetail(nodeNum: 111)
		await router.navigateToNodeDetail(nodeNum: 222)
		let state = await router.navigationState
		#expect(state.nodeListSelectedNodeNum == 222)
		let selected = await router.selectedNodeNum
		#expect(selected == 222)
	}

	// MARK: - popToRoot

	@Test func popToRootNodes() async {
		let router = await Router()
		await router.navigateToNodeDetail(nodeNum: 42)
		await router.popToRoot(tab: .nodes)
		let selected = await router.selectedNodeNum
		#expect(selected == nil)
		let state = await router.navigationState
		#expect(state.nodeListSelectedNodeNum == nil)
	}

	@Test func popToRootMessages() async {
		let router = await Router()
		let url = URL(string: "meshtastic:///messages?channelId=1")!
		await router.route(url: url)
		let msgBefore = await router.messagesState
		#expect(msgBefore != nil)
		await router.popToRoot(tab: .messages)
		let msgAfter = await router.messagesState
		#expect(msgAfter == nil)
	}

	@Test func popToRootMap() async {
		let router = await Router()
		let url = URL(string: "meshtastic:///map?nodenum=99")!
		await router.route(url: url)
		let mapBefore = await router.mapState
		#expect(mapBefore != nil)
		await router.popToRoot(tab: .map)
		let mapAfter = await router.mapState
		#expect(mapAfter == nil)
	}

	@Test func popToRootSettings() async {
		let router = await Router()
		let url = URL(string: "meshtastic:///settings/about")!
		await router.route(url: url)
		await router.popToRoot(tab: .settings)
		let pathCount = await router.settingsPath.count
		#expect(pathCount == 0)
		let state = await router.navigationState
		#expect(state.settings == nil)
	}

	// MARK: - Path Properties

	@Test func nodeSelectionDrivesNavigation() async {
		let router = await Router()
		await router.navigateToNodeDetail(nodeNum: 12345)
		let selected = await router.selectedNodeNum
		#expect(selected == 12345)
	}

	@Test func settingsPathDrivesNavigation() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///settings/lora"))
		await router.route(url: url)
		let path = await router.settingsPath
		#expect(path == [.lora])
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

// MARK: - One router per window (feature 021, D-19, T308)

@MainActor
@Suite("Window routers")
struct WindowRoutersTests {
	private let windowA = RadioWindow(deviceId: UUID())
	private let windowB = RadioWindow(deviceId: UUID())

	@Test("A direct message goes to the window of the radio that received it")
	func directMessageGoesToItsRadio() {
		let windows = [(window: windowA, radioNum: Int64?(0x0A)), (window: windowB, radioNum: Int64?(0x0B))]
		#expect(WindowRouters.choose(windows: windows, radio: 0x0B, channelRadios: nil, lastActive: windowA) == windowB)
		#expect(WindowRouters.choose(windows: windows, radio: 0x0A, channelRadios: nil, lastActive: windowB) == windowA)
	}

	@Test("A channel message goes to the first window, in the order they opened, whose radio has the channel")
	func channelMessageGoesToTheFirstWindowWithIt() {
		let windows = [(window: windowB, radioNum: Int64?(0x0B)), (window: windowA, radioNum: Int64?(0x0A))]
		#expect(WindowRouters.choose(windows: windows, radio: 0x0A, channelRadios: [0x0A, 0x0B], lastActive: windowA) == windowB)
		#expect(WindowRouters.choose(windows: windows, radio: 0x0A, channelRadios: [0x0A], lastActive: windowB) == windowA)
	}

	@Test("With no window for its radio, a link goes to the window last used, then the first")
	func fallsBackToTheLastWindow() {
		let windows = [(window: windowA, radioNum: Int64?(0x0A)), (window: windowB, radioNum: Int64?(0x0B))]
		#expect(WindowRouters.choose(windows: windows, radio: 0x0C, channelRadios: nil, lastActive: windowB) == windowB)
		#expect(WindowRouters.choose(windows: windows, radio: nil, channelRadios: nil, lastActive: nil) == windowA)
		#expect(WindowRouters.choose(windows: [], radio: 0x0A, channelRadios: nil, lastActive: nil) == nil)
	}

	@Test("A link about a radio with no window open opens its window, and goes there once it's open")
	func opensTheRadiosWindow() throws {
		let registry = WindowRouters(fallback: Router())
		let manager = AccessoryManager(transports: [])
		let radioB = UUID()
		manager.knownNodeNums[radioB] = 456
		let shown = Router()
		registry.register(windowA, router: shown)
		var opened: [RadioWindow] = []
		registry.openWindowHandler = { opened.append($0) }
		let url = try #require(URL(string: "meshtastic:///messages?userNum=123&radio=456"))

		registry.route(url: url, manager: manager)
		#expect(opened == [RadioWindow(deviceId: radioB)], "B's window opens (W-05)")
		#expect(shown.selectedTab != .messages, "A's window isn't moved")
		#expect(registry.pendingLinks[radioB] == url)

		let bRouter = Router()
		registry.register(RadioWindow(deviceId: radioB), router: bRouter)
		#expect(bRouter.selectedTab == .messages)
		#expect(registry.pendingLinks.isEmpty)
	}

	@Test("On the Mac, a link about no radio with no window open opens a connected radio's window")
	func radiolessLinkOpensAWindow() throws {
		let fallback = Router()
		let registry = WindowRouters(fallback: fallback)
		let manager = AccessoryManager(transports: [])
		var opened: [RadioWindow] = []
		registry.openWindowHandler = { opened.append($0) }
		let url = try #require(URL(string: "meshtastic:///settings/debugLogs"))

		registry.route(url: url, manager: manager)
		#expect(opened.isEmpty, "nothing connected: no window to show it in")

		let device = Device(id: UUID(), name: "A", transportType: .tcp, identifier: "a.local:4403")
		manager.activeConnection = RadioSession(device: device, connection: ScriptedRadio(nodeNum: 0x1234))
		registry.route(url: url, manager: manager)
		#expect(opened == [RadioWindow(deviceId: device.id)])
		#expect(registry.pendingLinks[device.id] == url)
	}

	@Test("Windows register and leave; with one open, every link uses its router")
	func registry() throws {
		let fallback = Router()
		let registry = WindowRouters(fallback: fallback)
		#expect(registry.allRouters.map(ObjectIdentifier.init) == [ObjectIdentifier(fallback)])
		let first = Router()
		registry.register(.firstRadio, router: first)
		let url = try #require(URL(string: "meshtastic:///messages?userNum=123&radio=456"))
		#expect(registry.router(for: url, manager: AccessoryManager(transports: [])) === first)
		let second = Router()
		registry.register(windowB, router: second)
		#expect(registry.allRouters.count == 2)
		registry.unregister(router: first)
		#expect(registry.allRouters.map(ObjectIdentifier.init) == [ObjectIdentifier(second)])
	}
}

// MARK: - Radio windows on the Mac (feature 021, D-19, T310)

@MainActor
@Suite("Radio window tracker")
struct RadioWindowTrackerTests {
	@Test("A radio's window opens once when it connects, and again only after the user disconnects it")
	func opensOnce() {
		let tracker = RadioWindowTracker()
		let a = UUID(), b = UUID()
		#expect(tracker.toOpen(connected: [a]) == [a])
		#expect(tracker.toOpen(connected: [a]).isEmpty, "closing the window only hid it (W-01)")
		#expect(tracker.toOpen(connected: [a, b]) == [b])
		// Dropped and back: its window is still open or hidden, so nothing opens.
		#expect(tracker.toOpen(connected: [b]).isEmpty)
		#expect(tracker.toOpen(connected: [a, b]).isEmpty)
		// Disconnected by the user (W-02): its window opens the next time it connects.
		tracker.forget(a)
		#expect(tracker.toOpen(connected: [a, b]) == [a])
	}
}
