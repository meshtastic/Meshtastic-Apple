import Foundation
import XCTest

@testable import Meshtastic

final class RouterTests: XCTestCase {

	func testInitialState() throws {
		XCTAssertEqual(Router().navigationState, .bluetooth)
	}

    func testRouteTo() throws {
		let router = Router(navigationState: .bluetooth)
		router.route(to: .settings(.about))
		XCTAssertEqual(router.navigationState, .settings(.about))
	}

	func testRouteURL() throws {
		// Messages
		try assertRoute("meshtastic:///messages", .messages())
		try assertRoute(
			"meshtastic:///messages?channelId=0&messageId=1122334455",
			.messages(.channels(channelId: 0, messageId: 1122334455))
		)
		try assertRoute(
			"meshtastic:///messages?userNum=123456789&messageId=9876543210",
			.messages(.directMessages(userNum: 123456789, messageId: 9876543210))
		)

		// Bluetooth
		try assertRoute("meshtastic:///bluetooth", .bluetooth)

		// Nodes
		try assertRoute("meshtastic:///nodes", .nodes())
		try assertRoute("meshtastic:///nodes?nodenum=1234567890", .nodes(selectedNodeNum: 1234567890))

		// Map
		try assertRoute("meshtastic:///map", .map())
		try assertRoute("meshtastic:///map?waypointId=123456", .map(.waypoint(123456)))
		try assertRoute("meshtastic:///map?nodenum=1234567890", .map(.selectedNode(1234567890)))

		// Settings
		try assertRoute("meshtastic:///settings", .settings())
		try assertRoute("meshtastic:///settings/about", .settings(.about))
		try assertRoute("meshtastic:///settings/invalidSetting", .settings())
	}

	private func assertRoute(
		router: Router = Router(),
		_ urlString: String,
		_ destination: NavigationState
	) throws {
		let url = try XCTUnwrap(URL(string: urlString))
		router.route(url: url)
		XCTAssertEqual(router.navigationState, destination)
	}
}
