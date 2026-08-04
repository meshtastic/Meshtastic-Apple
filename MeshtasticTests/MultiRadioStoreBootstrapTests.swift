// MultiRadioStoreBootstrapTests.swift
// MeshtasticTests

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Multi-radio store bootstrap", .serialized)
@MainActor
struct MultiRadioStoreBootstrapTests {
	@Test("legacy SwiftData store is split before active store selection")
	func migratesLegacyStoreBeforeSelection() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let paths = RadioStorePaths(applicationSupportDirectory: directory)
		try makeLegacyFixture(at: paths.legacyStoreURL)

		let result = try MultiRadioStoreBootstrap.prepare(
			paths: paths,
			includeCoreDataMigration: false
		)

		let storeKey = try #require(result.selectedStoreKey)
		#expect(result.selectedProfileID != nil)
		#expect(FileManager.default.fileExists(atPath: paths.radioStoreURL(for: storeKey).path))
		#expect(FileManager.default.fileExists(atPath: paths.registryStoreURL.path))
		#expect(!FileManager.default.fileExists(atPath: paths.legacyStoreURL.path))
		#expect(FileManager.default.fileExists(
			atPath: directory.appendingPathComponent("Meshtastic.store-legacy-backup").path
		))
	}

	@Test("fresh install starts without a selected radio")
	func freshInstallHasNoSelection() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let paths = RadioStorePaths(applicationSupportDirectory: directory)

		let result = try MultiRadioStoreBootstrap.prepare(
			paths: paths,
			includeCoreDataMigration: false
		)

		#expect(result == MultiRadioStoreBootstrapResult(
			selectedProfileID: nil,
			selectedStoreKey: nil
		))
		#expect(FileManager.default.fileExists(atPath: paths.registryStoreURL.path))
	}

	private func makeLegacyFixture(at url: URL) throws {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration(url: url, allowsSave: true)
		var container: ModelContainer? = try ModelContainer(
			for: schema,
			migrationPlan: MeshtasticMigrationPlan.self,
			configurations: configuration
		)
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = 42
		myInfo.deviceId = Data([
			0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
			0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff
		])
		myInfo.peripheralId = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
		let node = NodeInfoEntity()
		node.num = 42
		container?.mainContext.insert(myInfo)
		container?.mainContext.insert(node)
		node.myInfo = myInfo
		try container?.mainContext.save()
		container = nil
	}

	private func makeTemporaryDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("MultiRadioStoreBootstrapTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}
}
