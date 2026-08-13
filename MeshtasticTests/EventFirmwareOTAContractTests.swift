// MARK: EventFirmwareOTAContractTests.swift

import CryptoKit
import Foundation
import Testing

@testable import Meshtastic

@Suite("Event firmware OTA contract")
struct EventFirmwareOTAContractTests {

	private struct SignedFixture {
		let keyId: String
		let publicKey: Data
		let envelopeData: Data
	}

	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	@Test func verifiesSignatureBeforeDecodingPayload() throws {
		let fixture = try signedFixture()
		let verifier = EventFirmwareOTAContractVerifier(
			trustedKeys: [fixture.keyId: fixture.publicKey],
			now: { now }
		)

		let contract = try verifier.verify(envelopeData: fixture.envelopeData)

		#expect(contract.schemaVersion == 1)
		#expect(contract.releaseId == "defcon-34-b00d76f")
		#expect(contract.edition == "DEFCON")
		#expect(contract.version == "2.8.0.b00d76f")
	}

	@Test func rejectsTamperedPayload() throws {
		let fixture = try signedFixture()
		var envelope = try JSONDecoder().decode(EventFirmwareOTAEnvelope.self, from: fixture.envelopeData)
		var payload = try #require(Data(base64Encoded: envelope.payload))
		payload[payload.startIndex] ^= 0x01
		envelope.payload = payload.base64EncodedString()
		let tamperedEnvelope = try JSONEncoder().encode(envelope)
		let verifier = EventFirmwareOTAContractVerifier(
			trustedKeys: [fixture.keyId: fixture.publicKey],
			now: { now }
		)

		#expect(throws: EventFirmwareOTAContractError.invalidSignature) {
			try verifier.verify(envelopeData: tamperedEnvelope)
		}
	}

	@Test func rejectsSignatureFromDifferentKey() throws {
		let fixture = try signedFixture()
		let otherKey = try Curve25519.Signing.PrivateKey(
			rawRepresentation: Data((32..<64).map(UInt8.init))
		)
		let verifier = EventFirmwareOTAContractVerifier(
			trustedKeys: [fixture.keyId: otherKey.publicKey.rawRepresentation],
			now: { now }
		)

		#expect(throws: EventFirmwareOTAContractError.invalidSignature) {
			try verifier.verify(envelopeData: fixture.envelopeData)
		}
	}

	@Test func rejectsUnknownKeyIdentifier() throws {
		let fixture = try signedFixture()
		let verifier = EventFirmwareOTAContractVerifier(trustedKeys: [:], now: { now })

		#expect(throws: EventFirmwareOTAContractError.unknownKey("event-fixture-1")) {
			try verifier.verify(envelopeData: fixture.envelopeData)
		}
	}

	@Test func rejectsMalformedBase64BeforePayloadDecode() throws {
		let envelope = EventFirmwareOTAEnvelope(
			keyId: "event-fixture-1",
			payload: "not base64!",
			signature: "also not base64!"
		)
		let verifier = EventFirmwareOTAContractVerifier(
			trustedKeys: ["event-fixture-1": Data(repeating: 0, count: 32)],
			now: { now }
		)

		#expect(throws: EventFirmwareOTAContractError.malformedEnvelope) {
			try verifier.verify(envelopeData: JSONEncoder().encode(envelope))
		}
	}

	@Test func rejectsExpiredContract() throws {
		let fixture = try signedFixture(expiresAt: now.addingTimeInterval(-1))
		let verifier = EventFirmwareOTAContractVerifier(
			trustedKeys: [fixture.keyId: fixture.publicKey],
			now: { now }
		)

		#expect(throws: EventFirmwareOTAContractError.expired) {
			try verifier.verify(envelopeData: fixture.envelopeData)
		}
	}

	@Test func rejectsContractIssuedTooFarInTheFuture() throws {
		let fixture = try signedFixture(
			issuedAt: now.addingTimeInterval(301)
		)
		let verifier = EventFirmwareOTAContractVerifier(
			trustedKeys: [fixture.keyId: fixture.publicKey],
			now: { now }
		)

		#expect(throws: EventFirmwareOTAContractError.notYetValid) {
			try verifier.verify(envelopeData: fixture.envelopeData)
		}
	}

	@Test func rejectsInvertedValidityWindow() throws {
		let issuedAt = now.addingTimeInterval(-60)
		let fixture = try signedFixture(
			issuedAt: issuedAt,
			expiresAt: issuedAt
		)
		let verifier = EventFirmwareOTAContractVerifier(
			trustedKeys: [fixture.keyId: fixture.publicKey],
			now: { now }
		)

		#expect(throws: EventFirmwareOTAContractError.invalidValidityWindow) {
			try verifier.verify(envelopeData: fixture.envelopeData)
		}
	}

	@Test func rejectsUnsupportedSchema() throws {
		let fixture = try signedFixture(schemaVersion: 2)
		let verifier = EventFirmwareOTAContractVerifier(
			trustedKeys: [fixture.keyId: fixture.publicKey],
			now: { now }
		)

		#expect(throws: EventFirmwareOTAContractError.unsupportedSchema(2)) {
			try verifier.verify(envelopeData: fixture.envelopeData)
		}
	}

	private func signedFixture(
		schemaVersion: Int = 1,
		issuedAt: Date? = nil,
		expiresAt: Date? = nil
	) throws -> SignedFixture {
		let privateKey = try Curve25519.Signing.PrivateKey(
			rawRepresentation: Data((0..<32).map(UInt8.init))
		)
		let contract = EventFirmwareOTAContract(
			schemaVersion: schemaVersion,
			releaseId: "defcon-34-b00d76f",
			edition: "DEFCON",
			version: "2.8.0.b00d76f",
			issuedAt: issuedAt ?? now.addingTimeInterval(-60),
			expiresAt: expiresAt ?? now.addingTimeInterval(3_600),
			artifacts: [],
			standardArtifacts: []
		)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.sortedKeys]
		let payload = try encoder.encode(contract)
		let signature = try privateKey.signature(for: payload)
		let keyId = "event-fixture-1"
		let envelope = EventFirmwareOTAEnvelope(
			keyId: keyId,
			payload: payload.base64EncodedString(),
			signature: signature.base64EncodedString()
		)

		return SignedFixture(
			keyId: keyId,
			publicKey: privateKey.publicKey.rawRepresentation,
			envelopeData: try JSONEncoder().encode(envelope)
		)
	}
}
