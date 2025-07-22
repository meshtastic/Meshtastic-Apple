import Foundation
import XCTest

@testable import Meshtastic

final class RouterTests: XCTestCase {

	func testInitialState() async throws {
		let router = await Router()
		let tab = await router.navigationState.selectedTab
		XCTAssertEqual(tab, .bluetooth)
	}

	func testRouteMessages() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///messages",
			NavigationState(selectedTab: .messages)
		)
	}

	func testRouteMessagesWithChannelIdAndMessageId() async throws {
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

	func testRouteMessagesWithUserNumAndMessageId() async throws {
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

	func testRouteConnect() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///connect",
			NavigationState(selectedTab: .bluetooth)
		)
	}

	func testRouteNodes() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///nodes",
			NavigationState(selectedTab: .nodes)
		)
	}

	func testRouteNodesWithNodeNum() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///nodes?nodenum=1234567890",
			NavigationState(
				selectedTab: .nodes,
				nodeListSelectedNodeNum: 1234567890
			)
		)
	}

	func testRouteMap() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///map",
			NavigationState(selectedTab: .map)
		)
	}

	func testRouteMapWithWaypointId() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///map?waypointId=123456",
			NavigationState(
				selectedTab: .map,
				map: .waypoint(123456)
			)
		)
	}

	func testRouteMapWithNodeNum() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///map?nodenum=1234567890",
			NavigationState(
				selectedTab: .map,
				map: .selectedNode(1234567890)
			)
		)
	}

	func testRouteSettings() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///settings",
			NavigationState(
				selectedTab: .settings
			)
		)
	}

	func testRouteSettingsAbout() async throws {
		try await assertRoute(
			router: Router(),
			"meshtastic:///settings/about",
			NavigationState(
				selectedTab: .settings,
				settings: .about
			)
		)
	}

	func testRouteSettingsInvalidSetting() async throws {
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
		let url = try XCTUnwrap(URL(string: urlString))
		await router.route(url: url)
		let state = await router.navigationState
		XCTAssertEqual(state, destination)
	}
}
