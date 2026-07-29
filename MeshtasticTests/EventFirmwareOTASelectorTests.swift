import Foundation
import Testing

@testable import Meshtastic

@Suite("Event firmware OTA selector")
struct EventFirmwareOTASelectorTests {

	@Test func selectsExactESP32Target() throws {
		let expected = try artifact()
		let result = try EventFirmwareOTASelector().select(
			from: contract(artifacts: [expected]),
			for: target(),
			purpose: .event
		)

		#expect(result.artifact == expected)
		#expect(result.purpose == .event)
	}

	@Test func requiresExactPlatformIOEnvironmentAndHardwareModel() throws {
		let wrongEnvironment = try artifact(pioEnv: "t-deck")
		let wrongHardware = try artifact(hwModel: 99)

		#expect(throws: EventFirmwareOTASelectionError.noExactTarget) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [wrongEnvironment, wrongHardware]),
				for: target(),
				purpose: .event
			)
		}
	}

	@Test func requiresExactArchitecture() throws {
		let wrongArchitecture = try artifact(architecture: Architecture.nrf52840.rawValue)

		#expect(throws: EventFirmwareOTASelectionError.noExactTarget) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [wrongArchitecture]),
				for: target(),
				purpose: .event
			)
		}
	}

	@Test func rejectsDuplicateExactTargets() throws {
		let first = try artifact()
		let second = try artifact(
			urlString: "https://raw.githubusercontent.com/meshtastic/firmware/" +
				"0123456789abcdef0123456789abcdef01234567/duplicate.bin"
		)

		#expect(throws: EventFirmwareOTASelectionError.ambiguousTarget) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [first, second]),
				for: target(),
				purpose: .event
			)
		}
	}

	@Test func rejectsSourceFirmwareBelowMinimum() throws {
		let requiresNewer = try artifact(minimumSourceVersion: "2.8.0")

		#expect(throws: EventFirmwareOTASelectionError.sourceFirmwareTooOld(minimum: "2.8.0")) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [requiresNewer]),
				for: target(firmwareVersion: "2.7.26.54e0d8d"),
				purpose: .event
			)
		}
	}

	@Test func rejectsMalformedSourceFirmwareVersion() throws {
		#expect(throws: EventFirmwareOTASelectionError.sourceFirmwareTooOld(minimum: "2.7.0")) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [try artifact()]),
				for: target(firmwareVersion: "2.7.invalid"),
				purpose: .event
			)
		}
	}

	@Test func rejectsOverflowingSourceFirmwareComponent() throws {
		let artifact = try artifact(minimumSourceVersion: "2.0.0")
		let overflow = "999999999999999999999999999999999999999999999999"

		#expect(throws: EventFirmwareOTASelectionError.sourceFirmwareTooOld(minimum: "2.0.0")) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [artifact]),
				for: target(firmwareVersion: "2.\(overflow).0"),
				purpose: .event
			)
		}
	}

	@Test func rejectsTargetWithoutAppSupportedOTAPath() throws {
		#expect(throws: EventFirmwareOTASelectionError.unsupportedOTAPath) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [try artifact()]),
				for: target(supportsOTA: false),
				purpose: .event
			)
		}
	}

	@Test func rejectsMutableRawGitHubURL() throws {
		let mutable = try artifact(
			urlString: "https://raw.githubusercontent.com/meshtastic/meshtastic.github.io/master/event/defcon.bin"
		)

		#expect(throws: EventFirmwareOTASelectionError.unapprovedArtifactURL) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [mutable]),
				for: target(),
				purpose: .event
			)
		}
	}

	@Test func requiresESP32AppPartitionPayload() throws {
		let helperImage = try artifact(partitionRole: "app1")

		#expect(throws: EventFirmwareOTASelectionError.incompatibleArtifact) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [helperImage]),
				for: target(),
				purpose: .event
			)
		}
	}

	@Test func requiresExactESP32PartitionScheme() throws {
		let wrongPartitionScheme = try artifact(partitionScheme: "4MB")

		#expect(throws: EventFirmwareOTASelectionError.incompatibleArtifact) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [wrongPartitionScheme]),
				for: target(),
				purpose: .event
			)
		}
	}

	@Test func rejectsOversizedArtifact() throws {
		let oversized = try artifact(byteCount: 16 * 1_024 * 1_024 + 1)

		#expect(throws: EventFirmwareOTASelectionError.incompatibleArtifact) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [oversized]),
				for: target(),
				purpose: .event
			)
		}
	}

	@Test func rejectsMalformedArtifactVersion() throws {
		let malformed = try artifact(version: "latest")

		#expect(throws: EventFirmwareOTASelectionError.incompatibleArtifact) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [malformed]),
				for: target(),
				purpose: .event
			)
		}
	}

	@Test func validatesNRFProtocolAndBootloaderMinimum() throws {
		let nrfArtifact = try artifact(
			pioEnv: "t-echo",
			hwModel: 8,
			architecture: Architecture.nrf52840.rawValue,
			format: .otaZip,
			partitionRole: nil,
			partitionScheme: nil,
			dfuProtocol: "nordic-legacy",
			minimumBootloaderVersion: "0.6.1"
		)
		let oldBootloader = EventFirmwareOTATarget(
			pioEnv: "t-echo",
			hwModel: 8,
			architecture: Architecture.nrf52840.rawValue,
			firmwareVersion: "2.7.26.54e0d8d",
			supportsOTA: true,
			partitionScheme: nil,
			bootloaderVersion: "0.6.0"
		)

		#expect(throws: EventFirmwareOTASelectionError.bootloaderTooOld(minimum: "0.6.1")) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [nrfArtifact]),
				for: oldBootloader,
				purpose: .event
			)
		}
	}

	@Test func requiresExplicitNRFBootloaderMinimum() throws {
		let nrfArtifact = try artifact(
			pioEnv: "t-echo",
			hwModel: 7,
			architecture: Architecture.nrf52840.rawValue,
			format: .otaZip,
			partitionRole: nil,
			partitionScheme: nil,
			dfuProtocol: "nordic-legacy",
			minimumBootloaderVersion: nil
		)
		let nrfTarget = EventFirmwareOTATarget(
			pioEnv: "t-echo",
			hwModel: 7,
			architecture: Architecture.nrf52840.rawValue,
			firmwareVersion: "2.7.26.54e0d8d",
			supportsOTA: true,
			partitionScheme: nil,
			bootloaderVersion: "0.6.1"
		)

		#expect(throws: EventFirmwareOTASelectionError.incompatibleArtifact) {
			try EventFirmwareOTASelector().select(
				from: contract(artifacts: [nrfArtifact]),
				for: nrfTarget,
				purpose: .event
			)
		}
	}

	@Test func returnToStandardUsesOnlyStandardArtifacts() throws {
		let eventArtifact = try artifact()
		let standardArtifact = try artifact(
			urlString: "https://raw.githubusercontent.com/meshtastic/firmware/0123456789abcdef0123456789abcdef01234567/standard.bin"
		)
		let result = try EventFirmwareOTASelector().select(
			from: contract(artifacts: [eventArtifact], standardArtifacts: [standardArtifact]),
			for: target(),
			purpose: .standard
		)

		#expect(result.artifact == standardArtifact)
		#expect(result.purpose == .standard)
	}

	private func target(
		firmwareVersion: String = "2.7.26.54e0d8d",
		supportsOTA: Bool = true
	) -> EventFirmwareOTATarget {
		EventFirmwareOTATarget(
			pioEnv: "tbeam-s3-core",
			hwModel: 12,
			architecture: Architecture.esp32S3.rawValue,
			firmwareVersion: firmwareVersion,
			supportsOTA: supportsOTA,
			partitionScheme: "8MB",
			bootloaderVersion: nil
		)
	}

	private func contract(
		artifacts: [EventFirmwareOTAArtifact],
		standardArtifacts: [EventFirmwareOTAArtifact] = []
	) -> EventFirmwareOTAContract {
		EventFirmwareOTAContract(
			schemaVersion: 1,
			releaseId: "defcon-34-b00d76f",
			edition: "DEFCON",
			version: "2.8.0.b00d76f",
			issuedAt: .distantPast,
			expiresAt: .distantFuture,
			artifacts: artifacts,
			standardArtifacts: standardArtifacts
		)
	}

	private func artifact(
		pioEnv: String = "tbeam-s3-core",
		hwModel: Int = 12,
		architecture: String = Architecture.esp32S3.rawValue,
		version: String = "2.8.0.b00d76f",
		format: EventFirmwareOTAArtifact.Format = .bin,
		urlString: String =
			"https://raw.githubusercontent.com/meshtastic/meshtastic.github.io/" +
			"0123456789abcdef0123456789abcdef01234567/event/defcon.bin",
		minimumSourceVersion: String = "2.7.0",
		partitionRole: String? = "app0",
		partitionScheme: String? = "8MB",
		dfuProtocol: String? = nil,
		minimumBootloaderVersion: String? = nil,
		byteCount: Int64 = 1_024
	) throws -> EventFirmwareOTAArtifact {
		EventFirmwareOTAArtifact(
			pioEnv: pioEnv,
			hwModel: hwModel,
			architecture: architecture,
			version: version,
			format: format,
			url: try #require(URL(string: urlString)),
			sha256: String(repeating: "a", count: 64),
			byteCount: byteCount,
			minimumSourceVersion: minimumSourceVersion,
			partitionRole: partitionRole,
			partitionScheme: partitionScheme,
			dfuProtocol: dfuProtocol,
			minimumBootloaderVersion: minimumBootloaderVersion
		)
	}
}
