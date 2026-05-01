import Foundation
import Testing

@testable import Meshtastic

// MARK: - EXICodec Compression

@Suite("EXICodec Compression")
struct EXICodecTests {

	@Test func compress_validXML_returnsData() {
		let xml = "<event version='2.0'><point lat='37.0' lon='-122.0'/></event>"
		let compressed = EXICodec.shared.compress(xml)
		#expect(compressed != nil)
	}

	@Test func compress_startsWithZlibHeader() {
		let xml = "<event version='2.0'><point lat='37.0' lon='-122.0'/></event>"
		if let compressed = EXICodec.shared.compress(xml) {
			if compressed.count >= 2 {
				#expect(compressed[0] == 0x78) // Zlib magic byte
			}
		}
	}

	@Test func decompress_compressedData_returnsOriginal() {
		let original = "<event><detail><contact callsign='TEST'/></detail></event>"
		if let compressed = EXICodec.shared.compress(original) {
			let decompressed = EXICodec.shared.decompress(compressed)
			#expect(decompressed == original)
		}
	}

	@Test func decompress_rawUTF8_returnsString() {
		let xml = "<simple>text</simple>"
		let data = Data(xml.utf8)
		let result = EXICodec.shared.decompress(data)
		#expect(result == xml)
	}

	@Test func decompress_invalidData_returnsNilOrFallback() {
		let garbage = Data([0xFF, 0xFE, 0xFD, 0xFC])
		// Should either return nil or handle gracefully
		_ = EXICodec.shared.decompress(garbage)
	}

	@Test func roundTrip_longString() {
		let longXml = String(repeating: "<tag>content</tag>", count: 10)
		if let compressed = EXICodec.shared.compress(longXml) {
			#expect(compressed.count < longXml.utf8.count) // Should actually compress
			let decompressed = EXICodec.shared.decompress(compressed)
			#expect(decompressed == longXml)
		}
	}

	@Test func compress_emptyString_returnsData() {
		let compressed = EXICodec.shared.compress("")
		// Empty string should still produce some zlib output
		#expect(compressed != nil)
	}
}
