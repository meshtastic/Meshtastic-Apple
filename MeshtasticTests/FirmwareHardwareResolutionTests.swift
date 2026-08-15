import Testing

@testable import Meshtastic

@Suite("Firmware hardware resolution")
struct FirmwareHardwareResolutionTests {
	@Test func missingInkHudCatalogTargetUsesHardwareModelMetadata() throws {
		let standard = thinkNodeRecord(target: "thinknode_m1")

		let resolution = try #require(FirmwareHardwareResolver.resolve(
			pioEnv: "thinknode_m1-inkhud",
			hwModel: 89,
			in: [standard]
		))

		#expect(resolution.metadataTarget == "thinknode_m1")
		#expect(resolution.firmwareTarget == "thinknode_m1-inkhud")
	}

	@Test func exactTargetTakesPrecedenceOverHardwareModelFallback() throws {
		let standard = thinkNodeRecord(target: "thinknode_m1")
		let inkHud = thinkNodeRecord(target: "thinknode_m1-inkhud")

		let resolution = try #require(FirmwareHardwareResolver.resolve(
			pioEnv: "thinknode_m1-inkhud",
			hwModel: 89,
			in: [standard, inkHud]
		))

		#expect(resolution.metadataTarget == "thinknode_m1-inkhud")
		#expect(resolution.firmwareTarget == "thinknode_m1-inkhud")
	}

	@Test func resolvesAfterPlatformIOTargetArrives() throws {
		let catalog = [thinkNodeRecord(target: "thinknode_m1")]

		#expect(FirmwareHardwareResolver.resolve(pioEnv: nil, hwModel: 89, in: catalog) == nil)

		let resolution = try #require(FirmwareHardwareResolver.resolve(
			pioEnv: "thinknode_m1-inkhud",
			hwModel: 89,
			in: catalog
		))
		#expect(resolution.firmwareTarget == "thinknode_m1-inkhud")
	}

	@Test func unknownTargetWithoutHardwareModelMetadataDoesNotResolve() {
		let catalog = [thinkNodeRecord(target: "thinknode_m1")]

		#expect(FirmwareHardwareResolver.resolve(
			pioEnv: "unknown-board-inkhud",
			hwModel: 999,
			in: catalog
		) == nil)
	}

	private func thinkNodeRecord(target: String) -> HardwareCatalogRecord {
		HardwareCatalogRecord(
			hwModel: 89,
			hwModelSlug: "THINKNODE_M1",
			platformioTarget: target,
			displayName: "ThinkNode M1",
			activelySupported: true,
			supportLevel: .flagship,
			architecture: "nrf52840"
		)
	}
}

@Suite("Firmware artifact target")
struct FirmwareArtifactTargetTests {
	@Test func usesConnectedNodesExactTargetInsteadOfMetadataFallbackTarget() throws {
		let metadataHardware = DeviceHardwareEntity()
		metadataHardware.platformioTarget = "thinknode_m1"
		metadataHardware.architecture = "nrf52840"

		let release = FirmwareReleaseEntity()
		release.versionId = "v2.8.0"
		release.releaseType = ReleaseType.stable.rawValue

		let firmware = try FirmwareFile(
			firmware: release,
			hardware: metadataHardware,
			platformioTarget: "thinknode_m1-inkhud",
			type: .uf2,
			localeTags: ["ja"]
		)

		#expect(firmware.platformioTarget == "thinknode_m1-inkhud")
		#expect(firmware.localUrl.lastPathComponent == "firmware-thinknode_m1-inkhud-2.8.0.uf2")
		#expect(firmware.remoteUrlCandidates.map(\.lastPathComponent) == [
			"firmware-thinknode_m1-inkhud-2.8.0-ja.uf2",
			"firmware-thinknode_m1-inkhud-2.8.0.uf2"
		])
	}
}
