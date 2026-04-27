// NymeaConstantsTests.swift
// MeshtasticTests

import Testing
import Foundation
@testable import Meshtastic

// MARK: - NymeaWirelessCommand Tests

@Suite("NymeaWirelessCommand")
struct NymeaWirelessCommandTests {

	@Test func rawValues() {
		#expect(NymeaWirelessCommand.getNetworks.rawValue == 0)
		#expect(NymeaWirelessCommand.connect.rawValue == 1)
		#expect(NymeaWirelessCommand.connectHidden.rawValue == 2)
		#expect(NymeaWirelessCommand.disconnect.rawValue == 3)
		#expect(NymeaWirelessCommand.scan.rawValue == 4)
		#expect(NymeaWirelessCommand.getConnection.rawValue == 5)
		#expect(NymeaWirelessCommand.startAccessPoint.rawValue == 6)
	}

	@Test func initFromRawValue() {
		#expect(NymeaWirelessCommand(rawValue: 0) == .getNetworks)
		#expect(NymeaWirelessCommand(rawValue: 6) == .startAccessPoint)
		#expect(NymeaWirelessCommand(rawValue: 99) == nil)
	}
}

// MARK: - NymeaNetworkCommand Tests

@Suite("NymeaNetworkCommand")
struct NymeaNetworkCommandTests {

	@Test func rawValues() {
		#expect(NymeaNetworkCommand.enableNetworking.rawValue == 0x00)
		#expect(NymeaNetworkCommand.disableNetworking.rawValue == 0x01)
		#expect(NymeaNetworkCommand.enableWireless.rawValue == 0x02)
		#expect(NymeaNetworkCommand.disableWireless.rawValue == 0x03)
	}

	@Test func initFromRawValue() {
		#expect(NymeaNetworkCommand(rawValue: 0x00) == .enableNetworking)
		#expect(NymeaNetworkCommand(rawValue: 0x03) == .disableWireless)
		#expect(NymeaNetworkCommand(rawValue: 0xFF) == nil)
	}
}

// MARK: - NymeaWirelessConnectionStatus Tests

@Suite("NymeaWirelessConnectionStatus")
struct NymeaWirelessConnectionStatusTests {

	@Test func allCases_haveDescriptions() {
		let cases: [NymeaWirelessConnectionStatus] = [
			.unknown, .unmanaged, .unavailable, .disconnected,
			.prepare, .config, .needAuth, .ipConfig,
			.ipCheck, .secondaries, .activated, .deactivating, .failed
		]
		for c in cases {
			#expect(!c.description.isEmpty)
		}
	}

	@Test func descriptions_correctValues() {
		#expect(NymeaWirelessConnectionStatus.unknown.description == "Unknown")
		#expect(NymeaWirelessConnectionStatus.disconnected.description == "Disconnected")
		#expect(NymeaWirelessConnectionStatus.activated.description == "Connected")
		#expect(NymeaWirelessConnectionStatus.failed.description == "Failed")
		#expect(NymeaWirelessConnectionStatus.needAuth.description == "Needs Authentication")
		#expect(NymeaWirelessConnectionStatus.ipConfig.description == "Obtaining IP Address")
	}

	@Test func isConnecting_trueForActiveStates() {
		let connectingCases: [NymeaWirelessConnectionStatus] = [
			.prepare, .config, .needAuth, .ipConfig, .ipCheck, .secondaries
		]
		for c in connectingCases {
			#expect(c.isConnecting == true, "Expected \(c) to be connecting")
		}
	}

	@Test func isConnecting_falseForNonActiveStates() {
		let nonConnecting: [NymeaWirelessConnectionStatus] = [
			.unknown, .unmanaged, .unavailable, .disconnected, .activated, .deactivating, .failed
		]
		for c in nonConnecting {
			#expect(c.isConnecting == false, "Expected \(c) to NOT be connecting")
		}
	}

	@Test func rawValues() {
		#expect(NymeaWirelessConnectionStatus.unknown.rawValue == 0x00)
		#expect(NymeaWirelessConnectionStatus.activated.rawValue == 0x0A)
		#expect(NymeaWirelessConnectionStatus.failed.rawValue == 0x0C)
	}
}

// MARK: - NymeaWirelessMode Tests

@Suite("NymeaWirelessMode")
struct NymeaWirelessModeTests {

	@Test func rawValues() {
		#expect(NymeaWirelessMode.unknown.rawValue == 0x00)
		#expect(NymeaWirelessMode.adhoc.rawValue == 0x01)
		#expect(NymeaWirelessMode.infrastructure.rawValue == 0x02)
		#expect(NymeaWirelessMode.accessPoint.rawValue == 0x03)
	}

	@Test func initFromRawValue() {
		#expect(NymeaWirelessMode(rawValue: 0x02) == .infrastructure)
		#expect(NymeaWirelessMode(rawValue: 0xFF) == nil)
	}
}

// MARK: - NymeaNetworkStatus Tests

@Suite("NymeaNetworkStatus")
struct NymeaNetworkStatusTests {

	@Test func rawValues() {
		#expect(NymeaNetworkStatus.unknown.rawValue == 0x00)
		#expect(NymeaNetworkStatus.asleep.rawValue == 0x01)
		#expect(NymeaNetworkStatus.disconnected.rawValue == 0x02)
		#expect(NymeaNetworkStatus.disconnecting.rawValue == 0x03)
		#expect(NymeaNetworkStatus.connecting.rawValue == 0x04)
		#expect(NymeaNetworkStatus.local.rawValue == 0x05)
		#expect(NymeaNetworkStatus.connectedSite.rawValue == 0x06)
		#expect(NymeaNetworkStatus.connectedGlobal.rawValue == 0x07)
	}

	@Test func initFromRawValue() {
		#expect(NymeaNetworkStatus(rawValue: 0x07) == .connectedGlobal)
		#expect(NymeaNetworkStatus(rawValue: 0xFF) == nil)
	}
}

// MARK: - NymeaCommanderError Tests

@Suite("NymeaCommanderError")
struct NymeaCommanderErrorTests {

	@Test func success_hasNoDescription() {
		#expect(NymeaCommanderError.success.errorDescription == nil)
	}

	@Test func allErrors_haveDescriptions() {
		let errors: [NymeaCommanderError] = [
			.invalidCommand, .invalidParameter, .networkManagerNotAvailable,
			.wirelessNotAvailable, .networkingDisabled, .wirelessDisabled, .unknown
		]
		for e in errors {
			#expect(e.errorDescription != nil)
			#expect(!e.errorDescription!.isEmpty)
		}
	}

	@Test func rawValues() {
		#expect(NymeaCommanderError.success.rawValue == 0)
		#expect(NymeaCommanderError.invalidCommand.rawValue == 1)
		#expect(NymeaCommanderError.unknown.rawValue == 7)
	}

	@Test func codable_roundTrip() throws {
		let original = NymeaCommanderError.wirelessNotAvailable
		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(NymeaCommanderError.self, from: data)
		#expect(decoded == original)
	}
}

// MARK: - NymeaNetworkCommanderError Tests

@Suite("NymeaNetworkCommanderError")
struct NymeaNetworkCommanderErrorTests {

	@Test func success_hasNoDescription() {
		#expect(NymeaNetworkCommanderError.success.errorDescription == nil)
	}

	@Test func allErrors_haveDescriptions() {
		let errors: [NymeaNetworkCommanderError] = [
			.invalidValue, .networkManagerNotAvailable, .wirelessNotAvailable, .unknown
		]
		for e in errors {
			#expect(e.errorDescription != nil)
			#expect(!e.errorDescription!.isEmpty)
		}
	}

	@Test func rawValues() {
		#expect(NymeaNetworkCommanderError.success.rawValue == 0x00)
		#expect(NymeaNetworkCommanderError.invalidValue.rawValue == 0x01)
		#expect(NymeaNetworkCommanderError.unknown.rawValue == 0x04)
	}
}

// MARK: - NymeaCommandPacket Encoding Tests

@Suite("NymeaCommandPacket Encoding")
struct NymeaCommandPacketEncodingTests {

	@Test func encode_withParams() throws {
		let params = NymeaConnectParams(e: "MyWifi", p: "secret")
		let packet = NymeaCommandPacket(command: .connect, params: params)
		let data = try JSONEncoder().encode(packet)
		let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		#expect(json?["c"] as? Int == 1)
		let p = json?["p"] as? [String: String]
		#expect(p?["e"] == "MyWifi")
		#expect(p?["p"] == "secret")
	}

	@Test func simpleCommand_encoding() throws {
		let cmd = NymeaSimpleCommand(command: .getNetworks)
		let data = try JSONEncoder().encode(cmd)
		let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		#expect(json?["c"] as? Int == 0)
	}
}

// MARK: - NymeaResponsePacket Decoding Tests

@Suite("NymeaResponsePacket Decoding")
struct NymeaResponsePacketDecodingTests {

	@Test func decode_successResponse() throws {
		let json = #"{"c":0,"r":0}"#
		let data = Data(json.utf8)
		let response = try JSONDecoder().decode(NymeaResponsePacket.self, from: data)
		#expect(response.c == 0)
		#expect(response.r == 0)
	}

	@Test func decode_errorResponse() throws {
		let json = #"{"c":1,"r":4}"#
		let data = Data(json.utf8)
		let response = try JSONDecoder().decode(NymeaResponsePacket.self, from: data)
		#expect(response.c == 1)
		#expect(response.r == 4)
	}
}

// MARK: - NymeaWifiNetwork Tests

@Suite("NymeaWifiNetwork Decoding")
struct NymeaWifiNetworkDecodingTests {

	@Test func decode_protectedNetwork() throws {
		let json = #"{"e":"HomeWifi","m":"AA:BB:CC:DD:EE:FF","s":85,"p":1}"#
		let data = Data(json.utf8)
		let network = try JSONDecoder().decode(NymeaWifiNetwork.self, from: data)
		#expect(network.essid == "HomeWifi")
		#expect(network.bssid == "AA:BB:CC:DD:EE:FF")
		#expect(network.signal == 85)
		#expect(network.isProtected == true)
	}

	@Test func decode_openNetwork() throws {
		let json = #"{"e":"FreeWifi","m":"11:22:33:44:55:66","s":30,"p":0}"#
		let data = Data(json.utf8)
		let network = try JSONDecoder().decode(NymeaWifiNetwork.self, from: data)
		#expect(network.isProtected == false)
	}

	@Test func id_isBssid() throws {
		let json = #"{"e":"Test","m":"AA:BB:CC:DD:EE:FF","s":50,"p":0}"#
		let data = Data(json.utf8)
		let network = try JSONDecoder().decode(NymeaWifiNetwork.self, from: data)
		#expect(network.id == "AA:BB:CC:DD:EE:FF")
	}

	@Test func signalBars_strongSignal() throws {
		let json = #"{"e":"Test","m":"00:00:00:00:00:01","s":85,"p":0}"#
		let data = Data(json.utf8)
		let network = try JSONDecoder().decode(NymeaWifiNetwork.self, from: data)
		#expect(network.signalBars == 4)
	}

	@Test func signalBars_goodSignal() throws {
		let json = #"{"e":"Test","m":"00:00:00:00:00:02","s":60,"p":0}"#
		let data = Data(json.utf8)
		let network = try JSONDecoder().decode(NymeaWifiNetwork.self, from: data)
		#expect(network.signalBars == 3)
	}

	@Test func signalBars_fairSignal() throws {
		let json = #"{"e":"Test","m":"00:00:00:00:00:03","s":40,"p":0}"#
		let data = Data(json.utf8)
		let network = try JSONDecoder().decode(NymeaWifiNetwork.self, from: data)
		#expect(network.signalBars == 2)
	}

	@Test func signalBars_weakSignal() throws {
		let json = #"{"e":"Test","m":"00:00:00:00:00:04","s":10,"p":0}"#
		let data = Data(json.utf8)
		let network = try JSONDecoder().decode(NymeaWifiNetwork.self, from: data)
		#expect(network.signalBars == 1)
	}

	@Test func signalBars_noSignal() throws {
		let json = #"{"e":"Test","m":"00:00:00:00:00:05","s":0,"p":0}"#
		let data = Data(json.utf8)
		let network = try JSONDecoder().decode(NymeaWifiNetwork.self, from: data)
		#expect(network.signalBars == 0)
	}

	@Test func hashable_conformance() throws {
		let json = #"{"e":"Test","m":"AA:BB:CC:DD:EE:FF","s":50,"p":0}"#
		let data = Data(json.utf8)
		let n1 = try JSONDecoder().decode(NymeaWifiNetwork.self, from: data)
		let n2 = try JSONDecoder().decode(NymeaWifiNetwork.self, from: data)
		#expect(n1 == n2)
		var set = Set<NymeaWifiNetwork>()
		set.insert(n1)
		set.insert(n2)
		#expect(set.count == 1)
	}
}

// MARK: - NymeaGetNetworksResponse Tests

@Suite("NymeaGetNetworksResponse Decoding")
struct NymeaGetNetworksResponseDecodingTests {

	@Test func decode_withNetworks() throws {
		let json = """
		{"c":0,"r":0,"p":[{"e":"Net1","m":"AA:BB:CC:DD:EE:01","s":80,"p":1},{"e":"Net2","m":"AA:BB:CC:DD:EE:02","s":30,"p":0}]}
		"""
		let data = Data(json.utf8)
		let response = try JSONDecoder().decode(NymeaGetNetworksResponse.self, from: data)
		#expect(response.c == 0)
		#expect(response.r == 0)
		#expect(response.p?.count == 2)
		#expect(response.p?.first?.essid == "Net1")
	}

	@Test func decode_emptyNetworks() throws {
		let json = #"{"c":0,"r":0,"p":[]}"#
		let data = Data(json.utf8)
		let response = try JSONDecoder().decode(NymeaGetNetworksResponse.self, from: data)
		#expect(response.p?.isEmpty == true)
	}
}

// MARK: - NymeaWifiConnection Tests

@Suite("NymeaWifiConnection Decoding")
struct NymeaWifiConnectionDecodingTests {

	@Test func decode_connected() throws {
		let json = #"{"e":"HomeNet","m":"AA:BB:CC:DD:EE:FF","s":90,"p":1,"i":"192.168.1.100"}"#
		let data = Data(json.utf8)
		let conn = try JSONDecoder().decode(NymeaWifiConnection.self, from: data)
		#expect(conn.essid == "HomeNet")
		#expect(conn.bssid == "AA:BB:CC:DD:EE:FF")
		#expect(conn.signal == 90)
		#expect(conn.isProtected == true)
		#expect(conn.ipAddress == "192.168.1.100")
	}
}

// MARK: - NymeaGetConnectionResponse Tests

@Suite("NymeaGetConnectionResponse Decoding")
struct NymeaGetConnectionResponseDecodingTests {

	@Test func decode_withConnection() throws {
		let json = #"{"c":5,"r":0,"p":{"e":"Net","m":"00:11:22:33:44:55","s":70,"p":0,"i":"10.0.0.1"}}"#
		let data = Data(json.utf8)
		let response = try JSONDecoder().decode(NymeaGetConnectionResponse.self, from: data)
		#expect(response.c == 5)
		#expect(response.r == 0)
		#expect(response.p?.ipAddress == "10.0.0.1")
	}
}

// MARK: - NymeaConnectParams Tests

@Suite("NymeaConnectParams Encoding")
struct NymeaConnectParamsEncodingTests {

	@Test func encode_withPassword() throws {
		let params = NymeaConnectParams(e: "TestSSID", p: "mypassword")
		let data = try JSONEncoder().encode(params)
		let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
		#expect(json?["e"] == "TestSSID")
		#expect(json?["p"] == "mypassword")
	}

	@Test func encode_openNetwork() throws {
		let params = NymeaConnectParams(e: "OpenNet", p: "")
		let data = try JSONEncoder().encode(params)
		let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
		#expect(json?["e"] == "OpenNet")
		#expect(json?["p"] == "")
	}
}
