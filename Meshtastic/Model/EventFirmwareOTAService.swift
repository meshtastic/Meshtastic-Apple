import CryptoKit
import Foundation

enum EventFirmwareOTAUnavailableReason: Equatable, Sendable {
	case contractUnavailable
	case contractEditionMismatch
	case noCompatibleArtifact
	case sourceFirmwareTooOld(String)
	case bootloaderTooOld(String)
	case unsupportedOTAPath
	case untrustedArtifact
}

enum EventFirmwareOTAAvailability: Equatable, Sendable {
	case available(EventFirmwareOTASelection)
	case unavailable(EventFirmwareOTAUnavailableReason)
}

struct EventFirmwareOTAAvailabilityResolver {
	let contract: EventFirmwareOTAContract?
	private let selector: EventFirmwareOTASelector

	init(
		contract: EventFirmwareOTAContract?,
		selector: EventFirmwareOTASelector = EventFirmwareOTASelector()
	) {
		self.contract = contract
		self.selector = selector
	}

	func availability(
		edition: String,
		target: EventFirmwareOTATarget,
		purpose: EventFirmwareOTAInstallPurpose
	) -> EventFirmwareOTAAvailability {
		guard let contract else {
			return .unavailable(.contractUnavailable)
		}
		guard contract.edition == edition else {
			return .unavailable(.contractEditionMismatch)
		}
		do {
			return .available(try selector.select(
				from: contract,
				for: target,
				purpose: purpose
			))
		} catch let error as EventFirmwareOTASelectionError {
			switch error {
			case .noExactTarget, .ambiguousTarget, .incompatibleArtifact:
				return .unavailable(.noCompatibleArtifact)
			case let .sourceFirmwareTooOld(minimum):
				return .unavailable(.sourceFirmwareTooOld(minimum))
			case let .bootloaderTooOld(minimum):
				return .unavailable(.bootloaderTooOld(minimum))
			case .unsupportedOTAPath:
				return .unavailable(.unsupportedOTAPath)
			case .unapprovedArtifactURL:
				return .unavailable(.untrustedArtifact)
			}
		} catch {
			return .unavailable(.noCompatibleArtifact)
		}
	}
}

enum EventFirmwareOTAContractSource {
	static var currentContract: EventFirmwareOTAContract? {
		#if DEBUG && targetEnvironment(simulator)
		return try? EventFirmwareOTADebugFixture.verifiedContract()
		#else
		return nil
		#endif
	}
}

#if DEBUG
enum EventFirmwareOTADebugFixture {
	static let eventPayload = Data("simulated DEFCON event firmware".utf8)
	static let standardPayload = Data("simulated standard Meshtastic firmware".utf8)

	static func verifiedContract() throws -> EventFirmwareOTAContract {
		let privateKey = try Curve25519.Signing.PrivateKey(
			rawRepresentation: Data((0..<32).map(UInt8.init))
		)
		let contract = EventFirmwareOTAContract(
			schemaVersion: 1,
			releaseId: "defcon-34-simulator",
			edition: "DEFCON",
			version: "2.8.0.b00d76f",
			issuedAt: Date(timeIntervalSince1970: 1_750_000_000),
			expiresAt: Date(timeIntervalSince1970: 2_100_000_000),
			artifacts: [
				try artifact(
					name: "event.bin",
					payload: eventPayload
				)
			],
			standardArtifacts: [
				try artifact(
					name: "standard.bin",
					payload: standardPayload
				)
			]
		)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.sortedKeys]
		let payload = try encoder.encode(contract)
		let envelope = EventFirmwareOTAEnvelope(
			keyId: "event-simulator-1",
			payload: payload.base64EncodedString(),
			signature: try privateKey.signature(for: payload).base64EncodedString()
		)
		let envelopeData = try JSONEncoder().encode(envelope)
		return try EventFirmwareOTAContractVerifier(
			trustedKeys: ["event-simulator-1": privateKey.publicKey.rawRepresentation]
		).verify(envelopeData: envelopeData)
	}

	static func payload(for url: URL) -> Data? {
		switch url.lastPathComponent {
		case "event.bin":
			return eventPayload
		case "standard.bin":
			return standardPayload
		default:
			return nil
		}
	}

	private static func artifact(
		name: String,
		payload: Data
	) throws -> EventFirmwareOTAArtifact {
		guard let url = URL(
			string: "https://raw.githubusercontent.com/meshtastic/firmware/" +
				"0123456789abcdef0123456789abcdef01234567/\(name)"
		) else {
			throw URLError(.badURL)
		}
		return EventFirmwareOTAArtifact(
			pioEnv: "tbeam-s3-core",
			hwModel: 12,
			architecture: Architecture.esp32S3.rawValue,
			version: "2.8.0.b00d76f",
			format: .bin,
			url: url,
			sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
			byteCount: Int64(payload.count),
			minimumSourceVersion: "2.7.0",
			partitionRole: "app0",
			partitionScheme: "8MB",
			dfuProtocol: nil,
			minimumBootloaderVersion: nil
		)
	}
}
#endif
