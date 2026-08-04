// LegacyRadioStoreMigrationTests.swift
// MeshtasticTests

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Legacy radio store migration", .serialized)
@MainActor
struct LegacyRadioStoreMigrationTests {
	@Test("legacy single store moves radio data and global routes without losing its backup")
	func migratesLegacyStore() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let legacyStoreURL = directory.appendingPathComponent("Meshtastic.store")
		try makeLegacyFixture(at: legacyStoreURL)

		let registryContainer = try RadioRegistryController.makeContainer(
			url: directory.appendingPathComponent("RadioRegistry.store")
		)
		let result = try LegacyRadioStoreMigrator.migrate(
			legacyStoreURL: legacyStoreURL,
			radioStoreDirectory: directory.appendingPathComponent("RadioStores", isDirectory: true),
			registryContainer: registryContainer
		)

		#expect(FileManager.default.fileExists(atPath: result.legacyBackupURL.path))
		#expect(!FileManager.default.fileExists(atPath: legacyStoreURL.path))

		let radioContainer = try makeRadioContainer(at: result.radioStoreURL)
		let nodes = try radioContainer.mainContext.fetch(FetchDescriptor<NodeInfoEntity>())
		let myInfos = try radioContainer.mainContext.fetch(FetchDescriptor<MyInfoEntity>())
		let messages = try radioContainer.mainContext.fetch(FetchDescriptor<MessageEntity>())
		#expect(nodes.map(\.num) == [42])
		#expect(nodes.first?.user?.longName == "Legacy user")
		#expect(nodes.first?.positions.map(\.latitudeI) == [987654321])
		#expect(myInfos.map(\.myNodeNum) == [42])
		#expect(myInfos.first?.channels.map(\.name) == ["Legacy channel"])
		#expect(messages.map(\.messagePayload) == ["Legacy message"])
		#expect(messages.first?.fromUser?.num == 42)

		let profiles = try registryContainer.mainContext.fetch(FetchDescriptor<RadioProfileEntity>())
		let metadata = try #require(
			try registryContainer.mainContext.fetch(FetchDescriptor<RadioRegistryMetadataEntity>()).first
		)
		let routes = try registryContainer.mainContext.fetch(FetchDescriptor<RouteEntity>())
		let profile = try #require(profiles.first)
		#expect(profiles.count == 1)
		#expect(profile.id == result.profileID)
		#expect(profile.storeKey == result.storeKey)
		#expect(profile.deviceID == "00112233445566778899aabbccddeeff")
		#expect(profile.nodeNum == 42)
		#expect(metadata.selectedProfileID == profile.id)
		#expect(metadata.legacyMigrationCompletedAt != nil)
		#expect(routes.map(\.name) == ["Legacy route"])
		#expect(routes.first?.locations.map(\.latitudeI) == [123456789])
	}

	@Test("completed migration is idempotent")
	func completedMigrationIsIdempotent() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let legacyStoreURL = directory.appendingPathComponent("Meshtastic.store")
		let radioStoreDirectory = directory.appendingPathComponent("RadioStores", isDirectory: true)
		try makeLegacyFixture(at: legacyStoreURL)
		let registryContainer = try RadioRegistryController.makeContainer(
			url: directory.appendingPathComponent("RadioRegistry.store")
		)

		let first = try LegacyRadioStoreMigrator.migrate(
			legacyStoreURL: legacyStoreURL,
			radioStoreDirectory: radioStoreDirectory,
			registryContainer: registryContainer
		)
		let second = try LegacyRadioStoreMigrator.migrate(
			legacyStoreURL: legacyStoreURL,
			radioStoreDirectory: radioStoreDirectory,
			registryContainer: registryContainer
		)

		#expect(second == first)
		#expect(try registryContainer.mainContext.fetch(FetchDescriptor<RouteEntity>()).count == 1)
		#expect(try registryContainer.mainContext.fetch(FetchDescriptor<RadioProfileEntity>()).count == 1)
	}

	@Test("preexisting backup is never overwritten")
	func preexistingBackupIsNeverOverwritten() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let legacyStoreURL = directory.appendingPathComponent("Meshtastic.store")
		let backupURL = directory.appendingPathComponent("Meshtastic.store-legacy-backup")
		let sentinel = Data("existing-backup".utf8)
		try makeLegacyFixture(at: legacyStoreURL)
		try sentinel.write(to: backupURL)
		let registryContainer = try RadioRegistryController.makeContainer(
			url: directory.appendingPathComponent("RadioRegistry.store")
		)

		var migrationFailed = false
		do {
			_ = try LegacyRadioStoreMigrator.migrate(
				legacyStoreURL: legacyStoreURL,
				radioStoreDirectory: directory.appendingPathComponent("RadioStores", isDirectory: true),
				registryContainer: registryContainer
			)
		} catch {
			migrationFailed = true
		}

		#expect(migrationFailed)
		#expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))
		#expect(try Data(contentsOf: backupURL) == sentinel)
		#expect(try registryContainer.mainContext.fetch(FetchDescriptor<RadioProfileEntity>()).isEmpty)
		#expect(try registryContainer.mainContext.fetch(FetchDescriptor<RadioRegistryMetadataEntity>()).isEmpty)
	}

	@Test("orphaned backup sidecar fails closed")
	func orphanedBackupSidecarFailsClosed() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let legacyStoreURL = directory.appendingPathComponent("Meshtastic.store")
		let orphanedWAL = directory.appendingPathComponent("Meshtastic.store-legacy-backup-wal")
		let sentinel = Data("orphaned-backup-wal".utf8)
		try makeLegacyFixture(at: legacyStoreURL)
		try sentinel.write(to: orphanedWAL)
		let registryContainer = try RadioRegistryController.makeContainer(
			url: directory.appendingPathComponent("RadioRegistry.store")
		)

		var migrationFailed = false
		do {
			_ = try LegacyRadioStoreMigrator.migrate(
				legacyStoreURL: legacyStoreURL,
				radioStoreDirectory: directory.appendingPathComponent("RadioStores", isDirectory: true),
				registryContainer: registryContainer
			)
		} catch {
			migrationFailed = true
		}

		#expect(migrationFailed)
		#expect(try Data(contentsOf: orphanedWAL) == sentinel)
		#expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))
		#expect(try registryContainer.mainContext.fetch(FetchDescriptor<RadioProfileEntity>()).isEmpty)
	}

	@Test("existing radio store is never overwritten")
	func existingRadioStoreIsNeverOverwritten() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let legacyStoreURL = directory.appendingPathComponent("Meshtastic.store")
		let radioStoreDirectory = directory.appendingPathComponent("RadioStores", isDirectory: true)
		try FileManager.default.createDirectory(at: radioStoreDirectory, withIntermediateDirectories: true)
		try makeLegacyFixture(at: legacyStoreURL)
		let registryContainer = try RadioRegistryController.makeContainer(
			url: directory.appendingPathComponent("RadioRegistry.store")
		)
		let registry = try RadioIdentityRegistry(container: registryContainer)
		let resolution = try registry.record(
			RadioIdentityObservation(
				transport: .ble,
				transportDeviceID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
				identifier: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
				deviceID: "00112233445566778899aabbccddeeff",
				nodeNum: 42
			)
		)
		guard case .resolved(let profileID) = resolution else {
			Issue.record("fixture identity did not resolve")
			return
		}
		let profile = try #require(try registry.profiles().first { $0.id == profileID })
		let radioStoreURL = radioStoreDirectory
			.appendingPathComponent(profile.storeKey.uuidString.lowercased())
			.appendingPathExtension("store")
		var existingContainer: ModelContainer? = try makeRadioContainer(at: radioStoreURL)
		let existingNode = NodeInfoEntity()
		existingNode.num = 999
		existingContainer?.mainContext.insert(existingNode)
		try existingContainer?.mainContext.save()
		existingContainer = nil

		var migrationFailed = false
		do {
			_ = try LegacyRadioStoreMigrator.migrate(
				legacyStoreURL: legacyStoreURL,
				radioStoreDirectory: radioStoreDirectory,
				registryContainer: registryContainer
			)
		} catch {
			migrationFailed = true
		}

		let reopened = try makeRadioContainer(at: radioStoreURL)
		let nodes = try reopened.mainContext.fetch(FetchDescriptor<NodeInfoEntity>())
		#expect(migrationFailed)
		#expect(nodes.map(\.num) == [999])
		#expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))
		#expect(try registryContainer.mainContext.fetch(FetchDescriptor<RadioRegistryMetadataEntity>()).isEmpty)
	}

	@Test("started migration resumes after target creation")
	func startedMigrationResumesAfterTargetCreation() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let legacyStoreURL = directory.appendingPathComponent("Meshtastic.store")
		let radioStoreDirectory = directory.appendingPathComponent("RadioStores", isDirectory: true)
		try FileManager.default.createDirectory(at: radioStoreDirectory, withIntermediateDirectories: true)
		try makeLegacyFixture(at: legacyStoreURL)
		let registryContainer = try RadioRegistryController.makeContainer(
			url: directory.appendingPathComponent("RadioRegistry.store")
		)
		let registry = try RadioIdentityRegistry(container: registryContainer)
		let resolution = try registry.record(
			RadioIdentityObservation(
				transport: .ble,
				transportDeviceID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
				identifier: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
				deviceID: "00112233445566778899aabbccddeeff",
				nodeNum: 42
			)
		)
		guard case .resolved(let profileID) = resolution else {
			Issue.record("fixture identity did not resolve")
			return
		}
		let profile = try #require(try registry.profiles().first { $0.id == profileID })
		let metadata = RadioRegistryMetadataEntity()
		metadata.legacyMigrationProfileID = profile.id
		metadata.legacyMigrationStartedAt = Date(timeIntervalSince1970: 1_700_000_000)
		registryContainer.mainContext.insert(metadata)
		try registryContainer.mainContext.save()

		let radioStoreURL = radioStoreDirectory
			.appendingPathComponent(profile.storeKey.uuidString.lowercased())
			.appendingPathExtension("store")
		try copyStoreFiles(from: legacyStoreURL, to: radioStoreURL)
		var partialContainer: ModelContainer? = try makeRadioContainer(at: radioStoreURL)
		_ = try partialContainer?.mainContext.fetch(FetchDescriptor<NodeInfoEntity>())
		partialContainer = nil

		let result = try LegacyRadioStoreMigrator.migrate(
			legacyStoreURL: legacyStoreURL,
			radioStoreDirectory: radioStoreDirectory,
			registryContainer: registryContainer
		)

		#expect(result.profileID == profile.id)
		#expect(FileManager.default.fileExists(atPath: result.legacyBackupURL.path))
		#expect(!FileManager.default.fileExists(atPath: legacyStoreURL.path))
		#expect(metadata.legacyMigrationCompletedAt != nil)
		#expect(try registryContainer.mainContext.fetch(FetchDescriptor<RouteEntity>()).count == 1)
	}

	@Test("completed migration finishes archival after interruption")
	func completedMigrationFinishesArchivalAfterInterruption() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let legacyStoreURL = directory.appendingPathComponent("Meshtastic.store")
		let radioStoreDirectory = directory.appendingPathComponent("RadioStores", isDirectory: true)
		try makeLegacyFixture(at: legacyStoreURL)
		let registryContainer = try RadioRegistryController.makeContainer(
			url: directory.appendingPathComponent("RadioRegistry.store")
		)
		let first = try LegacyRadioStoreMigrator.migrate(
			legacyStoreURL: legacyStoreURL,
			radioStoreDirectory: radioStoreDirectory,
			registryContainer: registryContainer
		)

		try copyStoreFiles(from: first.legacyBackupURL, to: legacyStoreURL)
		let second = try LegacyRadioStoreMigrator.migrate(
			legacyStoreURL: legacyStoreURL,
			radioStoreDirectory: radioStoreDirectory,
			registryContainer: registryContainer
		)

		#expect(second == first)
		#expect(!FileManager.default.fileExists(atPath: legacyStoreURL.path))
		#expect(FileManager.default.fileExists(atPath: first.legacyBackupURL.path))
		#expect(try registryContainer.mainContext.fetch(FetchDescriptor<RouteEntity>()).count == 1)
	}

	@Test("ambiguous legacy identities fail without committing migration")
	func ambiguousLegacyIdentitiesFailClosed() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let legacyStoreURL = directory.appendingPathComponent("Meshtastic.store")
		try makeLegacyFixture(at: legacyStoreURL)
		var legacyContainer: ModelContainer? = try makeLegacyContainer(at: legacyStoreURL)
		let otherMyInfo = MyInfoEntity()
		otherMyInfo.myNodeNum = 43
		otherMyInfo.deviceId = Data([
			0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99, 0x88,
			0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00
		])
		otherMyInfo.peripheralId = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
		legacyContainer?.mainContext.insert(otherMyInfo)
		try legacyContainer?.mainContext.save()
		legacyContainer = nil
		let registryContainer = try RadioRegistryController.makeContainer(
			url: directory.appendingPathComponent("RadioRegistry.store")
		)

		var migrationFailed = false
		do {
			_ = try LegacyRadioStoreMigrator.migrate(
				legacyStoreURL: legacyStoreURL,
				radioStoreDirectory: directory.appendingPathComponent("RadioStores", isDirectory: true),
				registryContainer: registryContainer
			)
		} catch {
			migrationFailed = true
		}

		#expect(migrationFailed)
		#expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))
		#expect(try registryContainer.mainContext.fetch(FetchDescriptor<RadioProfileEntity>()).isEmpty)
		#expect(try registryContainer.mainContext.fetch(FetchDescriptor<RadioRegistryMetadataEntity>()).isEmpty)
	}

	private func makeLegacyFixture(at url: URL) throws {
		var container: ModelContainer? = try makeLegacyContainer(at: url)
		let context = try #require(container?.mainContext)

		let node = NodeInfoEntity()
		node.num = 42
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = 42
		myInfo.deviceId = Data([
			0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
			0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff
		])
		myInfo.peripheralId = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
		let user = UserEntity()
		user.num = 42
		user.longName = "Legacy user"
		let message = MessageEntity()
		message.messageId = 314_159
		message.messagePayload = "Legacy message"
		let channel = ChannelEntity()
		channel.index = 0
		channel.name = "Legacy channel"
		let position = PositionEntity()
		position.latitudeI = 987654321
		let route = RouteEntity()
		route.id = 7
		route.name = "Legacy route"
		let location = LocationEntity()
		location.id = 8
		location.latitudeI = 123456789

		context.insert(node)
		context.insert(myInfo)
		context.insert(user)
		context.insert(message)
		context.insert(channel)
		context.insert(position)
		context.insert(route)
		context.insert(location)
		node.myInfo = myInfo
		node.user = user
		node.positions.append(position)
		myInfo.channels.append(channel)
		message.fromUser = user
		message.toUser = user
		route.locations.append(location)
		try context.save()
		container = nil
	}

	private func makeLegacyContainer(at url: URL) throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration(url: url, allowsSave: true)
		let container = try ModelContainer(
			for: schema,
			migrationPlan: MeshtasticMigrationPlan.self,
			configurations: configuration
		)
		container.mainContext.autosaveEnabled = false
		return container
	}

	private func makeRadioContainer(at url: URL) throws -> ModelContainer {
		let configuration = ModelConfiguration(url: url, allowsSave: true)
		let container = try ModelContainer(
			for: MultiRadioStoreSchema.radioSchema,
			configurations: configuration
		)
		container.mainContext.autosaveEnabled = false
		return container
	}

	private func copyStoreFiles(from source: URL, to destination: URL) throws {
		for suffix in ["", "-shm", "-wal"] {
			let sourceFile = URL(fileURLWithPath: source.path + suffix)
			guard FileManager.default.fileExists(atPath: sourceFile.path) else { continue }
			try FileManager.default.copyItem(
				at: sourceFile,
				to: URL(fileURLWithPath: destination.path + suffix)
			)
		}
	}

	private func makeTemporaryDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LegacyRadioStoreMigrationTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}
}
