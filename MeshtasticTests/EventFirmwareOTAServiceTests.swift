import Foundation
import Testing

@testable import Meshtastic

@Suite("Event firmware OTA availability")
struct EventFirmwareOTAServiceTests {

	@Test func productionDisplayMetadataCannotAuthorizeInstall() {
		let displayMetadata = EventFirmwareEntity(edition: "DEFCON")
		displayMetadata.firmwareVersion = "2.8.0.b00d76f"
		displayMetadata.firmwareId = "mutable-display-only-id"
		let resolver = EventFirmwareOTAAvailabilityResolver(contract: nil)

		let availability = resolver.availability(
			edition: displayMetadata.edition,
			target: target(),
			purpose: .event
		)

		#expect(availability == .unavailable(.contractUnavailable))
	}

	@Test func verifiedContractAuthorizesExactTarget() throws {
		let contract = try EventFirmwareOTADebugFixture.verifiedContract()
		let resolver = EventFirmwareOTAAvailabilityResolver(contract: contract)

		let availability = resolver.availability(
			edition: "DEFCON",
			target: target(),
			purpose: .event
		)

		guard case let .available(selection) = availability else {
			Issue.record("Expected the signed DEBUG fixture to authorize its exact target")
			return
		}
		#expect(selection.artifact.format == .bin)
		#expect(selection.purpose == .event)
	}

	@Test func contractForAnotherEditionCannotAuthorizeInstall() throws {
		let resolver = EventFirmwareOTAAvailabilityResolver(
			contract: try EventFirmwareOTADebugFixture.verifiedContract()
		)

		let availability = resolver.availability(
			edition: "BURNING_MAN",
			target: target(),
			purpose: .event
		)

		#expect(availability == .unavailable(.contractEditionMismatch))
	}

	@Test func returnToStandardUsesSignedStandardArtifact() throws {
		let resolver = EventFirmwareOTAAvailabilityResolver(
			contract: try EventFirmwareOTADebugFixture.verifiedContract()
		)

		let availability = resolver.availability(
			edition: "DEFCON",
			target: target(),
			purpose: .standard
		)

		guard case let .available(selection) = availability else {
			Issue.record("Expected a signed return-to-standard artifact")
			return
		}
		#expect(selection.purpose == .standard)
		#expect(selection.artifact.url.lastPathComponent == "standard.bin")
	}

	private func target() -> EventFirmwareOTATarget {
		EventFirmwareOTATarget(
			pioEnv: "tbeam-s3-core",
			hwModel: 12,
			architecture: Architecture.esp32S3.rawValue,
			firmwareVersion: "2.7.26.54e0d8d",
			supportsOTA: true,
			partitionScheme: "8MB",
			bootloaderVersion: nil
		)
	}
}
