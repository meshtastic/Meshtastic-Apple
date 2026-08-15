import Foundation
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

	@Test func platformIOTargetChangeHandlerResolvesFirmwareContent() throws {
		let catalog = [thinkNodeRecord(target: "thinknode_m1")]
		var state = FirmwareHardwareViewState()
		state.resolve(nodeNum: 123, pioEnv: nil, hwModel: 89, in: catalog)
		#expect(state.resolution == nil)

		state.handlePlatformIOTargetChange(
			to: "thinknode_m1-inkhud",
			nodeNum: 123,
			hwModel: 89,
			in: catalog
		)

		let resolution = try #require(state.resolution)
		#expect(resolution.metadataTarget == "thinknode_m1")
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

	@MainActor
	@Test func refreshIncludesLocalFlavorFileUsingMetadataArchitecture() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			"FirmwareHardwareResolutionTests-\(UUID().uuidString)",
			isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let localFile = directory.appendingPathComponent(
			"firmware-thinknode_m1-inkhud-0.0.999999.uf2"
		)
		try Data([0]).write(to: localFile)

		let metadataHardware = DeviceHardwareEntity()
		metadataHardware.platformioTarget = "thinknode_m1"
		metadataHardware.architecture = "nrf52840"
		let viewModel = FirmwareViewModel(
			forHardware: metadataHardware,
			platformioTarget: "thinknode_m1-inkhud",
			localFirmwareStorageURL: directory,
			automaticallyRefresh: false
		)

		viewModel.refresh()

		let firmware = try #require(viewModel.firmwareFiles.first(where: {
			$0.localUrl == localFile
		}))
		#expect(firmware.platformioTarget == "thinknode_m1-inkhud")
		#expect(firmware.architecture == .nrf52840)
		#expect(firmware.status == .downloaded)
	}
}
