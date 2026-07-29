import Testing

@testable import Meshtastic

@Suite("Event firmware installer policy")
struct EventFirmwareInstallerViewTests {

	@Test func verifiedSelectionUsesInAppInstall() throws {
		let contract = try EventFirmwareOTADebugFixture.verifiedContract()
		let availability = EventFirmwareOTAAvailabilityResolver(contract: contract).availability(
			edition: "DEFCON",
			target: target(),
			purpose: .event
		)

		#expect(EventFirmwareInstallerPolicy.primaryAction(for: availability) == .install)
	}

	@Test func missingContractUsesWebFlasher() {
		let availability = EventFirmwareOTAAvailability.unavailable(.contractUnavailable)

		#expect(EventFirmwareInstallerPolicy.primaryAction(for: availability) == .webFlasher)
	}

	@Test func unsupportedOTAPathUsesWebFlasher() {
		let availability = EventFirmwareOTAAvailability.unavailable(.unsupportedOTAPath)

		#expect(EventFirmwareInstallerPolicy.primaryAction(for: availability) == .webFlasher)
	}

	@Test func installHandoffRequiresSameConnectedNode() {
		#expect(EventFirmwareInstallerPolicy.isExpectedDeviceActive(
			expectedNodeNum: 123,
			activeNodeNum: 123
		))
		#expect(!EventFirmwareInstallerPolicy.isExpectedDeviceActive(
			expectedNodeNum: 123,
			activeNodeNum: 456
		))
		#expect(!EventFirmwareInstallerPolicy.isExpectedDeviceActive(
			expectedNodeNum: 123,
			activeNodeNum: nil
		))
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
