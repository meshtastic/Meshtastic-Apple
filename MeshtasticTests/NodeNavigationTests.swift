import Foundation
import Testing

@testable import Meshtastic

@Suite("Node Navigation & Deep Links")
struct NodeNavigationTests {

	// MARK: - navigateToNodeDetail

	@Test func navigateToNodeDetailSetsTabAndNodeNum() async {
		let router = await Router()
		await router.navigateToNodeDetail(nodeNum: 1234567890)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == 1234567890)
	}

	@Test func navigateToNodeDetailOverwritesPreviousNodeNum() async {
		let router = await Router()
		await router.navigateToNodeDetail(nodeNum: 111)
		await router.navigateToNodeDetail(nodeNum: 222)
		let state = await router.navigationState
		#expect(state.nodeListSelectedNodeNum == 222)
	}

	@Test func navigateToNodeDetailFromDifferentTab() async {
		let router = await Router(navigationState: NavigationState(
			selectedTab: .messages,
			messages: .channels(channelId: 0, messageId: nil)
		))
		await router.navigateToNodeDetail(nodeNum: 42)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == 42)
	}

	@Test func navigateToNodeDetailPreservesOtherTabState() async {
		let router = await Router(navigationState: NavigationState(
			selectedTab: .settings,
			settings: .lora
		))
		await router.navigateToNodeDetail(nodeNum: 99)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == 99)
		// Settings state should still be present
		#expect(state.settings == .lora)
	}

	// MARK: - Deep Link: /nodes

	@Test func deepLinkNodesWithNodeNum() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///nodes?nodenum=9876543210"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == 9876543210)
	}

	@Test func deepLinkNodesWithoutNodeNum() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///nodes"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == nil)
	}

	@Test func deepLinkNodesWithZeroNodeNum() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///nodes?nodenum=0"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == 0)
	}

	@Test func deepLinkNodesWithNegativeNodeNum() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///nodes?nodenum=-1"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == -1)
	}

	@Test func deepLinkNodesWithNonNumericNodeNumIgnored() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///nodes?nodenum=abc"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == nil)
	}

	@Test func deepLinkNodesWithEmptyNodeNumIgnored() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///nodes?nodenum="))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == nil)
	}

	@Test func deepLinkNodesWithMaxInt64() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///nodes?nodenum=\(Int64.max)"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == Int64.max)
	}

	@Test func deepLinkNodesWithExtraQueryParamsIgnoresThem() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///nodes?nodenum=42&extra=ignored"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == 42)
	}

	// MARK: - Deep Link: /map with nodenum

	@Test func deepLinkMapWithNodeNum() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///map?nodenum=555"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .map)
		#expect(state.map == .selectedNode(555))
	}

	@Test func deepLinkMapNodeNumTakesPriorityOverWaypoint() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///map?nodenum=111&waypointId=222"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.map == .selectedNode(111))
	}

	// MARK: - Sequential Navigation

	@Test func navigateToNodeThenClearSelection() async {
		let router = await Router()
		await router.navigateToNodeDetail(nodeNum: 42)
		await MainActor.run { router.nodeListSelectedNodeNum = nil }
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == nil)
	}

	@Test func deepLinkToNodeThenDeepLinkToMap() async throws {
		let router = await Router()

		let nodesURL = try #require(URL(string: "meshtastic:///nodes?nodenum=100"))
		await router.route(url: nodesURL)
		let nodesState = await router.navigationState
		#expect(nodesState.selectedTab == .nodes)
		#expect(nodesState.nodeListSelectedNodeNum == 100)

		let mapURL = try #require(URL(string: "meshtastic:///map?nodenum=200"))
		await router.route(url: mapURL)
		let mapState = await router.navigationState
		#expect(mapState.selectedTab == .map)
		#expect(mapState.map == .selectedNode(200))
		// Node selection should still be present from the nodes tab
		#expect(mapState.nodeListSelectedNodeNum == 100)
	}

	@Test func deepLinkToMapThenNavigateToNodeDetail() async throws {
		let router = await Router()

		let mapURL = try #require(URL(string: "meshtastic:///map?waypointId=99"))
		await router.route(url: mapURL)
		#expect(await router.navigationState.selectedTab == .map)

		await router.navigateToNodeDetail(nodeNum: 42)
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == 42)
		// Map state should still be set
		#expect(state.map == .waypoint(99))
	}

	@Test func rapidNodeNavigationUpdatesAreSafe() async {
		let router = await Router()
		// Simulate rapid-fire node selections
		for i: Int64 in 1...20 {
			await router.navigateToNodeDetail(nodeNum: i)
		}
		let state = await router.navigationState
		#expect(state.selectedTab == .nodes)
		#expect(state.nodeListSelectedNodeNum == 20)
	}

	// MARK: - Deep Link: /messages with userNum (navigates to DM with a node)

	@Test func deepLinkToDirectMessageForNode() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///messages?userNum=42"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .messages)
		#expect(state.messages == .directMessages(userNum: 42, messageId: nil))
	}

	@Test func deepLinkToDirectMessageWithSpecificMessage() async throws {
		let router = await Router()
		let url = try #require(URL(string: "meshtastic:///messages?userNum=42&messageId=999"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.messages == .directMessages(userNum: 42, messageId: 999))
	}

	// MARK: - Invalid Deep Links

	@Test func wrongSchemeDoesNotNavigateToNodes() async throws {
		let router = await Router()
		let url = try #require(URL(string: "https:///nodes?nodenum=42"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state.selectedTab == .connect)
		#expect(state.nodeListSelectedNodeNum == nil)
	}

	@Test func wrongSchemeDoesNotMutateExistingNodeSelection() async throws {
		let initial = NavigationState(selectedTab: .nodes, nodeListSelectedNodeNum: 100)
		let router = await Router(navigationState: initial)
		let url = try #require(URL(string: "https:///nodes?nodenum=42"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state == initial)
	}

	@Test func unknownPathDoesNotAffectNodeState() async throws {
		let initial = NavigationState(selectedTab: .nodes, nodeListSelectedNodeNum: 100)
		let router = await Router(navigationState: initial)
		let url = try #require(URL(string: "meshtastic:///foobar?nodenum=999"))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state == initial)
	}

	// MARK: - Node Object ID Cache

	@Test func cachedNodeInfoReturnNilForUnknownNode() async {
		let router = await Router()
		let context = await sharedModelContainer.mainContext
		let result = await router.cachedNodeInfo(id: 999999, context: context)
		#expect(result == nil)
	}
}
