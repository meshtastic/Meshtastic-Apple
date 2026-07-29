import CryptoKit
import Foundation

struct EventFirmwareOTAEnvelope: Codable, Equatable, Sendable {
	var keyId: String
	var payload: String
	var signature: String
}

struct EventFirmwareOTAContract: Codable, Equatable, Sendable {
	let schemaVersion: Int
	let releaseId: String
	let edition: String
	let version: String
	let issuedAt: Date
	let expiresAt: Date
	let artifacts: [EventFirmwareOTAArtifact]
	let standardArtifacts: [EventFirmwareOTAArtifact]
}

struct EventFirmwareOTAArtifact: Codable, Equatable, Sendable {
	enum Format: String, Codable, Sendable {
		case bin
		case otaZip
	}

	let pioEnv: String
	let hwModel: Int
	let architecture: String
	let format: Format
	let url: URL
	let sha256: String
	let byteCount: Int64
	let minimumSourceVersion: String
	let partitionRole: String?
	let partitionScheme: String?
	let dfuProtocol: String?
	let minimumBootloaderVersion: String?
}

enum EventFirmwareOTAContractError: Error, Equatable {
	case malformedEnvelope
	case unknownKey(String)
	case invalidTrustedKey
	case invalidSignature
	case invalidPayload
	case unsupportedSchema(Int)
	case notYetValid
	case invalidValidityWindow
	case expired
}

struct EventFirmwareOTAContractVerifier {
	private let trustedKeys: [String: Data]
	private let now: () -> Date

	init(
		trustedKeys: [String: Data],
		now: @escaping () -> Date = Date.init
	) {
		self.trustedKeys = trustedKeys
		self.now = now
	}

	func verify(envelopeData: Data) throws -> EventFirmwareOTAContract {
		let envelope: EventFirmwareOTAEnvelope
		do {
			envelope = try JSONDecoder().decode(EventFirmwareOTAEnvelope.self, from: envelopeData)
		} catch {
			throw EventFirmwareOTAContractError.malformedEnvelope
		}

		guard let payload = Data(base64Encoded: envelope.payload),
			  let signature = Data(base64Encoded: envelope.signature) else {
			throw EventFirmwareOTAContractError.malformedEnvelope
		}
		guard let trustedKey = trustedKeys[envelope.keyId] else {
			throw EventFirmwareOTAContractError.unknownKey(envelope.keyId)
		}

		let publicKey: Curve25519.Signing.PublicKey
		do {
			publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: trustedKey)
		} catch {
			throw EventFirmwareOTAContractError.invalidTrustedKey
		}
		guard publicKey.isValidSignature(signature, for: payload) else {
			throw EventFirmwareOTAContractError.invalidSignature
		}

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let contract: EventFirmwareOTAContract
		do {
			contract = try decoder.decode(EventFirmwareOTAContract.self, from: payload)
		} catch {
			throw EventFirmwareOTAContractError.invalidPayload
		}

		guard contract.schemaVersion == 1 else {
			throw EventFirmwareOTAContractError.unsupportedSchema(contract.schemaVersion)
		}
		guard contract.expiresAt > contract.issuedAt else {
			throw EventFirmwareOTAContractError.invalidValidityWindow
		}
		let verificationDate = now()
		guard contract.issuedAt <= verificationDate.addingTimeInterval(300) else {
			throw EventFirmwareOTAContractError.notYetValid
		}
		guard contract.expiresAt > verificationDate else {
			throw EventFirmwareOTAContractError.expired
		}
		return contract
	}
}
