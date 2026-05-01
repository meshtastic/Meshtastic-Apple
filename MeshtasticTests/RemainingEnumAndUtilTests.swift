// RemainingEnumAndUtilTests.swift
// MeshtasticTests

import Testing
import Foundation
import SwiftUI
import MeshtasticProtobufs
@testable import Meshtastic

// MARK: - Aqi Tests

@Suite("Aqi Enum")
struct AqiEnumTests {

	@Test func allCases_count() {
		#expect(Aqi.allCases.count == 6)
	}

	@Test func allCases_haveDescriptions() {
		for aqi in Aqi.allCases {
			#expect(!aqi.description.isEmpty)
		}
	}

	@Test func allCases_haveColors() {
		for aqi in Aqi.allCases {
			_ = aqi.color
		}
	}

	@Test func allCases_haveRanges() {
		for aqi in Aqi.allCases {
			let range = aqi.range
			#expect(!range.isEmpty)
		}
	}

	@Test func getAqi_good() {
		#expect(Aqi.getAqi(for: 25) == .good)
	}

	@Test func getAqi_moderate() {
		#expect(Aqi.getAqi(for: 75) == .moderate)
	}

	@Test func getAqi_sensitive() {
		#expect(Aqi.getAqi(for: 125) == .sensitive)
	}

	@Test func getAqi_unhealthy() {
		#expect(Aqi.getAqi(for: 175) == .unhealthy)
	}

	@Test func getAqi_veryUnhealthy() {
		#expect(Aqi.getAqi(for: 250) == .veryUnhealthy)
	}

	@Test func getAqi_hazardous() {
		#expect(Aqi.getAqi(for: 400) == .hazardous)
	}

	@Test func getAqi_boundaries() {
		#expect(Aqi.getAqi(for: 0) == .good)
		#expect(Aqi.getAqi(for: 50) == .good)
		#expect(Aqi.getAqi(for: 51) == .moderate)
		#expect(Aqi.getAqi(for: 100) == .moderate)
		#expect(Aqi.getAqi(for: 101) == .sensitive)
		#expect(Aqi.getAqi(for: 150) == .sensitive)
		#expect(Aqi.getAqi(for: 151) == .unhealthy)
		#expect(Aqi.getAqi(for: 200) == .unhealthy)
		#expect(Aqi.getAqi(for: 201) == .veryUnhealthy)
		#expect(Aqi.getAqi(for: 300) == .veryUnhealthy)
		#expect(Aqi.getAqi(for: 301) == .hazardous)
		#expect(Aqi.getAqi(for: 500) == .hazardous)
	}

	@Test func identifiable() {
		for aqi in Aqi.allCases {
			#expect(aqi.id == aqi.rawValue)
		}
	}
}

// MARK: - Iaq Tests

@Suite("Iaq Enum Extended")
struct IaqEnumExtendedTests {

	@Test func allCases_count() {
		#expect(Iaq.allCases.count == 7)
	}

	@Test func allCases_haveDescriptions() {
		for iaq in Iaq.allCases {
			#expect(!iaq.description.isEmpty)
		}
	}

	@Test func allCases_haveColors() {
		for iaq in Iaq.allCases {
			_ = iaq.color
		}
	}

	@Test func allCases_haveRanges() {
		for iaq in Iaq.allCases {
			let range = iaq.range
			#expect(!range.isEmpty)
		}
	}

	@Test func getIaq_excellent() {
		#expect(Iaq.getIaq(for: 25) == .excellent)
	}

	@Test func getIaq_good() {
		#expect(Iaq.getIaq(for: 75) == .good)
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

	@Test func getIaq_extremelyPolluted() {
		#expect(Iaq.getIaq(for: 400) == .extremelyPolluted)
	}

	@Test func getIaq_boundaries() {
		#expect(Iaq.getIaq(for: 0) == .excellent)
		#expect(Iaq.getIaq(for: 50) == .excellent)
		#expect(Iaq.getIaq(for: 51) == .good)
		#expect(Iaq.getIaq(for: 100) == .good)
		#expect(Iaq.getIaq(for: 101) == .lightlyPolluted)
		#expect(Iaq.getIaq(for: 150) == .lightlyPolluted)
		#expect(Iaq.getIaq(for: 151) == .moderatelyPolluted)
		#expect(Iaq.getIaq(for: 200) == .moderatelyPolluted)
		#expect(Iaq.getIaq(for: 201) == .heavilyPolluted)
		#expect(Iaq.getIaq(for: 250) == .heavilyPolluted)
		#expect(Iaq.getIaq(for: 251) == .severelyPolluted)
		#expect(Iaq.getIaq(for: 350) == .severelyPolluted)
		#expect(Iaq.getIaq(for: 351) == .extremelyPolluted)
		#expect(Iaq.getIaq(for: 999) == .extremelyPolluted)
	}

	@Test func identifiable() {
		for iaq in Iaq.allCases {
			#expect(iaq.id == iaq.rawValue)
		}
	}
}

// MARK: - EthernetMode Tests

@Suite("EthernetMode Enum")
struct EthernetModeEnumTests {

	@Test func allCases_count() {
		#expect(EthernetMode.allCases.count == 2)
	}

	@Test func descriptions() {
		#expect(EthernetMode.dhcp.description == "DHCP")
		#expect(EthernetMode.staticip.description == "Static IP")
	}

	@Test func protoEnumValues() {
		_ = EthernetMode.dhcp.protoEnumValue()
		_ = EthernetMode.staticip.protoEnumValue()
	}

	@Test func identifiable() {
		#expect(EthernetMode.dhcp.id == 0)
		#expect(EthernetMode.staticip.id == 1)
	}
}

// MARK: - TAKPortNum Tests

@Suite("TAKPortNum Enum")
struct TAKPortNumEnumTests {

	@Test func atakPlugin() {
		#expect(TAKPortNum.atakPlugin.rawValue == 72)
	}

	@Test func atakForwarder() {
		#expect(TAKPortNum.atakForwarder.rawValue == 257)
	}
}

// MARK: - CoTSendMethod Tests

@Suite("CoTSendMethod Classification")
struct CoTSendMethodClassificationTests {

	@Test func pliType_returnsTakPacketPLI() async {
		let cot = CoTMessage(uid: "test", type: "a-f-G-U-C")
		let method = await GenericCoTHandler.shared.classifySendMethod(for: cot)
		if case .takPacketPLI = method {} else {
			Issue.record("Expected .takPacketPLI")
		}
	}

	@Test func pliType_lowercase() async {
		let cot = CoTMessage(uid: "test", type: "a-f-g-u-c")
		let method = await GenericCoTHandler.shared.classifySendMethod(for: cot)
		if case .takPacketPLI = method {} else {
			Issue.record("Expected .takPacketPLI for lowercase")
		}
	}

	@Test func chatType_returnsTakPacketChat() async {
		let cot = CoTMessage(uid: "test", type: "b-t-f")
		let method = await GenericCoTHandler.shared.classifySendMethod(for: cot)
		if case .takPacketChat = method {} else {
			Issue.record("Expected .takPacketChat")
		}
	}

	@Test func genericType_returnsExi() async {
		let cot = CoTMessage(uid: "test", type: "b-m-r")
		let method = await GenericCoTHandler.shared.classifySendMethod(for: cot)
		switch method {
		case .exiDirect, .exiFountain:
			break // expected
		default:
			Issue.record("Expected .exiDirect or .exiFountain for generic type")
		}
	}
}

// MARK: - GenericCoTError Tests

@Suite("GenericCoTError")
struct GenericCoTErrorEnumTests {

	@Test func allCases_haveDescriptions() {
		let errors: [GenericCoTError] = [.notConnected, .noDeviceNumber, .compressionFailed, .encodingFailed]
		for error in errors {
			#expect(error.errorDescription != nil)
			#expect(!error.errorDescription!.isEmpty)
		}
	}

	@Test func notConnected_description() {
		#expect(GenericCoTError.notConnected.errorDescription == "Not connected to Meshtastic device")
	}

	@Test func compressionFailed_description() {
		#expect(GenericCoTError.compressionFailed.errorDescription == "Failed to compress CoT to EXI")
	}
}

// MARK: - SerialConfigEnums Extended Tests

@Suite("SerialConfigEnums Extended")
struct SerialConfigEnumsExtendedTests {

	@Test func baudRates_specificDescriptions() {
		#expect(SerialBaudRates.baud9600.description == "9600 Baud")
		#expect(SerialBaudRates.baud115200.description == "115200 Baud")
		#expect(SerialBaudRates.baud921600.description == "921600 Baud")
	}

	@Test func modeTypes_specificDescriptions() {
		#expect(SerialModeTypes.proto.description.contains("Protobuf"))
		#expect(SerialModeTypes.nmea.description.contains("NMEA"))
		#expect(SerialModeTypes.caltopo.description.contains("CALTOPO"))
	}

	@Test func timeoutIntervals_specificDescriptions() {
		#expect(SerialTimeoutIntervals.fiveSeconds.description.contains("Five"))
		#expect(SerialTimeoutIntervals.oneMinute.description.contains("Minute"))
	}
}

// MARK: - AppSettingsEnums Extended Tests

@Suite("AppSettingsEnums Extended")
struct AppSettingsEnumsExtendedTests {

	@Test func mapTileServer_allCases_haveDescriptions() {
		for server in MapTileServer.allCases {
			#expect(!server.description.isEmpty)
		}
	}

	@Test func mapOverlayServer_allCases_haveDescriptions() {
		for server in MapOverlayServer.allCases {
			#expect(!server.description.isEmpty)
		}
	}

	@Test func mapLayer_allCases_haveLocalized() {
		for layer in MapLayer.allCases {
			#expect(!layer.localized.isEmpty)
		}
	}

	@Test func locationUpdateInterval_allCases_haveDescriptions() {
		for interval in LocationUpdateInterval.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func locationUpdateInterval_identifiable() {
		for interval in LocationUpdateInterval.allCases {
			#expect(interval.id == interval.rawValue)
		}
	}
}

// MARK: - FirmwareFile Enums Tests

@Suite("FirmwareFile FirmwareType")
struct FirmwareFileTypeTests {

	@Test func uf2_rawValue() {
		#expect(FirmwareFile.FirmwareType.uf2.rawValue == ".uf2")
	}

	@Test func bin_rawValue() {
		#expect(FirmwareFile.FirmwareType.bin.rawValue == ".bin")
	}

	@Test func otaZip_rawValue() {
		#expect(FirmwareFile.FirmwareType.otaZip.rawValue == "-ota.zip")
	}

	@Test func description_matchesRawValue() {
		#expect(FirmwareFile.FirmwareType.uf2.description == ".uf2")
		#expect(FirmwareFile.FirmwareType.bin.description == ".bin")
	}

	@Test func identifiable() {
		#expect(FirmwareFile.FirmwareType.uf2.id == ".uf2")
	}
}

// MARK: - FirmwareFileError Tests

@Suite("FirmwareFile FirmwareFileError Extended")
struct FirmwareFileErrorExtendedTests {

	@Test func allErrors_haveDescriptions() {
		let errors: [FirmwareFile.FirmwareFileError] = [
			.invalidFilenamePrefix,
			.parseError,
			.unknownFileType,
			.unknownTarget,
			.unknownArchitecture,
			.unknownVersion,
			.unknownReleaseType,
			.unknownRemoteURL
		]
		for error in errors {
			#expect(error.errorDescription != nil)
			#expect(!error.errorDescription!.isEmpty)
		}
	}

	@Test func invalidFilenamePrefix_description() {
		#expect(FirmwareFile.FirmwareFileError.invalidFilenamePrefix.errorDescription!.contains("firmware-"))
	}
}

// MARK: - FirmwareFile DownloadStatus Tests

@Suite("FirmwareFile DownloadStatus")
struct FirmwareFileDownloadStatusTests {

	@Test func equatable() {
		#expect(FirmwareFile.DownloadStatus.notDownloaded == FirmwareFile.DownloadStatus.notDownloaded)
		#expect(FirmwareFile.DownloadStatus.downloading == FirmwareFile.DownloadStatus.downloading)
		#expect(FirmwareFile.DownloadStatus.downloaded == FirmwareFile.DownloadStatus.downloaded)
		#expect(FirmwareFile.DownloadStatus.error("err") == FirmwareFile.DownloadStatus.error("err"))
		#expect(FirmwareFile.DownloadStatus.error("a") != FirmwareFile.DownloadStatus.error("b"))
		#expect(FirmwareFile.DownloadStatus.notDownloaded != FirmwareFile.DownloadStatus.downloaded)
	}
}

// MARK: - EXICodec Tests Extended

@Suite("EXICodec Extended")
struct EXICodecExtendedTests {

	@Test func compress_decompress_roundTrip() {
		let xml = "<?xml version='1.0'?><event version='2.0' uid='test' type='a-f-G' time='2024-01-01T00:00:00Z' start='2024-01-01T00:00:00Z' stale='2024-01-01T00:10:00Z' how='m-g'><point lat='37.0' lon='-122.0' hae='0' ce='9999999' le='9999999'/><detail/></event>"
		let compressed = EXICodec.shared.compress(xml)
		#expect(compressed != nil)
		if let compressed {
			#expect(compressed.count < xml.count)
			let decompressed = EXICodec.shared.decompress(compressed)
			#expect(decompressed != nil)
			#expect(decompressed == xml)
		}
	}

	@Test func decompress_invalidData_returnsNil() {
		let garbage = Data([0xFF, 0xFE, 0xFD, 0xFC])
		let result = EXICodec.shared.decompress(garbage)
		#expect(result == nil)
	}

	@Test func compress_emptyString() {
		let result = EXICodec.shared.compress("")
		// Empty string should still compress (zlib can handle it)
		#expect(result != nil)
	}
}

// MARK: - String xmlEscaped Extended

@Suite("String xmlEscaped Extended")
struct StringXmlEscapedExtendedTests {

	@Test func allSpecialChars() {
		let input = "&<>\"'"
		let escaped = input.xmlEscaped
		#expect(escaped == "&amp;&lt;&gt;&quot;&apos;")
	}

	@Test func unicodePreserved() {
		let input = "Hello 🌍"
		#expect(input.xmlEscaped == "Hello 🌍")
	}

	@Test func multilinePreserved() {
		let input = "Line1\nLine2"
		#expect(input.xmlEscaped == "Line1\nLine2")
	}
}

// MARK: - CoTMessage.parse roundTrip Tests

@Suite("CoTMessage parse roundTrip")
struct CoTMessageParseRoundTripTests {

	@Test func pli_roundTrip() {
		let original = CoTMessage.pli(
			uid: "roundtrip-uid",
			callsign: "TestUser",
			latitude: 37.7749,
			longitude: -122.4194,
			altitude: 50.0,
			speed: 3.0,
			course: 45.0,
			team: "Green",
			role: "Medic",
			battery: 90
		)
		let xml = original.toXML()
		let parsed = CoTMessage.parse(from: xml)
		#expect(parsed != nil)
		#expect(parsed!.uid == "roundtrip-uid")
		#expect(parsed!.type == "a-f-G-U-C")
		#expect(abs(parsed!.latitude - 37.7749) < 0.0001)
		#expect(abs(parsed!.longitude - (-122.4194)) < 0.0001)
		#expect(parsed!.contact?.callsign == "TestUser")
	}

	@Test func chat_roundTrip() {
		let original = CoTMessage.chat(
			senderUid: "sender-001",
			senderCallsign: "Sender",
			message: "Test message with <special> & 'chars'"
		)
		let xml = original.toXML()
		let parsed = CoTMessage.parse(from: xml)
		#expect(parsed != nil)
		#expect(parsed!.type == "b-t-f")
	}

	@Test func parse_invalidXML_returnsNil() {
		let result = CoTMessage.parse(from: "not xml at all")
		#expect(result == nil)
	}

	@Test func parse_emptyString_returnsNil() {
		let result = CoTMessage.parse(from: "")
		#expect(result == nil)
	}
}

// MARK: - MetricsTypes Tests

@Suite("MetricsTypes Enum")
struct MetricsTypesEnumTests {

	@Test func allCases_count() {
		#expect(MetricsTypes.allCases.count == 5)
	}

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

	@Test func identifiable() {
		for mt in MetricsTypes.allCases {
			#expect(mt.id == mt.rawValue)
		}
	}
}

// MARK: - DisplayEnums Tests

@Suite("DisplayEnums Extended")
struct DisplayEnumsExtendedTests {

	@Test func screenUnits_descriptions() {
		#expect(ScreenUnits.metric.description == "Metric")
		#expect(ScreenUnits.imperial.description == "Imperial")
	}

	@Test func screenUnits_protoEnumValues() {
		_ = ScreenUnits.metric.protoEnumValue()
		_ = ScreenUnits.imperial.protoEnumValue()
	}

	@Test func screenUnits_identifiable() {
		#expect(ScreenUnits.metric.id == 0)
		#expect(ScreenUnits.imperial.id == 1)
	}

	@Test func units_descriptions() {
		#expect(Units.metric.description == "Metric")
		#expect(Units.imperial.description == "Imperial")
	}

	@Test func units_protoEnumValues() {
		_ = Units.metric.protoEnumValue()
		_ = Units.imperial.protoEnumValue()
	}

	@Test func displayModes_allCases_haveDescriptions() {
		for mode in DisplayModes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func displayModes_protoEnumValues() {
		for mode in DisplayModes.allCases {
			_ = mode.protoEnumValue()
		}
	}

	@Test func oledTypes_allCases_haveDescriptions() {
		for oled in OledTypes.allCases {
			#expect(!oled.description.isEmpty)
		}
	}

	@Test func oledTypes_protoEnumValues() {
		for oled in OledTypes.allCases {
			_ = oled.protoEnumValue()
		}
	}

	@Test func screenOnIntervals_allCases_haveDescriptions() {
		for interval in ScreenOnIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func screenCarouselIntervals_allCases_haveDescriptions() {
		for interval in ScreenCarouselIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}
}

// MARK: - TimeZone Extension Tests

@Suite("TimeZone posixDescription Detailed")
struct TimeZonePosixDetailedTests {

	@Test func utc_posixDescription() {
		let tz = TimeZone(identifier: "UTC")!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
	}

	@Test func phoenix_noDST() {
		let tz = TimeZone(identifier: "America/Phoenix")!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
		// Phoenix is MST (GMT-7), no DST
		#expect(posix.contains("7") || posix.contains("MST"))
	}

	@Test func newYork_withDST() {
		let tz = TimeZone(identifier: "America/New_York")!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
		// Should contain DST transition markers
		if tz.nextDaylightSavingTimeTransition != nil {
			#expect(posix.contains(",M"))
		}
	}

	@Test func tokyo_noDST() {
		let tz = TimeZone(identifier: "Asia/Tokyo")!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
		// JST is GMT+9, POSIX inverts so it should be -9
		#expect(posix.contains("-9"))
	}

	@Test func london_withDST() {
		let tz = TimeZone(identifier: "Europe/London")!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
	}

	@Test func kolkata_halfHour() {
		let tz = TimeZone(identifier: "Asia/Kolkata")!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
		// IST is GMT+5:30, POSIX should show -5:30
		#expect(posix.contains(":30"))
	}
}
