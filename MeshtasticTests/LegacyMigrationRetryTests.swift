import CoreData
import SwiftData
import XCTest
@testable import Meshtastic

final class LegacyMigrationRetryTests: XCTestCase {
	private let storeMembers: [CoreDataMigrationService.StoreMember] = [.wal, .shm, .main]
	private var temporaryDirectory: URL!

	override func setUpWithError() throws {
		try super.setUpWithError()
		temporaryDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LegacyMigrationRetryTests-")
			.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
	}

	override func tearDownWithError() throws {
		if let temporaryDirectory {
			try? FileManager.default.removeItem(at: temporaryDirectory)
		}
		try super.tearDownWithError()
	}

	@MainActor
	func testRetryAfterParentSave() throws {
		let (locations, container) = try makeScenario()

		try interruptMigration(at: .afterParentSave, container: container, locations: locations)
		XCTAssertTrue(CoreDataMigrationService.legacyStoreExists(at: locations))
		XCTAssertEqual(
			try migrationCounts(in: container),
			MigrationCounts(messages: 0, positions: 0, telemetry: 0, channels: 1, deviceConfigs: 1)
		)

		try completeMigration(container: container, locations: locations)
		try assertFinalState(container: container, locations: locations)
	}

	@MainActor
	func testRetryAfterEveryHistoryBatch() throws {
		let checkpoints: [(CoreDataMigrationService.MigrationCheckpoint, MigrationCounts)] = [
			(.afterHistoryBatch(.messages, index: 0), .init(messages: 1, positions: 0, telemetry: 0, channels: 1, deviceConfigs: 1)),
			(.afterHistoryBatch(.messages, index: 1), .init(messages: 2, positions: 0, telemetry: 0, channels: 1, deviceConfigs: 1)),
			(.afterHistoryBatch(.positions, index: 0), .init(messages: 2, positions: 1, telemetry: 0, channels: 1, deviceConfigs: 1)),
			(.afterHistoryBatch(.positions, index: 1), .init(messages: 2, positions: 2, telemetry: 0, channels: 1, deviceConfigs: 1)),
			(.afterHistoryBatch(.positions, index: 2), .init(messages: 2, positions: 3, telemetry: 0, channels: 1, deviceConfigs: 1)),
			(.afterHistoryBatch(.telemetry, index: 0), .init(messages: 2, positions: 3, telemetry: 1, channels: 1, deviceConfigs: 1)),
			(.afterHistoryBatch(.telemetry, index: 1), .init(messages: 2, positions: 3, telemetry: 2, channels: 1, deviceConfigs: 1))
		]

		for (checkpoint, expectedCounts) in checkpoints {
			let (locations, container) = try makeScenario()
			try interruptMigration(at: checkpoint, container: container, locations: locations)
			XCTAssertTrue(CoreDataMigrationService.legacyStoreExists(at: locations), "checkpoint: \(checkpoint)")
			XCTAssertEqual(try migrationCounts(in: container), expectedCounts, "checkpoint: \(checkpoint)")

			try completeMigration(container: container, locations: locations)
			try assertFinalState(container: container, locations: locations)
		}
	}

	@MainActor
	func testRetryAfterMessageScalarsRepairsRelationships() throws {
		let (locations, container) = try makeScenario()

		try interruptMigration(at: .afterMessageScalarPersistence, container: container, locations: locations)
		let interruptedMessages = try container.mainContext.fetch(FetchDescriptor<MessageEntity>())
		XCTAssertEqual(Set(interruptedMessages.map(\.messageId)), [1001, 1002])
		XCTAssertTrue(interruptedMessages.allSatisfy { $0.fromUser == nil && $0.toUser == nil })

		try completeMigration(container: container, locations: locations)
		try assertFinalState(container: container, locations: locations)
	}

	@MainActor
	func testRetryAfterMessageUserLinkDoesNotDuplicateMessages() throws {
		let (locations, container) = try makeScenario()

		try interruptMigration(at: .afterMessageUserLink(nodeNum: 111), container: container, locations: locations)
		let linkedMessages = try container.mainContext.fetch(FetchDescriptor<MessageEntity>())
		XCTAssertEqual(linkedMessages.count, 2)
		XCTAssertTrue(linkedMessages.allSatisfy { $0.fromUser?.num == 111 && $0.toUser?.num == 111 })

		try completeMigration(container: container, locations: locations)
		try assertFinalState(container: container, locations: locations)
	}

	@MainActor
	func testPrepareRetriesAfterEveryStoreMove() throws {
		for member in storeMembers {
			let locations = try makeLocations()
			try buildLegacyStore(at: locations.candidateStoreURL)
			try Data().write(to: sidecar(of: locations.candidateStoreURL, suffix: "-wal"))
			try Data().write(to: sidecar(of: locations.candidateStoreURL, suffix: "-shm"))

			XCTAssertThrowsError(
				try CoreDataMigrationService.prepareForMigration(
					locations: locations,
					options: .init(checkpoint: { checkpoint in
						if checkpoint == .afterPrepareMove(member) { throw TestInterruption() }
					})
				)
			)
			XCTAssertEqual(
				CoreDataMigrationService.legacyStoreExists(at: locations),
				member == .main,
				"member: \(member)"
			)

			try CoreDataMigrationService.prepareForMigration(locations: locations)
			XCTAssertTrue(CoreDataMigrationService.legacyStoreExists(at: locations), "member: \(member)")
			XCTAssertFalse(FileManager.default.fileExists(atPath: locations.candidateStoreURL.path), "member: \(member)")

			let container = try makeDestinationContainer(at: locations)
			try completeMigration(container: container, locations: locations)
			try assertFinalState(container: container, locations: locations)
		}
	}

	@MainActor
	func testRetirementRetriesAfterEveryStoreMove() throws {
		for member in storeMembers {
			let (locations, container) = try makeScenario()
			let legacyWAL = sidecar(of: locations.legacyStoreURL, suffix: "-wal")
			let legacySHM = sidecar(of: locations.legacyStoreURL, suffix: "-shm")

			XCTAssertThrowsError(
				try CoreDataMigrationService.migrate(
					into: container,
					locations: locations,
					options: .init(
						batchSize: 1,
						checkpoint: { checkpoint in
							if checkpoint == .beforeRetirement {
								try Data().write(to: legacyWAL)
								try Data().write(to: legacySHM)
							}
							if checkpoint == .afterRetirementMove(member) {
								throw TestInterruption()
							}
						}
					)
				)
			)
			XCTAssertEqual(
				CoreDataMigrationService.legacyStoreExists(at: locations),
				member != .main,
				"member: \(member)"
			)

			if CoreDataMigrationService.legacyStoreExists(at: locations) {
				try completeMigration(container: container, locations: locations)
			} else {
				try CoreDataMigrationService.prepareForMigration(locations: locations)
			}
			XCTAssertFalse(FileManager.default.fileExists(atPath: locations.retirementMarkerURL.path))
			try assertFinalState(container: container, locations: locations)
		}
	}

	@MainActor
	func testRetirementCollisionWithoutMarkerFailsClosed() throws {
		let (locations, container) = try makeScenario()
		let backupWAL = sidecar(of: locations.backupStoreURL, suffix: "-wal")
		try Data("collision".utf8).write(to: backupWAL)

		XCTAssertThrowsError(
			try CoreDataMigrationService.migrate(
				into: container,
				locations: locations,
				options: .init(batchSize: 1)
			)
		)
		XCTAssertTrue(CoreDataMigrationService.legacyStoreExists(at: locations))
		XCTAssertFalse(FileManager.default.fileExists(atPath: locations.retirementMarkerURL.path))

		try FileManager.default.removeItem(at: backupWAL)
		try completeMigration(container: container, locations: locations)
		try assertFinalState(container: container, locations: locations)
	}

	@MainActor
	func testRetryAfterCommittedDataBeforeRetirementDoesNotDuplicateHistory() throws {
		let (locations, container) = try makeScenario()

		try interruptMigration(at: .beforeRetirement, container: container, locations: locations)
		XCTAssertTrue(CoreDataMigrationService.legacyStoreExists(at: locations))
		XCTAssertEqual(try migrationCounts(in: container), .final)

		try completeMigration(container: container, locations: locations)
		try assertFinalState(container: container, locations: locations)
	}

	@MainActor
	func testBootstrapRetryCompletesAnInterruptedMigration() async throws {
		let (locations, container) = try makeScenario()
		let interruptionMarkerURL = locations.applicationSupportURL.appendingPathComponent("did-interrupt")
		let bootstrap = PersistenceBootstrap(loader: {
			try CoreDataMigrationService.migrate(
				into: container,
				locations: locations,
				options: .init(
					batchSize: 1,
					checkpoint: { checkpoint in
						if checkpoint == .afterParentSave,
						   !FileManager.default.fileExists(atPath: interruptionMarkerURL.path) {
							try Data().write(to: interruptionMarkerURL)
							throw TestInterruption()
						}
					}
				)
			)
			return PersistenceController(inMemory: true)
		})

		await bootstrap.start()
		guard case .failed = bootstrap.state else {
			return XCTFail("Expected the checkpoint interruption to fail bootstrap")
		}
		XCTAssertTrue(CoreDataMigrationService.legacyStoreExists(at: locations))

		await bootstrap.retry()
		XCTAssertEqual(bootstrap.state, .ready)
		try assertFinalState(container: container, locations: locations)
	}

	@MainActor
	private func interruptMigration(
		at target: CoreDataMigrationService.MigrationCheckpoint,
		container: ModelContainer,
		locations: CoreDataMigrationService.StoreLocations
	) throws {
		XCTAssertThrowsError(
			try CoreDataMigrationService.migrate(
				into: container,
				locations: locations,
				options: .init(
					batchSize: 1,
					checkpoint: { checkpoint in
						if checkpoint == target { throw TestInterruption() }
					}
				)
			)
		)
	}

	@MainActor
	private func completeMigration(
		container: ModelContainer,
		locations: CoreDataMigrationService.StoreLocations
	) throws {
		try CoreDataMigrationService.migrate(
			into: container,
			locations: locations,
			options: .init(batchSize: 1)
		)
	}

	@MainActor
	private func makeScenario() throws -> (CoreDataMigrationService.StoreLocations, ModelContainer) {
		let locations = try makeLocations()
		try buildLegacyStore(at: locations.legacyStoreURL)
		return (locations, try makeDestinationContainer(at: locations))
	}

	private func makeLocations() throws -> CoreDataMigrationService.StoreLocations {
		let root = temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return CoreDataMigrationService.StoreLocations(applicationSupportURL: root)
	}

	@MainActor
	private func makeDestinationContainer(
		at locations: CoreDataMigrationService.StoreLocations
	) throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration(url: locations.destinationStoreURL, allowsSave: true)
		let container = try ModelContainer(
			for: schema,
			migrationPlan: MeshtasticMigrationPlan.self,
			configurations: configuration
		)
		container.mainContext.autosaveEnabled = false
		return container
	}

	@MainActor
	private func migrationCounts(in container: ModelContainer) throws -> MigrationCounts {
		MigrationCounts(
			messages: try container.mainContext.fetchCount(FetchDescriptor<MessageEntity>()),
			positions: try container.mainContext.fetchCount(FetchDescriptor<PositionEntity>()),
			telemetry: try container.mainContext.fetchCount(FetchDescriptor<TelemetryEntity>()),
			channels: try container.mainContext.fetchCount(FetchDescriptor<ChannelEntity>()),
			deviceConfigs: try container.mainContext.fetchCount(FetchDescriptor<DeviceConfigEntity>())
		)
	}

	@MainActor
	private func assertFinalState(
		container: ModelContainer,
		locations: CoreDataMigrationService.StoreLocations
	) throws {
		XCTAssertEqual(try migrationCounts(in: container), .final)
		XCTAssertFalse(CoreDataMigrationService.legacyStoreExists(at: locations))
		XCTAssertTrue(FileManager.default.fileExists(atPath: locations.backupStoreURL.path))

		let messages = try container.mainContext.fetch(FetchDescriptor<MessageEntity>())
		XCTAssertEqual(Set(messages.map(\.messageId)), [1001, 1002])
		XCTAssertTrue(messages.allSatisfy { $0.fromUser?.num == 111 && $0.toUser?.num == 111 })
		XCTAssertTrue(messages.allSatisfy {
			$0.messagePayloadMarkdown == "markdown" &&
			$0.messagePayloadTranslated == "translated" &&
			$0.messagePayloadTranslatedMarkdown == "translated markdown" &&
			$0.pkiEncrypted && $0.portNum == 1 && $0.publicKey == Data([1, 2, 3]) &&
			$0.read && $0.realACK && $0.relayNode == 9 && $0.relays == 2 &&
			$0.rssi == -80 && $0.showTranslatedMessage
		})

		let positions = try container.mainContext.fetch(FetchDescriptor<PositionEntity>())
		XCTAssertTrue(positions.allSatisfy {
			$0.nodePosition?.num == 111 && $0.precisionBits == 17 && $0.rssi == -42
		})
		XCTAssertEqual(positions.filter(\.latest).count, 1)
		XCTAssertEqual(
			positions.filter {
				$0.latitudeI == 37_000_000 && $0.time == Date(timeIntervalSince1970: 1_700_000_001)
			}.count,
			2
		)

		let telemetry = try container.mainContext.fetch(FetchDescriptor<TelemetryEntity>())
		XCTAssertTrue(telemetry.allSatisfy {
			$0.nodeTelemetry?.num == 111 &&
			$0.numOnlineNodes == 2 && $0.numPacketsRx == 3 && $0.numPacketsRxBad == 4 &&
			$0.numPacketsTx == 5 && $0.numRxDupe == 6 && $0.numTotalNodes == 7 &&
			$0.numTxRelay == 8 && $0.numTxRelayCanceled == 9 &&
			$0.irLux == 10.5 && $0.lux == 11.5 && $0.radiation == 12.5 &&
			$0.soilMoisture == 4_000_000_000 && $0.windSpeed == 13.5
		})
		XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<ChannelEntity>()).first?.name, "LegacyChan")
		XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<DeviceConfigEntity>()).first?.role, 5)
	}

	private func sidecar(of storeURL: URL, suffix: String) -> URL {
		storeURL.deletingPathExtension().appendingPathExtension("sqlite\(suffix)")
	}

	private func buildLegacyStore(at storeURL: URL) throws {
		let momdURL = try XCTUnwrap(Bundle.main.url(forResource: "Meshtastic", withExtension: "momd"))
		let modelURL = momdURL.appendingPathComponent("MeshtasticDataModelV 58.mom")
		let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
		let container = NSPersistentContainer(name: "Meshtastic", managedObjectModel: model)
		let description = NSPersistentStoreDescription(url: storeURL)
		description.shouldAddStoreAsynchronously = false
		container.persistentStoreDescriptions = [description]
		var loadError: Error?
		container.loadPersistentStores { _, error in loadError = error }
		if let loadError { throw loadError }

		let context = container.viewContext
		func insert(_ entityName: String) -> NSManagedObject {
			NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
		}

		let node = insert("NodeInfoEntity")
		node.setValue(Int64(111), forKey: "num")
		node.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "lastHeard")

		let user = insert("UserEntity")
		user.setValue(Int64(111), forKey: "num")
		user.setValue("TEST", forKey: "hwModel")
		user.setValue("Legacy User", forKey: "longName")
		user.setValue("LU", forKey: "shortName")
		user.setValue("!0000006f", forKey: "userId")
		user.setValue(node, forKey: "userNode")

		let myInfo = insert("MyInfoEntity")
		myInfo.setValue(Int64(111), forKey: "myNodeNum")
		myInfo.setValue(node, forKey: "myInfoNode")

		let channel = insert("ChannelEntity")
		channel.setValue(Int32(0), forKey: "index")
		channel.setValue("LegacyChan", forKey: "name")
		channel.setValue(myInfo, forKey: "myInfoChannel")

		let config = insert("DeviceConfigEntity")
		config.setValue(Int32(5), forKey: "role")
		config.setValue(node, forKey: "deviceConfigNode")

		for messageId in [Int64(1001), Int64(1002)] {
			let message = insert("MessageEntity")
			message.setValue(messageId, forKey: "messageId")
			message.setValue("message \(messageId)", forKey: "messagePayload")
			message.setValue("markdown", forKey: "messagePayloadMarkdown")
			message.setValue("translated", forKey: "messagePayloadTranslated")
			message.setValue("translated markdown", forKey: "messagePayloadTranslatedMarkdown")
			message.setValue(true, forKey: "pkiEncrypted")
			message.setValue(Int32(1), forKey: "portNum")
			message.setValue(Data([1, 2, 3]), forKey: "publicKey")
			message.setValue(true, forKey: "read")
			message.setValue(true, forKey: "realACK")
			message.setValue(false, forKey: "receivedACK")
			message.setValue(Int64(9), forKey: "relayNode")
			message.setValue(Int16(2), forKey: "relays")
			message.setValue(Int32(-80), forKey: "rssi")
			message.setValue(true, forKey: "showTranslatedMessage")
			message.setValue(user, forKey: "fromUser")
			message.setValue(user, forKey: "toUser")
		}

		func insertPosition(latitude: Int32, time: TimeInterval) {
			let position = insert("PositionEntity")
			position.setValue(latitude == 38_000_000, forKey: "latest")
			position.setValue(latitude, forKey: "latitudeI")
			position.setValue(Int32(-122_000_000), forKey: "longitudeI")
			position.setValue(Int32(17), forKey: "precisionBits")
			position.setValue(Int32(-42), forKey: "rssi")
			position.setValue(Date(timeIntervalSince1970: time), forKey: "time")
			position.setValue(node, forKey: "nodePosition")
		}
		insertPosition(latitude: 37_000_000, time: 1_700_000_001)
		insertPosition(latitude: 37_000_000, time: 1_700_000_001)
		insertPosition(latitude: 38_000_000, time: 1_700_000_002)

		func insertTelemetry(temperature: Float, time: TimeInterval) {
			let telemetry = insert("TelemetryEntity")
			telemetry.setValue(Int32(1), forKey: "metricsType")
			telemetry.setValue(Int32(2), forKey: "numOnlineNodes")
			telemetry.setValue(Int32(3), forKey: "numPacketsRx")
			telemetry.setValue(Int32(4), forKey: "numPacketsRxBad")
			telemetry.setValue(Int32(5), forKey: "numPacketsTx")
			telemetry.setValue(Int32(6), forKey: "numRxDupe")
			telemetry.setValue(Int32(7), forKey: "numTotalNodes")
			telemetry.setValue(Int32(8), forKey: "numTxRelay")
			telemetry.setValue(Int32(9), forKey: "numTxRelayCanceled")
			telemetry.setValue(Float(10.5), forKey: "irLux")
			telemetry.setValue(Float(11.5), forKey: "lux")
			telemetry.setValue(Float(12.5), forKey: "radiation")
			telemetry.setValue(Int32(bitPattern: 4_000_000_000), forKey: "soilMoisture")
			telemetry.setValue(temperature, forKey: "temperature")
			telemetry.setValue(Float(13.5), forKey: "windSpeed")
			telemetry.setValue(Date(timeIntervalSince1970: time), forKey: "time")
			telemetry.setValue(node, forKey: "nodeTelemetry")
		}
		insertTelemetry(temperature: 21.5, time: 1_700_000_003)
		insertTelemetry(temperature: 22.5, time: 1_700_000_004)

		// V58 permits these orphans. They must remain skipped on every retry.
		let orphanChannel = insert("ChannelEntity")
		orphanChannel.setValue(Int32(7), forKey: "index")
		_ = insert("DeviceConfigEntity")

		try context.save()
		for store in container.persistentStoreCoordinator.persistentStores {
			try container.persistentStoreCoordinator.remove(store)
		}
	}
}

private struct TestInterruption: Error {}

private struct MigrationCounts: Equatable {
	let messages: Int
	let positions: Int
	let telemetry: Int
	let channels: Int
	let deviceConfigs: Int

	static let final = MigrationCounts(messages: 2, positions: 3, telemetry: 2, channels: 1, deviceConfigs: 1)
}
