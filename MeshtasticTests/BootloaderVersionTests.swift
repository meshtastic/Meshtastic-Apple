//
//  BootloaderVersionTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/24/26.
//

import Testing
import MeshtasticProtobufs
@testable import Meshtastic

/// `DeviceMetadata.bootloader_version` (design#172): installed against latest on the firmware screen.
@Suite("Bootloader version")
struct BootloaderVersionTests {

	private func packed(_ major: UInt32, _ minor: UInt32, _ patch: UInt32) -> UInt32 {
		major << 16 | minor << 8 | patch
	}

	@Test("Zero means not reported")
	func zeroIsNotReported() {
		#expect(BootloaderVersion(packed: 0) == nil)
		#expect(BootloaderStatus(packed: 0, latestTag: "2.6.0") == nil)
	}

	@Test("A packed value decodes to x.y.z")
	func decodesPacked() {
		let version = BootloaderVersion(packed: packed(2, 6, 1))
		#expect(version == BootloaderVersion(major: 2, minor: 6, patch: 1))
		#expect(version?.description == "2.6.1")
	}

	@Test("A 2.6.0 board on the latest release is up to date")
	func currentIsUpToDate() throws {
		let status = try #require(BootloaderStatus(packed: packed(2, 6, 0), latestTag: "2.6.0"))
		#expect(status.installed == .version(BootloaderVersion(major: 2, minor: 6, patch: 0)))
		#expect(status.isUpToDate)
	}

	@Test("A board behind the latest release is not up to date")
	func olderIsNotUpToDate() throws {
		let status = try #require(BootloaderStatus(packed: packed(2, 6, 0), latestTag: "2.7.0"))
		#expect(!status.isUpToDate)
	}

	@Test("0.9.2 reads as older than 2.6.0, never a named release")
	func legacyIsOlder() throws {
		let status = try #require(BootloaderStatus(packed: packed(0, 9, 2), latestTag: "2.6.0"))
		#expect(status.installed == .olderThanFirstReported)
		#expect(!status.isUpToDate)
	}

	@Test("Another version below 2.6.0 shows as itself and is older")
	func otherOldVersion() throws {
		let status = try #require(BootloaderStatus(packed: packed(0, 8, 0), latestTag: "2.6.0"))
		#expect(status.installed == .version(BootloaderVersion(major: 0, minor: 8, patch: 0)))
		#expect(!status.isUpToDate)
	}

	@Test("A latest tag that doesn't parse shows no comparison", arguments: ["", "v2.6.0", "2.6", "2.6.0-beta", "2.6.x"])
	func unparsableLatest(tag: String) throws {
		let status = try #require(BootloaderStatus(packed: packed(2, 6, 0), latestTag: tag))
		#expect(status.latest == nil)
		#expect(!status.isUpToDate)
	}

	@Test("The value is saved from metadata")
	func savedFromMetadata() {
		var metadata = DeviceMetadata()
		metadata.firmwareVersion = "2.8.1.abcdef"
		metadata.bootloaderVersion = packed(2, 6, 0)
		let entity = DeviceMetadataEntity()
		entity.update(from: metadata)
		#expect(entity.bootloaderVersion == Int64(packed(2, 6, 0)))

		metadata.bootloaderVersion = 0
		entity.update(from: metadata)
		#expect(entity.bootloaderVersion == 0)
	}
}
