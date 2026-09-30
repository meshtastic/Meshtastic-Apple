import Foundation
import Testing

@testable import Meshtastic

@Suite("TCP discovery names")
struct TCPTransportDiscoveryTests {
	@Test func usesServiceNameAndIPWithoutTXT() {
		#expect(TCPTransport.discoveryName(serviceName: "Meshtastic", host: "meshcon.local.", ip: "192.168.1.20", port: 4403, txtRecords: nil) == "Meshtastic (192.168.1.20:4403)")
	}

	@Test func usesServiceNameAndIPForEmptyTXT() {
		#expect(TCPTransport.discoveryName(serviceName: "Nebra-Stick", host: "meshcon.local.", ip: "192.168.1.20", port: 4405, txtRecords: [:]) == "Nebra-Stick (192.168.1.20:4405)")
	}

	@Test func usesHostWhenIPIsUnavailable() {
		#expect(TCPTransport.discoveryName(serviceName: "Meshtastic", host: "meshcon.local.", ip: nil, port: 4403, txtRecords: [:]) == "Meshtastic (meshcon.local:4403)")
	}

	@Test func usesHostWhenServiceNameIsUnavailable() {
		#expect(TCPTransport.discoveryName(serviceName: " ", host: "meshcon.local.", ip: "192.168.1.20", port: 4403, txtRecords: [:]) == "meshcon.local (192.168.1.20:4403)")
	}

	@Test func ignoresUnusableTXTName() {
		#expect(TCPTransport.discoveryName(serviceName: "Meshtastic", host: "meshcon.local.", ip: "192.168.1.20", port: 4403, txtRecords: ["shortname": Data("  ".utf8)]) == "Meshtastic (192.168.1.20:4403)")
	}

	@Test func preservesNameFromTXT() {
		let records = ["shortname": Data("NODE".utf8), "id": Data("!12345678".utf8)]
		#expect(TCPTransport.discoveryName(serviceName: "Meshtastic", host: "meshcon.local.", ip: "192.168.1.20", port: 4403, txtRecords: records) == "NODE_5678")
	}
}
