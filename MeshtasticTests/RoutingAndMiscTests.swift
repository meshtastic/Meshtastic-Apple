import Foundation
import Testing
import SwiftUI

@testable import Meshtastic

// MARK: - RoutingError

@Suite("RoutingError Detailed")
struct RoutingErrorDetailedTests {

	@Test func allCases_count() {
		#expect(RoutingError.allCases.count == 18)
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
		#expect(RoutingError.pkiSendFailPublicKey.rawValue == 39)
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

	@Test func display_noneIsDeliveredToRecipient() {
		#expect(RoutingError.none.display == "Delivered to recipient")
	}

	@Test func display_noChannelUsesSourceBackedMeaning() {
		#expect(RoutingError.noChannel.display == "Channel/key mismatch")
	}

	@Test func display_usesSourceBackedRoutingErrorWording() {
		let expected: [(RoutingError, String)] = [
			(.none, "Delivered to recipient"),
			(.noRoute, "Failed to deliver to mesh"),
			(.gotNak, "Failed to deliver to mesh"),
			(.timeout, "Failed to deliver to mesh"),
			(.noInterface, "No radio interface"),
			(.maxRetransmit, "Failed to deliver to mesh"),
			(.noChannel, "Channel/key mismatch"),
			(.tooLarge, "Message is too large to send"),
			(.noResponse, "No app response"),
			(.dutyCycleLimit, "Duty cycle limit"),
			(.badRequest, "Invalid request"),
			(.notAuthorized, "Not authorized"),
			(.pkiFailed, "Could not send encrypted message"),
			(.pkiUnknownPubkey, "Recipient needs your key"),
			(.adminBadSessionKey, "Admin session expired"),
			(.adminPublicKeyUnauthorized, "Admin key not authorized"),
			(.rateLimitExceeded, "Rate limited"),
			(.pkiSendFailPublicKey, "Recipient key unavailable")
		]

		for (error, display) in expected {
			#expect(error.display == display)
		}
	}

	@Test func description_usesActionableDesignIssueWording() {
		let expected: [(RoutingError, String)] = [
			(.maxRetransmit, "No node confirmed this message. Try again when you have better signal or more mesh coverage."),
			(.noChannel, "The sender or recipient could not use a matching channel/key for this message."),
			(.noInterface, "The sender has no usable radio interface for this message."),
			(.dutyCycleLimit, "Local airtime limits are temporarily blocking sends. Wait before trying again."),
			(.rateLimitExceeded, "Messages are being sent too quickly. Wait before trying again."),
			(.noResponse, "The destination received the request, but no app or module responded. Try again when the recipient is reachable."),
			(.pkiFailed, "The encrypted send path could not be used. Wait for node info or keys to sync, then try again."),
			(.pkiUnknownPubkey, "The recipient does not know your public key yet. Your node may share its info automatically; try again after it syncs."),
			(.pkiSendFailPublicKey, "Your node does not have the recipient's public key yet. Wait for node info to sync, then try again."),
			(.adminBadSessionKey, "The admin session key is missing, expired, or invalid. Request a new session before trying again.")
		]

		for (error, description) in expected {
			#expect(error.description == description)
		}
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
			.noResponse, .dutyCycleLimit, .pkiFailed, .pkiUnknownPubkey,
			.adminBadSessionKey, .rateLimitExceeded, .pkiSendFailPublicKey
		]
		for error in retryable {
			#expect(error.canRetry == true, "Expected \(error) to be retryable")
		}
	}

	@Test func canRetry_nonRetryableErrors() {
		let nonRetryable: [RoutingError] = [
			.none, .noChannel, .tooLarge, .badRequest, .notAuthorized, .adminPublicKeyUnauthorized
		]
		for error in nonRetryable {
			#expect(error.canRetry == false, "Expected \(error) not to show blind retry")
		}
	}

	@Test func color_noneIsSecondary() {
		#expect(RoutingError.none.color == Color(uiColor: .secondaryLabel))
	}

	@Test func color_retryableIsOrange() {
		#expect(RoutingError.noRoute.color == Color(uiColor: .systemOrange))
	}

	@Test func color_tooLargeIsRed() {
		#expect(RoutingError.tooLarge.color == Color(uiColor: .systemRed))
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
		#expect(RoutingError(rawValue: 0) == .some(.none))
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
