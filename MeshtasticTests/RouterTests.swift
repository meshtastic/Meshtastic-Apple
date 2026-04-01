import Foundation
import Testing

@testable import Meshtastic

@Suite("Router")
struct RouterTests {

	@Test func initialState() async throws {
		let router = await Router()
		let tab = await router.navigationState.selectedTab
		#expect(tab == .connect)
	}

	@Test func routeMessages() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///messages",
			NavigationState(selectedTab: .messages)
		)
	}

	@Test func routeMessagesWithChannelIdAndMessageId() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///messages?channelId=0&messageId=1122334455",
			NavigationState(
				selectedTab: .messages,
				messages: .channels(
					channelId: 0,
					messageId: 1122334455
				)
			)
		)
	}

	@Test func routeMessagesWithUserNumAndMessageId() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///messages?userNum=123456789&messageId=9876543210",
			NavigationState(
				selectedTab: .messages,
				messages: .directMessages(
					userNum: 123456789,
					messageId: 9876543210
				)
			)
		)
	}

	@Test func routeConnect() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///connect",
			NavigationState(selectedTab: .connect)
		)
	}

	@Test func routeNodes() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///nodes",
			NavigationState(selectedTab: .nodes)
		)
	}

	@Test func routeNodesWithNodeNum() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///nodes?nodenum=1234567890",
			NavigationState(
				selectedTab: .nodes,
				nodeListSelectedNodeNum: 1234567890
			)
		)
	}

	@Test func routeMap() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///map",
			NavigationState(selectedTab: .map)
		)
	}

	@Test func routeMapWithWaypointId() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///map?waypointId=123456",
			NavigationState(
				selectedTab: .map,
				map: .waypoint(123456)
			)
		)
	}

	@Test func routeMapWithNodeNum() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///map?nodenum=1234567890",
			NavigationState(
				selectedTab: .map,
				map: .selectedNode(1234567890)
			)
		)
	}

	@Test func routeSettings() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///settings",
			NavigationState(
				selectedTab: .settings
			)
		)
	}

	@Test func routeSettingsAbout() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///settings/about",
			NavigationState(
				selectedTab: .settings,
				settings: .about
			)
		)
	}

	@Test func routeSettingsInvalidSetting() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///settings/invalidSetting",
			NavigationState(
				selectedTab: .settings
			)
		)
	}

	private func assertRoute(
		router: Router,
		_ urlString: String,
		_ destination: NavigationState
	) async throws {
		let url = try #require(URL(string: urlString))
		await router.route(url: url)
		let state = await router.navigationState
		#expect(state == destination)
	}
}
