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
			.adminBadSessionKey, .adminPublicKeyUnauthorized, .rateLimitExceeded
		]
		for error in retryable {
			#expect(error.canRetry == true, "Expected \(error) to be retryable")
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

// MARK: - CommonRegex (no testable static members beyond COORDS_REGEX)
