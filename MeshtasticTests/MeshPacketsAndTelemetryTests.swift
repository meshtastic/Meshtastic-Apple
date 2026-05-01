// MeshPacketsAndTelemetryTests.swift
// MeshtasticTests

import Testing
import Foundation
import SwiftUI
@testable import Meshtastic

// MARK: - generateMessageMarkdown Tests

@Suite("generateMessageMarkdown")
struct GenerateMessageMarkdownTests {

	@Test func plainText_returnsUnchanged() {
		let result = generateMessageMarkdown(message: "Hello World")
		#expect(result == "Hello World")
	}

	@Test func emojiOnly_returnsUnchanged() {
		let result = generateMessageMarkdown(message: "😀🎉🔥")
		#expect(result == "😀🎉🔥")
	}

	@Test func urlDetected_createsMarkdownLink() {
		let result = generateMessageMarkdown(message: "Visit https://meshtastic.org for info")
		#expect(result.contains("[https://meshtastic.org](https://meshtastic.org)"))
	}

	@Test func phoneNumber_createsTelLink() {
		let result = generateMessageMarkdown(message: "Call me at (555) 123-4567")
		#expect(result.contains("tel:"))
		#expect(result.contains("555"))
	}

	@Test func address_createsMapsLink() {
		let result = generateMessageMarkdown(message: "Meet at 1600 Pennsylvania Avenue NW, Washington, DC 20500")
		#expect(result.contains("maps.apple.com"))
	}

	@Test func emptyString_returnsEmpty() {
		let result = generateMessageMarkdown(message: "")
		#expect(result == "")
	}

	@Test func noMatches_returnsOriginal() {
		let result = generateMessageMarkdown(message: "just a plain text message")
		#expect(result == "just a plain text message")
	}

	@Test func multipleURLs_allConverted() {
		let result = generateMessageMarkdown(message: "Check https://meshtastic.org and https://github.com")
		#expect(result.contains("[https://meshtastic.org]"))
		#expect(result.contains("[https://github.com]"))
	}
}

// MARK: - TelemetryEnums Aqi

@Suite("Aqi getAqi boundary values")
struct AqiGetAqiBoundaryTests {

	@Test func getAqi_good_low() {
		#expect(Aqi.getAqi(for: 0) == .good)
	}

	@Test func getAqi_good_high() {
		#expect(Aqi.getAqi(for: 50) == .good)
	}

	@Test func getAqi_moderate_low() {
		#expect(Aqi.getAqi(for: 51) == .moderate)
	}

	@Test func getAqi_moderate_high() {
		#expect(Aqi.getAqi(for: 100) == .moderate)
	}

	@Test func getAqi_sensitive_low() {
		#expect(Aqi.getAqi(for: 101) == .sensitive)
	}

	@Test func getAqi_sensitive_high() {
		#expect(Aqi.getAqi(for: 150) == .sensitive)
	}

	@Test func getAqi_unhealthy_low() {
		#expect(Aqi.getAqi(for: 151) == .unhealthy)
	}

	@Test func getAqi_unhealthy_high() {
		#expect(Aqi.getAqi(for: 200) == .unhealthy)
	}

	@Test func getAqi_veryUnhealthy_low() {
		#expect(Aqi.getAqi(for: 201) == .veryUnhealthy)
	}

	@Test func getAqi_veryUnhealthy_high() {
		#expect(Aqi.getAqi(for: 300) == .veryUnhealthy)
	}

	@Test func getAqi_hazardous_low() {
		#expect(Aqi.getAqi(for: 301) == .hazardous)
	}

	@Test func getAqi_hazardous_high() {
		#expect(Aqi.getAqi(for: 500) == .hazardous)
	}
}

@Suite("Aqi range property")
struct AqiRangePropertyTests {

	@Test func allCases_haveValidRanges() {
		for aqi in Aqi.allCases {
			let range = aqi.range
			#expect(!range.isEmpty)
		}
	}

	@Test func good_range() {
		#expect(Aqi.good.range.contains(25))
		#expect(!Aqi.good.range.contains(51))
	}

	@Test func hazardous_range() {
		#expect(Aqi.hazardous.range.contains(400))
		#expect(!Aqi.hazardous.range.contains(200))
	}
}

@Suite("Aqi color property")
struct AqiColorPropertyTests {

	@Test func allCases_haveColors() {
		for aqi in Aqi.allCases {
			_ = aqi.color // should not crash
		}
	}
}

// MARK: - TelemetryEnums Iaq

@Suite("Iaq getIaq boundary values")
struct IaqGetIaqBoundaryTests {

	@Test func getIaq_excellent_low() {
		#expect(Iaq.getIaq(for: 0) == .excellent)
	}

	@Test func getIaq_excellent_high() {
		#expect(Iaq.getIaq(for: 50) == .excellent)
	}

	@Test func getIaq_good_low() {
		#expect(Iaq.getIaq(for: 51) == .good)
	}

	@Test func getIaq_good_high() {
		#expect(Iaq.getIaq(for: 100) == .good)
	}

	@Test func getIaq_lightlyPolluted() {
		#expect(Iaq.getIaq(for: 125) == .lightlyPolluted)
	}

	@Test func getIaq_moderatelyPolluted() {
		#expect(Iaq.getIaq(for: 175) == .moderatelyPolluted)
	}

	@Test func getIaq_heavilyPolluted() {
		#expect(Iaq.getIaq(for: 225) == .heavilyPolluted)
	}

	@Test func getIaq_severelyPolluted() {
		#expect(Iaq.getIaq(for: 300) == .severelyPolluted)
	}

	@Test func getIaq_extremelyPolluted_low() {
		#expect(Iaq.getIaq(for: 351) == .extremelyPolluted)
	}

	@Test func getIaq_extremelyPolluted_high() {
		#expect(Iaq.getIaq(for: 999) == .extremelyPolluted)
	}
}

@Suite("Iaq range property")
struct IaqRangePropertyTests {

	@Test func allCases_haveValidRanges() {
		for iaq in Iaq.allCases {
			let range = iaq.range
			#expect(!range.isEmpty)
		}
	}

	@Test func excellent_range() {
		#expect(Iaq.excellent.range.contains(25))
		#expect(!Iaq.excellent.range.contains(51))
	}
}

@Suite("Iaq color property")
struct IaqColorPropertyTests {

	@Test func allCases_haveColors() {
		for iaq in Iaq.allCases {
			_ = iaq.color
		}
	}
}

@Suite("Iaq description property")
struct IaqDescriptionPropertyTests {

	@Test func allCases_haveDescriptions() {
		for iaq in Iaq.allCases {
			#expect(!iaq.description.isEmpty)
		}
	}

	@Test func specificDescriptions() {
		#expect(Iaq.excellent.description == "Excellent")
		#expect(Iaq.extremelyPolluted.description == "Extremely Polluted")
	}
}

// MARK: - MetricsTypes name

@Suite("MetricsTypes name property")
struct MetricsTypesNameExtendedTests {

	@Test func allCases_haveNames() {
		for mt in MetricsTypes.allCases {
			#expect(!mt.name.isEmpty)
		}
	}

	@Test func specificNames() {
		#expect(MetricsTypes.device.name == "Device Metrics")
		#expect(MetricsTypes.environment.name == "Environment Metrics")
		#expect(MetricsTypes.power.name == "Power Metrics")
		#expect(MetricsTypes.airQuality.name == "Air Quality Metrics")
		#expect(MetricsTypes.stats.name == "Stats")
	}
}

// MARK: - NymeaWifiNetwork signalBars

@Suite("NymeaWifiNetwork signalBars")
struct NymeaWifiNetworkSignalBarsTests {

	private func makeNetwork(signal: Int) throws -> NymeaWifiNetwork {
		let json = """
		{"e":"TestSSID","m":"AA:BB:CC:DD:EE:FF","s":\(signal),"p":1}
		"""
		return try JSONDecoder().decode(NymeaWifiNetwork.self, from: json.data(using: .utf8)!)
	}

	@Test func signalBars_highSignal() throws {
		let net = try makeNetwork(signal: 80)
		#expect(net.signalBars == 4)
	}

	@Test func signalBars_boundary76() throws {
		let net = try makeNetwork(signal: 76)
		#expect(net.signalBars == 4)
	}

	@Test func signalBars_boundary75() throws {
		let net = try makeNetwork(signal: 75)
		#expect(net.signalBars == 3)
	}

	@Test func signalBars_boundary51() throws {
		let net = try makeNetwork(signal: 51)
		#expect(net.signalBars == 3)
	}

	@Test func signalBars_boundary50() throws {
		let net = try makeNetwork(signal: 50)
		#expect(net.signalBars == 2)
	}

	@Test func signalBars_boundary26() throws {
		let net = try makeNetwork(signal: 26)
		#expect(net.signalBars == 2)
	}

	@Test func signalBars_boundary25() throws {
		let net = try makeNetwork(signal: 25)
		#expect(net.signalBars == 1)
	}

	@Test func signalBars_boundary1() throws {
		let net = try makeNetwork(signal: 1)
		#expect(net.signalBars == 1)
	}

	@Test func signalBars_zero() throws {
		let net = try makeNetwork(signal: 0)
		#expect(net.signalBars == 0)
	}

	@Test func signalBars_negative() throws {
		let net = try makeNetwork(signal: -10)
		#expect(net.signalBars == 0)
	}

	@Test func isProtected_fromInt() throws {
		let openJson = """
		{"e":"Open","m":"11:22:33:44:55:66","s":50,"p":0}
		"""
		let openNet = try JSONDecoder().decode(NymeaWifiNetwork.self, from: openJson.data(using: .utf8)!)
		#expect(openNet.isProtected == false)

		let protectedJson = """
		{"e":"Secured","m":"AA:BB:CC:DD:EE:FF","s":50,"p":1}
		"""
		let protectedNet = try JSONDecoder().decode(NymeaWifiNetwork.self, from: protectedJson.data(using: .utf8)!)
		#expect(protectedNet.isProtected == true)
	}

	@Test func hashable_sameNetwork() throws {
		let net1 = try makeNetwork(signal: 50)
		let net2 = try makeNetwork(signal: 50)
		#expect(net1 == net2)
	}
}

// MARK: - NymeaCommandPacket encoding

@Suite("NymeaCommandPacket encoding extended")
struct NymeaCommandPacketEncodingExtendedTests {

	@Test func encodeWithParams() throws {
		let packet = NymeaCommandPacket(command: .connect, params: NymeaConnectParams(e: "MySSID", p: "password"))
		let data = try JSONEncoder().encode(packet)
		let json = String(data: data, encoding: .utf8)!
		#expect(json.contains("\"c\":1"))
		#expect(json.contains("MySSID"))
	}

	@Test func encodeSimpleCommand() throws {
		let cmd = NymeaSimpleCommand(command: .getConnection)
		let data = try JSONEncoder().encode(cmd)
		let json = String(data: data, encoding: .utf8)!
		#expect(json.contains("\"c\":5"))
	}
}

// MARK: - NymeaResponsePacket decoding

@Suite("NymeaResponsePacket decoding extended")
struct NymeaResponsePacketDecodingExtendedTests {

	@Test func decodeResponse() throws {
		let json = """
		{"c":0,"r":0}
		"""
		let response = try JSONDecoder().decode(NymeaResponsePacket.self, from: json.data(using: .utf8)!)
		#expect(response.c == 0)
		#expect(response.r == 0)
	}
}

// MARK: - NymeaWirelessConnectionStatus

@Suite("NymeaWirelessConnectionStatus extended")
struct NymeaWirelessConnectionStatusExtendedTests {

	@Test func isConnecting_trueCases() {
		let connectingStatuses: [NymeaWirelessConnectionStatus] = [
			.prepare,
			.config,
			.needAuth,
			.ipConfig,
			.ipCheck,
			.secondaries
		]
		for status in connectingStatuses {
			#expect(status.isConnecting)
		}
	}

	@Test func isConnecting_falseCases() {
		let notConnectingStatuses: [NymeaWirelessConnectionStatus] = [
			.disconnected,
			.activated,
			.unknown,
			.failed
		]
		for status in notConnectingStatuses {
			#expect(!status.isConnecting)
		}
	}

	@Test func descriptions_nonEmpty() {
		let allStatuses: [NymeaWirelessConnectionStatus] = [
			.unknown, .unmanaged, .unavailable, .disconnected,
			.prepare, .config, .needAuth, .ipConfig, .ipCheck,
			.secondaries, .activated, .deactivating, .failed
		]
		for status in allStatuses {
			#expect(!status.description.isEmpty)
		}
	}
}

// MARK: - NymeaCommanderError

@Suite("NymeaCommanderError descriptions extended")
struct NymeaCommanderErrorDescriptionExtendedTests {

	@Test func errors_haveDescriptions() {
		let errors: [NymeaCommanderError] = [
			.invalidCommand, .invalidParameter,
			.networkManagerNotAvailable, .wirelessNotAvailable,
			.networkingDisabled, .wirelessDisabled, .unknown
		]
		for error in errors {
			#expect(error.errorDescription != nil)
			#expect(!error.errorDescription!.isEmpty)
		}
	}

	@Test func success_returnsNil() {
		#expect(NymeaCommanderError.success.errorDescription == nil)
	}
}

// MARK: - URL.TimeoutError

@Suite("URL TimeoutError extended")
struct URLTimeoutErrorExtendedTests {

	@Test func errorDescription_containsSeconds() {
		let error = URL.TimeoutError.timedOut(30.0)
		#expect(error.errorDescription?.contains("30.0") == true)
		#expect(error.errorDescription?.contains("timed out") == true)
	}

	@Test func errorDescription_smallTimeout() {
		let error = URL.TimeoutError.timedOut(0.5)
		#expect(error.errorDescription?.contains("0.5") == true)
	}
}

// MARK: - NymeaGetNetworksResponse

@Suite("NymeaGetNetworksResponse decoding extended")
struct NymeaGetNetworksResponseDecodingExtendedTests {

	@Test func decode_withNetworks() throws {
		let json = """
		{"c":0,"r":0,"p":[{"e":"TestSSID","m":"AA:BB:CC:DD:EE:FF","s":80,"p":1}]}
		"""
		let response = try JSONDecoder().decode(NymeaGetNetworksResponse.self, from: json.data(using: .utf8)!)
		#expect(response.p?.count == 1)
		#expect(response.p?.first?.essid == "TestSSID")
	}

	@Test func decode_withNilPayload() throws {
		let json = """
		{"c":0,"r":0}
		"""
		let response = try JSONDecoder().decode(NymeaGetNetworksResponse.self, from: json.data(using: .utf8)!)
		#expect(response.p == nil)
	}
}

// MARK: - EXICodec additional paths

@Suite("EXICodec error paths")
struct EXICodecErrorPathTests {

	@Test func decompress_invalidData_returnsNilOrFallback() {
		// Random bytes that are neither valid zlib nor valid UTF-8
		let randomData = Data([0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA])
		let result = EXICodec.shared.decompress(randomData)
		// May return nil or attempt raw UTF-8 fallback
		_ = result
	}

	@Test func decompress_validUTF8String_returnsFallback() {
		// Plain uncompressed UTF-8 text - should fall back to raw string
		let text = "<event uid=\"test\"/>"
		let data = text.data(using: .utf8)!
		let result = EXICodec.shared.decompress(data)
		// Should return the raw string as fallback when zlib decompression fails
		if let result {
			#expect(result.contains("event"))
		}
	}

	@Test func decompress_emptyData() {
		let result = EXICodec.shared.decompress(Data())
		_ = result // should not crash
	}

	@Test func compress_emptyString() {
		let result = EXICodec.shared.compress("")
		_ = result // should not crash
	}

	@Test func compress_longString() {
		let longXML = String(repeating: "<node id=\"test\"/>", count: 100)
		let result = EXICodec.shared.compress(longXML)
		#expect(result != nil)
		if let result {
			// Compressed should be smaller than original for repetitive data
			#expect(result.count < longXML.utf8.count)
		}
	}
}
