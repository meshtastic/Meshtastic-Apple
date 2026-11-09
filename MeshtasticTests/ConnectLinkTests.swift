//
//  ConnectLinkTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation
@testable import Meshtastic
import Testing

@Suite("Connect links")
struct ConnectLinkTests {

	private func link(_ string: String) -> ConnectLink? {
		guard let components = URLComponents(string: string) else { return nil }
		return ConnectLink.parse(components)
	}

	@Test func bluetoothLinkCarriesItsPIN() throws {
		let parsed = try #require(link("meshtastic://meshtastic/connections?address=xaa:bb:cc:dd:ee:0f&pin=100000"))
		#expect(parsed.address == .bluetooth("AA:BB:CC:DD:EE:0F"))
		#expect(parsed.pin == "100000")
	}

	@Test func parameterOrderDoesNotMatter() throws {
		let parsed = try #require(link("meshtastic://meshtastic/connections?pin=654321&address=xAA:BB:CC:DD:EE:FF"))
		#expect(parsed.pin == "654321")
	}

	/// Anything but 100000 to 999999, including a leading zero, since firmware stores the PIN as a number.
	@Test func anythingButSixDigitsIsNoPIN() throws {
		for pin in ["12345", "1234567", "12a456", "", "１２３４５６", "012345", "000000"] {
			let parsed = try #require(link("meshtastic://meshtastic/connections?address=xAA:BB:CC:DD:EE:FF&pin=\(pin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"))
			#expect(parsed.pin == nil, "pin \(pin)")
		}
		let noPIN = try #require(link("meshtastic://meshtastic/connections?address=xAA:BB:CC:DD:EE:FF"))
		#expect(noPIN.pin == nil)
	}

	@Test func tcpLinkDefaultsToPort4403AndTakesNoPIN() throws {
		let host = try #require(link("meshtastic://meshtastic/connections?address=t192.168.1.20&pin=123456"))
		#expect(host.address == .tcp(host: "192.168.1.20", port: 4403))
		#expect(host.pin == nil)
		#expect(host.displayAddress == "192.168.1.20:4403")
		let port = try #require(link("meshtastic:///connections?address=tmeshtastic.local:4404"))
		#expect(port.address == .tcp(host: "meshtastic.local", port: 4404))
	}

	@Test func malformedOrUnknownAddressesDoNotParse() {
		for address in ["", "s/dev/ttyUSB0", "AA:BB:CC:DD:EE:FF", "xAA:BB:CC:DD:EE", "xAA:BB:CC:DD:EE:GG", "xAABBCCDDEEFF",
						"t", "t:4403", "thost:0", "thost:70000", "thost:44a3", "t::1", "thost name"] {
			#expect(link("meshtastic://meshtastic/connections?address=\(address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") == nil, "address \(address)")
		}
		#expect(link("meshtastic://meshtastic/connections") == nil)
	}

	@Test func bothFormsOfTheSchemeAreRoutable() throws {
		#expect(Router.isRoutable(try #require(URL(string: "meshtastic:///messages"))))
		#expect(Router.isRoutable(try #require(URL(string: "meshtastic://meshtastic/messages"))))
		#expect(Router.isRoutable(try #require(URL(string: "MESHTASTIC://Meshtastic/map"))))
		#expect(!Router.isRoutable(try #require(URL(string: "meshtastic://e/#abc"))))
		#expect(!Router.isRoutable(try #require(URL(string: "https://meshtastic.org/connections?address=t1.2.3.4"))))
		#expect(ConnectLink.canHandle(try #require(URL(string: "meshtastic://meshtastic/connections?address=t1.2.3.4"))))
		#expect(!ConnectLink.canHandle(try #require(URL(string: "meshtastic://meshtastic/connect"))))
	}

	@Test func openedLinksOnEitherFormOfTheSchemeReachTheRouter() throws {
		#expect(MainScene.IncomingURL(try #require(URL(string: "meshtastic://meshtastic/connections?address=xAA:BB:CC:DD:EE:FF&pin=123456"))) == .route)
		#expect(MainScene.IncomingURL(try #require(URL(string: "meshtastic://meshtastic/nodes?nodenum=42"))) == .route)
		#expect(MainScene.IncomingURL(try #require(URL(string: "meshtastic:///map"))) == .route)
		#expect(MainScene.IncomingURL(try #require(URL(string: "meshtastic://other/nodes"))) == .ignored)
		#expect(MainScene.IncomingURL(try #require(URL(string: "https://meshtastic.org/e/#CgMSAQE"))) == .channel)
		#expect(MainScene.IncomingURL(URL(fileURLWithPath: "/tmp/overlay.geojson")) == .mapFile)
	}

	@MainActor
	@Test func routerHoldsAGoodLinkAndOpensConnectForABadOne() throws {
		let router = Router(navigationState: NavigationState(selectedTab: .messages))
		router.route(url: try #require(URL(string: "meshtastic://meshtastic/connections?address=xAA:BB:CC:DD:EE:FF&pin=999999")))
		#expect(router.connectLinkRequest?.pin == "999999")
		#expect(router.selectedTab == .messages, "nothing happens until the person confirms")

		let bad = Router(navigationState: NavigationState(selectedTab: .messages))
		bad.route(url: try #require(URL(string: "meshtastic://meshtastic/connections?address=s/dev/tty")))
		#expect(bad.connectLinkRequest == nil)
		#expect(bad.selectedTab == .connect)
	}

	@MainActor
	@Test func theOtherRoutesWorkOnTheMeshtasticHost() throws {
		let router = Router(navigationState: NavigationState(selectedTab: .connect))
		router.route(url: try #require(URL(string: "meshtastic://meshtastic/nodes?nodenum=42")))
		#expect(router.selectedTab == .nodes)
		#expect(router.selectedNodeNum == 42)
	}

	@Test func promptShowsTheAddressAndPIN() {
		let withPIN = ConnectLink(address: .bluetooth("AA:BB:CC:DD:EE:FF"), pin: "482915")
		let message = ContentView.connectLinkMessage(withPIN)
		#expect(message.contains("AA:BB:CC:DD:EE:FF") && message.contains("482915"))
		let tcp = ConnectLink(address: .tcp(host: "10.0.0.5", port: 4403), pin: nil)
		#expect(ContentView.connectLinkMessage(tcp).contains("10.0.0.5:4403"))
	}
}
