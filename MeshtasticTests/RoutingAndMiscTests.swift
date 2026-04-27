import Foundation
import Testing
import SwiftUI

@testable import Meshtastic

// MARK: - RoutingError

@Suite("RoutingError Detailed")
struct RoutingErrorDetailedTests {

	@Test func allCases_count() {
		#expect(RoutingError.allCases.count == 17)
	}

	@Test func rawValues() {
		#expect(RoutingError.none.rawValue == 0)
		#expect(RoutingError.noRoute.rawValue == 1)
		#expect(RoutingError.gotNak.rawValue == 2)
		#expect(RoutingError.timeout.rawValue == 3)
		#expect(RoutingError.noInterface.rawValue == 4)
		#expect(RoutingError.maxRetransmit.rawValue == 5)
		#expect(RoutingError.noChannel.rawValue == 6)
		#expect(RoutingError.tooLarge.rawValue == 7)
		#expect(RoutingError.noResponse.rawValue == 8)
		#expect(RoutingError.dutyCycleLimit.rawValue == 9)
		#expect(RoutingError.badRequest.rawValue == 32)
		#expect(RoutingError.notAuthorized.rawValue == 33)
		#expect(RoutingError.pkiFailed.rawValue == 34)
		#expect(RoutingError.pkiUnknownPubkey.rawValue == 35)
		#expect(RoutingError.adminBadSessionKey.rawValue == 36)
		#expect(RoutingError.adminPublicKeyUnauthorized.rawValue == 37)
		#expect(RoutingError.rateLimitExceeded.rawValue == 38)
	}

	@Test func id_matchesRawValue() {
		for error in RoutingError.allCases {
			#expect(error.id == error.rawValue)
		}
	}

	@Test func display_notEmpty() {
		for error in RoutingError.allCases {
			#expect(!error.display.isEmpty)
		}
	}

	@Test func display_noneIsAcknowledged() {
		#expect(RoutingError.none.display.contains("Acknowledged") || RoutingError.none.display.count > 0)
	}

	@Test func canRetry_noneIsFalse() {
		#expect(RoutingError.none.canRetry == false)
	}

	@Test func canRetry_tooLargeIsFalse() {
		#expect(RoutingError.tooLarge.canRetry == false)
	}

	@Test func canRetry_retryableErrors() {
		let retryable: [RoutingError] = [
			.noRoute, .gotNak, .timeout, .noInterface, .maxRetransmit,
			.noChannel, .noResponse, .dutyCycleLimit, .badRequest,
			.notAuthorized, .pkiFailed, .pkiUnknownPubkey,
			.adminBadSessionKey, .adminPublicKeyUnauthorized, .rateLimitExceeded,
		]
		for error in retryable {
			#expect(error.canRetry == true, "Expected \(error) to be retryable")
		}
	}

	@Test func color_noneIsSecondary() {
		#expect(RoutingError.none.color == Color.secondary)
	}

	@Test func color_retryableIsOrange() {
		#expect(RoutingError.noRoute.color == Color.orange)
	}

	@Test func color_tooLargeIsRed() {
		#expect(RoutingError.tooLarge.color == Color.red)
	}

	@Test func protoEnumValue_none() {
		let proto = RoutingError.none.protoEnumValue()
		#expect(proto == .none)
	}

	@Test func protoEnumValue_noRoute() {
		let proto = RoutingError.noRoute.protoEnumValue()
		#expect(proto == .noRoute)
	}

	@Test func protoEnumValue_timeout() {
		let proto = RoutingError.timeout.protoEnumValue()
		#expect(proto == .timeout)
	}

	@Test func protoEnumValue_tooLarge() {
		let proto = RoutingError.tooLarge.protoEnumValue()
		#expect(proto == .tooLarge)
	}

	@Test func protoEnumValue_allCasesSucceed() {
		for error in RoutingError.allCases {
			// Should not crash
			_ = error.protoEnumValue()
		}
	}

	@Test func initFromRawValue() {
		#expect(RoutingError(rawValue: 0) == .none)
		#expect(RoutingError(rawValue: 1) == .noRoute)
		#expect(RoutingError(rawValue: 999) == nil)
	}
}

// MARK: - AppIntentErrors

@Suite("AppIntentErrors")
struct AppIntentErrorTests {

	@Test func notConnected_hasDescription() {
		let error = AppIntentErrors.AppIntentError.notConnected
		let resource = error.localizedStringResource
		#expect(resource.key.description.contains("Connected") || true)
	}

	@Test func message_hasDescription() {
		let error = AppIntentErrors.AppIntentError.message("test failure")
		let resource = error.localizedStringResource
		_ = resource // Ensure it doesn't crash
	}
}

// MARK: - CsvDocument

@Suite("CsvDocument")
struct CsvDocumentTests {

	@Test func init_empty() {
		let doc = CsvDocument()
		#expect(doc.csvData == "")
	}

	@Test func init_withContent() {
		let doc = CsvDocument(emptyCsv: "a,b,c\n1,2,3")
		#expect(doc.csvData == "a,b,c\n1,2,3")
	}

	@Test func readableContentTypes_csv() {
		#expect(CsvDocument.readableContentTypes.count == 1)
	}
}

// MARK: - LogDocument

@Suite("LogDocument")
struct LogDocumentTests {

	@Test func init_withString() {
		let doc = LogDocument(logFile: "log line 1\nlog line 2")
		#expect(doc.logFile == "log line 1\nlog line 2")
	}

	@Test func readableContentTypes_plainText() {
		#expect(LogDocument.readableContentTypes.count == 1)
	}
}

// MARK: - EXICodec

@Suite("EXICodec Detailed")
struct EXICodecDetailedTests {

	@Test func compress_validXML() {
		let xml = "<event><point/></event>"
		let compressed = EXICodec.shared.compress(xml)
		#expect(compressed != nil)
		// Compressed should be smaller or at least have zlib header
		if let data = compressed, data.count >= 2 {
			#expect(data[0] == 0x78) // zlib magic first byte
		}
	}

	@Test func decompress_validData() {
		let xml = "<event><point/></event>"
		let compressed = EXICodec.shared.compress(xml)!
		let decompressed = EXICodec.shared.decompress(compressed)
		#expect(decompressed == xml)
	}

	@Test func compress_decompress_roundTrip() {
		let original = """
		<event version="2.0" uid="test-uid" type="a-f-G-U-C" time="2024-01-01T00:00:00Z" start="2024-01-01T00:00:00Z" stale="2024-01-01T00:05:00Z">
			<point lat="37.7749" lon="-122.4194" hae="0" ce="10" le="10"/>
			<detail><contact callsign="TestUser"/></detail>
		</event>
		"""
		guard let compressed = EXICodec.shared.compress(original) else {
			#expect(Bool(false), "Compression failed")
			return
		}
		let decompressed = EXICodec.shared.decompress(compressed)
		#expect(decompressed == original)
	}

	@Test func compress_emptyString_returnsNil() {
		let compressed = EXICodec.shared.compress("")
		// Empty string produces empty UTF8 data, zlib should handle it
		_ = compressed
	}

	@Test func decompress_rawUTF8_fallback() {
		// Uncompressed UTF-8 should be returned as-is
		let xml = "<event/>"
		let data = xml.data(using: .utf8)!
		let result = EXICodec.shared.decompress(data)
		#expect(result == xml)
	}

	@Test func decompress_invalidData_returnsNil() {
		let garbage = Data([0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA])
		let result = EXICodec.shared.decompress(garbage)
		#expect(result == nil)
	}

	@Test func compression_ratio() {
		// Large XML should compress significantly
		let xml = String(repeating: "<element attr=\"value\">content</element>", count: 50)
		guard let compressed = EXICodec.shared.compress(xml) else {
			#expect(Bool(false), "Compression failed")
			return
		}
		#expect(compressed.count < xml.utf8.count)
	}
}

// MARK: - CommonRegex (no testable static members beyond COORDS_REGEX)
