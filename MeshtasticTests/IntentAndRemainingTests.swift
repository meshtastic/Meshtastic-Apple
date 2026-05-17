// IntentAndRemainingTests.swift
// MeshtasticTests

import Testing
import Foundation
import SwiftUI
@testable import Meshtastic

// MARK: - EXICodec Compression Detailed

@Suite("EXICodec Compression Detailed")
struct EXICodecCompressionDetailedTests {

	@Test func compress_variousXMLSizes() {
		// Small XML
		let small = "<event/>"
		let smallResult = EXICodec.shared.compress(small)
		#expect(smallResult != nil)

		// Medium XML
		let medium = """
		<?xml version='1.0'?><event version="2.0" uid="test-medium" type="a-f-G-U-C" time="2024-01-01T00:00:00Z" start="2024-01-01T00:00:00Z" stale="2024-01-01T00:10:00Z" how="m-g"><point lat="37.7749" lon="-122.4194" hae="50" ce="9999999" le="9999999"/><detail><contact callsign="TestUser"/><__group name="Cyan" role="Team Member"/><track speed="1.5" course="270.0"/><status battery="85"/></detail></event>
		"""
		let medResult = EXICodec.shared.compress(medium)
		#expect(medResult != nil)
		if let medResult {
			#expect(medResult.count < medium.count)
		}
	}

	@Test func decompress_compressedData_roundTrip() {
		let original = "<event version=\"2.0\" uid=\"roundtrip\"/>"
		if let compressed = EXICodec.shared.compress(original) {
			let decompressed = EXICodec.shared.decompress(compressed)
			#expect(decompressed == original)
		}
	}

	@Test func compress_specialCharacters() {
		let xml = "<event note=\"Hello &amp; goodbye\"/>"
		let result = EXICodec.shared.compress(xml)
		#expect(result != nil)
	}

	@Test func compress_unicodeContent() {
		let xml = "<event note=\"こんにちは 🌍\"/>"
		let result = EXICodec.shared.compress(xml)
		#expect(result != nil)
	}
}

// MARK: - LogDocument Tests

@Suite("LogDocument Extended")
struct LogDocumentExtendedTests {

	@Test func init_withLogFile() {
		let doc = LogDocument(logFile: "test log content")
		#expect(doc.logFile == "test log content")
	}

	@Test func init_emptyLogFile() {
		let doc = LogDocument(logFile: "")
		#expect(doc.logFile == "")
	}
}

// MARK: - Bundle Extension Additional

@Suite("Bundle Extension Additional")
struct BundleExtensionAdditionalTests {

	@Test func mainBundle_hasBundleIdentifier() {
		let bundleId = Bundle.main.bundleIdentifier
		#expect(bundleId != nil)
	}
}

// MARK: - ConfigPresets Extended (additional tests)

@Suite("ConfigPresets Extended")
struct ConfigPresetsExtendedTests {

	@Test func specificDescriptions() {
		#expect(ConfigPresets.rakRotaryEncoder.description.contains("RAK"))
		#expect(ConfigPresets.cardKB.description.contains("KB"))
	}

	@Test func rawValues() {
		#expect(ConfigPresets.unset.rawValue == 0)
		#expect(ConfigPresets.rakRotaryEncoder.rawValue == 1)
		#expect(ConfigPresets.cardKB.rawValue == 2)
	}
}

// MARK: - InputEventChars Extended

@Suite("InputEventChars Extended")
struct InputEventCharsExtendedTests {

	@Test func specificRawValues() {
		#expect(InputEventChars.none.rawValue == 0)
		#expect(InputEventChars.up.rawValue == 17)
		#expect(InputEventChars.down.rawValue == 18)
		#expect(InputEventChars.left.rawValue == 19)
		#expect(InputEventChars.right.rawValue == 20)
		#expect(InputEventChars.select.rawValue == 10)
		#expect(InputEventChars.back.rawValue == 27)
		#expect(InputEventChars.cancel.rawValue == 24)
	}

	@Test func descriptions_forNavigation() {
		#expect(InputEventChars.up.description.contains("Up"))
		#expect(InputEventChars.down.description.contains("Down"))
		#expect(InputEventChars.left.description.contains("Left"))
		#expect(InputEventChars.right.description.contains("Right"))
	}
}

// MARK: - Color Extension Coverage

@Suite("Color Extension Coverage")
struct ColorExtensionCoverageTests {

	@Test func hex_colors() {
		// Exercise the Color(hex:) initializer with String
		let red = Color(hex: "FF0000")
		_ = red
		let green = Color(hex: "00FF00")
		_ = green
		let blue = Color(hex: "0000FF")
		_ = blue
		let white = Color(hex: "FFFFFF")
		_ = white
		let black = Color(hex: "000000")
		_ = black
	}
}

// MARK: - MeshtasticAPI additional

@Suite("MeshtasticAPI Helpers")
struct MeshtasticAPIHelperTests {

	@Test func architecture_decodableFromString() throws {
		let json = "\"esp32\""
		let data = json.data(using: .utf8)!
		let arch = try JSONDecoder().decode(Architecture.self, from: data)
		#expect(arch == .esp32)
	}

	@Test func architecture_allCases() {
		let all: [Architecture] = [.esp32, .esp32C3, .esp32S3, .nrf52840, .rp2040, .esp32C6]
		#expect(all.count == 6)
		for arch in all {
			#expect(!arch.rawValue.isEmpty)
		}
	}

	@Test func releaseType_decodable() {
		#expect(ReleaseType(rawValue: "Stable") == .stable)
		#expect(ReleaseType(rawValue: "Alpha") == .alpha)
		#expect(ReleaseType(rawValue: "Unlisted") == .unlisted)
		#expect(ReleaseType(rawValue: "Invalid") == nil)
	}
}
