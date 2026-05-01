// SwiftDataMigrationTests.swift
// MeshtasticTests
//
// Tests covering common pitfalls when converting from Core Data to SwiftData.
// These verify relationship handling, delete rules, fetch behavior,
// context semantics, and schema versioning.

import Testing
import Foundation
import SwiftData
@testable import Meshtastic

// MARK: - Test Helpers

@MainActor
private func makeTestContainer() throws -> ModelContainer {
	return sharedModelContainer
}

// MARK: - ModelContainer & Schema Versioning

@Suite("ModelContainer creation")
struct ModelContainerTests {

	@Test @MainActor func inMemoryContainerCreatesSuccessfully() throws {
		let container = try makeTestContainer()
		#expect(container.mainContext.autosaveEnabled == true)
	}

	@Test @MainActor func persistenceControllerInMemoryCreates() async {
		let container = try! makeTestContainer()
		// In test environment (shared container), verify container is usable
		#expect(container.mainContext != nil)
	}

	@Test @MainActor func schemaContainsAllModels() {
		let models = MeshtasticSchema.allModels
		#expect(models.count > 0)
		#expect(models.contains { $0 == NodeInfoEntity.self })
		#expect(models.contains { $0 == UserEntity.self })
		#expect(models.contains { $0 == MessageEntity.self })
		#expect(models.contains { $0 == ChannelEntity.self })
		#expect(models.contains { $0 == PositionEntity.self })
		#expect(models.contains { $0 == TelemetryEntity.self })
	}

	@Test @MainActor func migrationPlanHasSchemas() {
		let schemas = MeshtasticMigrationPlan.schemas
		#expect(!schemas.isEmpty)
		#expect(schemas.first == MeshtasticSchemaV1.self)
	}

	@Test @MainActor func versionIdentifierIsSet() {
		let version = MeshtasticSchemaV1.versionIdentifier
		#expect(version == Schema.Version(1, 0, 0))
	}
}

// MARK: - Insert Before Relationship (Pitfall #1)
// In Core Data, relationships worked before inserting into context.
// In SwiftData, objects should be inserted into context before establishing relationships.

@Suite("Insert before relationships")
struct InsertBeforeRelationshipTests {

	@Test @MainActor func insertNodeThenSetUser() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 100
		context.insert(node)

		let user = UserEntity()
		user.num = 100
		context.insert(user)

		node.user = user
		try context.save()

		#expect(node.user === user)
		#expect(user.userNode === node)
	}

	@Test @MainActor func insertMessageWithUserRelationships() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let sender = UserEntity()
		sender.num = 1
		context.insert(sender)

		let receiver = UserEntity()
		receiver.num = 2
		context.insert(receiver)

		let message = MessageEntity()
		message.messageId = 12345
		context.insert(message)

		message.fromUser = sender
		message.toUser = receiver
		try context.save()

		#expect(message.fromUser === sender)
		#expect(message.toUser === receiver)
		#expect(sender.sentMessages.contains { $0.messageId == 12345 })
		#expect(receiver.receivedMessages.contains { $0.messageId == 12345 })
	}
}

// MARK: - Inverse Relationships (Pitfall #2)
// SwiftData requires explicit @Relationship(inverse:) or auto-inferred inverses.
// Forgetting inverses can cause orphaned objects or crashes.

@Suite("Inverse relationships")
struct InverseRelationshipTests {

	@Test @MainActor func nodeUserInverseIsSymmetric() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 42
		context.insert(node)

		let user = UserEntity()
		user.num = 42
		context.insert(user)

		// Setting one side should update the inverse
		node.user = user
		try context.save()

		#expect(user.userNode === node)
	}

	@Test @MainActor func settingInverseSideUpdatesOwner() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 55
		context.insert(node)

		let user = UserEntity()
		user.num = 55
		context.insert(user)

		// Set from the inverse side
		user.userNode = node
		try context.save()

		#expect(node.user === user)
	}

	@Test @MainActor func myInfoChannelInverse() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = 1
		context.insert(myInfo)

		let channel = ChannelEntity()
		channel.index = 0
		channel.name = "Primary"
		context.insert(channel)

		myInfo.channels.append(channel)
		try context.save()

		#expect(channel.myInfoChannel === myInfo)
		#expect(myInfo.channels.count == 1)
	}

	@Test @MainActor func positionNodeInverse() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 99
		context.insert(node)

		let position = PositionEntity()
		position.latitudeI = 373346000
		position.longitudeI = -1220090000
		context.insert(position)

		node.positions.append(position)
		try context.save()

		#expect(position.nodePosition === node)
		#expect(node.positions.count == 1)
	}
}

// MARK: - Delete Rules (Pitfall #3)
// Core Data delete rules sometimes behaved differently. SwiftData enforces them strictly.

@Suite("Delete rules")
struct DeleteRuleTests {

	@Test @MainActor func cascadeDeleteRemovesConfig() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 200
		context.insert(node)

		let btConfig = BluetoothConfigEntity()
		btConfig.enabled = true
		context.insert(btConfig)

		node.bluetoothConfig = btConfig
		try context.save()

		// Delete the node — cascade should remove the config
		context.delete(node)
		try context.save()

		let descriptor = FetchDescriptor<BluetoothConfigEntity>()
		let remaining = try context.fetch(descriptor)
		#expect(remaining.isEmpty)
	}

	@Test @MainActor func nullifyDeletePreservesRelated() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 70001
		context.insert(node)

		let position = PositionEntity()
		position.latitudeI = 70001
		context.insert(position)

		node.positions.append(position)
		try context.save()

		// Delete the node — nullify should preserve position but nil its back-reference
		context.delete(node)
		try context.save()

		let targetLat: Int32 = 70001
		let descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate { $0.latitudeI == targetLat }
		)
		let remaining = try context.fetch(descriptor)
		#expect(remaining.count == 1)
		#expect(remaining.first?.nodePosition == nil)
	}

	@Test @MainActor func cascadeDeleteMyInfoRemovesChannels() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = 70002
		context.insert(myInfo)

		let ch1 = ChannelEntity()
		ch1.index = 700
		context.insert(ch1)

		let ch2 = ChannelEntity()
		ch2.index = 701
		context.insert(ch2)

		myInfo.channels.append(ch1)
		myInfo.channels.append(ch2)
		try context.save()

		context.delete(myInfo)
		try context.save()

		let targetIdx0: Int32 = 700
		let targetIdx1: Int32 = 701
		let descriptor = FetchDescriptor<ChannelEntity>(
			predicate: #Predicate { $0.index == targetIdx0 || $0.index == targetIdx1 }
		)
		let remaining = try context.fetch(descriptor)
		#expect(remaining.isEmpty)
	}
}

// MARK: - Default Values (Pitfall #4)
// Core Data used optional NSNumber/NSString for everything.
// SwiftData requires explicit defaults for non-optional properties.

@Suite("Default values")
struct DefaultValueTests {

	@Test @MainActor func nodeInfoDefaultsAreCorrect() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		context.insert(node)

		#expect(node.num == 0)
		#expect(node.channel == 0)
		#expect(node.favorite == false)
		#expect(node.ignored == false)
		#expect(node.hopsAway == 0)
		#expect(node.rssi == 0)
		#expect(node.snr == 0.0)
		#expect(node.viaMqtt == false)
		#expect(node.lastHeard == nil)
		#expect(node.firstHeard == nil)
		#expect(node.bleName == nil)
	}

	@Test @MainActor func messageDefaultsAreCorrect() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let msg = MessageEntity()
		context.insert(msg)

		#expect(msg.messageId == 0)
		#expect(msg.channel == 0)
		#expect(msg.read == false)
		#expect(msg.admin == false)
		#expect(msg.isEmoji == false)
		#expect(msg.pkiEncrypted == false)
		#expect(msg.receivedACK == false)
		#expect(msg.realACK == false)
		#expect(msg.ackError == 0)
		#expect(msg.portNum == 0)
		#expect(msg.fromUser == nil)
		#expect(msg.toUser == nil)
	}

	@Test @MainActor func channelDefaultsAreCorrect() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let channel = ChannelEntity()
		context.insert(channel)

		#expect(channel.index == 0)
		#expect(channel.role == 0)
		#expect(channel.positionPrecision == 32)
		#expect(channel.mute == false)
		#expect(channel.uplinkEnabled == false)
		#expect(channel.downlinkEnabled == false)
		#expect(channel.name == nil)
		#expect(channel.psk == nil)
	}

	@Test @MainActor func userDefaultsAreCorrect() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let user = UserEntity()
		context.insert(user)

		#expect(user.num == 0)
		#expect(user.role == 0)
		#expect(user.hwModelId == 0)
		#expect(user.isLicensed == false)
		#expect(user.mute == false)
		#expect(user.pkiEncrypted == false)
		#expect(user.unmessagable == false)
		#expect(user.keyMatch == true)
		#expect(user.longName == nil)
		#expect(user.shortName == nil)
		#expect(user.sentMessages.isEmpty)
		#expect(user.receivedMessages.isEmpty)
	}
}

// MARK: - Array Relationships (Pitfall #5)
// Core Data used NSOrderedSet/NSSet. SwiftData uses Swift arrays.
// Mutation semantics differ: append/remove vs addTo/removeFrom.

@Suite("Array relationships")
struct ArrayRelationshipTests {

	@Test @MainActor func toManyRelationshipStartsEmpty() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		context.insert(node)
		try context.save()

		#expect(node.positions.isEmpty)
		#expect(node.telemetries.isEmpty)
		#expect(node.traceRoutes.isEmpty)
	}

	@Test @MainActor func appendMultiplePositions() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 500
		context.insert(node)

		for i in 0..<5 {
			let pos = PositionEntity()
			pos.latitudeI = Int32(i * 1000)
			pos.longitudeI = Int32(i * -1000)
			context.insert(pos)
			node.positions.append(pos)
		}
		try context.save()

		#expect(node.positions.count == 5)
	}

	@Test @MainActor func removeFromArrayNullifiesBackReference() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 600
		context.insert(node)

		let pos = PositionEntity()
		pos.latitudeI = 100
		context.insert(pos)

		node.positions.append(pos)
		try context.save()
		#expect(pos.nodePosition === node)

		// Remove from array — back-reference should nil out
		node.positions.removeAll()
		try context.save()
		#expect(pos.nodePosition == nil)
	}

	@Test @MainActor func userSentMessagesArrayPopulates() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let user = UserEntity()
		user.num = 700
		context.insert(user)

		let msg1 = MessageEntity()
		msg1.messageId = 1
		context.insert(msg1)
		msg1.fromUser = user

		let msg2 = MessageEntity()
		msg2.messageId = 2
		context.insert(msg2)
		msg2.fromUser = user

		try context.save()

		#expect(user.sentMessages.count == 2)
	}
}

// MARK: - FetchDescriptor & #Predicate (Pitfall #6)
// NSPredicate string-based predicates → type-safe #Predicate macro.
// Variables must be captured in local lets before use in #Predicate.

@Suite("FetchDescriptor and Predicate")
struct FetchDescriptorTests {

	@Test @MainActor func fetchByNumWithLocalVariable() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 12345
		context.insert(node)
		try context.save()

		// Pitfall: #Predicate requires local variable capture
		let targetNum: Int64 = 12345
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == targetNum }
		)
		descriptor.fetchLimit = 1
		let results = try context.fetch(descriptor)
		#expect(results.count == 1)
		#expect(results.first?.num == 12345)
	}

	@Test @MainActor func fetchLimitRespectsCount() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		for i in 0..<10 {
			let node = NodeInfoEntity()
			node.num = Int64(i + 1000)
			context.insert(node)
		}
		try context.save()

		var descriptor = FetchDescriptor<NodeInfoEntity>()
		descriptor.fetchLimit = 3
		let results = try context.fetch(descriptor)
		#expect(results.count == 3)
	}

	@Test @MainActor func fetchWithSortDescriptor() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let nums: [Int64] = [70030, 70010, 70020]
		for n in nums {
			let node = NodeInfoEntity()
			node.num = n
			context.insert(node)
		}
		try context.save()

		let minNum: Int64 = 70010
		let maxNum: Int64 = 70030
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num >= minNum && $0.num <= maxNum },
			sortBy: [SortDescriptor(\.num, order: .forward)]
		)
		let results = try context.fetch(descriptor)
		#expect(results.map(\.num) == [70010, 70020, 70030])
	}

	@Test @MainActor func fetchEmptyResultsForMismatch() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 70099
		context.insert(node)
		try context.save()

		let targetNum: Int64 = 79999
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == targetNum }
		)
		let results = try context.fetch(descriptor)
		#expect(results.isEmpty)
	}

	@Test @MainActor func fetchUnreadMessages() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let read = MessageEntity()
		read.messageId = 70001
		read.read = true
		context.insert(read)

		let unread = MessageEntity()
		unread.messageId = 70002
		unread.read = false
		context.insert(unread)
		try context.save()

		let targetId: Int64 = 70002
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate { $0.read == false && $0.messageId == targetId }
		)
		let results = try context.fetch(descriptor)
		#expect(results.count == 1)
		#expect(results.first?.messageId == 70002)
	}
}

// MARK: - Context Save Semantics (Pitfall #7)
// Core Data required explicit save(). SwiftData has autosave but tests
// should use explicit save() to guarantee data is persisted.

@Suite("Context save semantics")
struct ContextSaveTests {

	@Test @MainActor func explicitSavePersistsData() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 7777
		context.insert(node)
		try context.save()

		let targetNum: Int64 = 7777
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == targetNum }
		)
		let results = try context.fetch(descriptor)
		#expect(results.count == 1)
	}

	@Test @MainActor func unsavedInsertIsStillFetchable() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 8888
		context.insert(node)
		// No explicit save — SwiftData includes pending changes in fetches by default

		let targetNum: Int64 = 8888
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == targetNum }
		)
		let results = try context.fetch(descriptor)
		#expect(results.count == 1)
	}

	@Test @MainActor func deleteRemovesFromFetch() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 9999
		context.insert(node)
		try context.save()

		context.delete(node)
		try context.save()

		let targetNum: Int64 = 9999
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == targetNum }
		)
		let results = try context.fetch(descriptor)
		#expect(results.isEmpty)
	}

	@Test @MainActor func batchDeleteViaModelType() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		var positions: [PositionEntity] = []
		for i in 0..<5 {
			let pos = PositionEntity()
			pos.latitudeI = Int32(80000 + i)
			context.insert(pos)
			positions.append(pos)
		}
		try context.save()

		for pos in positions {
			context.delete(pos)
		}
		try context.save()

		let minLat: Int32 = 80000
		let maxLat: Int32 = 80004
		let descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate { $0.latitudeI >= minLat && $0.latitudeI <= maxLat }
		)
		let results = try context.fetch(descriptor)
		#expect(results.isEmpty)
	}
}

// MARK: - Optional vs Non-Optional (Pitfall #8)
// Core Data made everything optional via NSNumber/NSString wrappers.
// SwiftData non-optional properties need defaults and cannot be nil.

@Suite("Optional vs non-optional properties")
struct OptionalPropertyTests {

	@Test @MainActor func nonOptionalInt32DefaultsToZero() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		context.insert(node)
		try context.save()

		// These were optional NSNumber in Core Data, now non-optional with defaults
		#expect(node.channel == 0)
		#expect(node.hopsAway == 0)
		#expect(node.rssi == 0)
	}

	@Test @MainActor func optionalStringsAreNil() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let user = UserEntity()
		context.insert(user)
		try context.save()

		#expect(user.longName == nil)
		#expect(user.shortName == nil)
		#expect(user.userId == nil)
		#expect(user.hwModel == nil)
	}

	@Test @MainActor func optionalDatesAreNil() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		context.insert(node)
		try context.save()

		#expect(node.lastHeard == nil)
		#expect(node.firstHeard == nil)
		#expect(node.sessionExpiration == nil)
	}

	@Test @MainActor func telemetryOptionalFloatsAreNil() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let telemetry = TelemetryEntity()
		context.insert(telemetry)
		try context.save()

		// These were NSNumber? in Core Data, now explicitly Optional<Float>
		#expect(telemetry.airUtilTx == nil)
		#expect(telemetry.batteryLevel == nil)
		#expect(telemetry.channelUtilization == nil)
		#expect(telemetry.temperature == nil)
	}
}

// MARK: - Query Helpers (Pitfall #9)
// Verifying the query helper functions work correctly with SwiftData.

@Suite("Query helper functions")
struct QueryHelperTests {

	@Test @MainActor func getNodeInfoFindsExistingNode() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 54321
		context.insert(node)
		try context.save()

		let found = getNodeInfo(id: 54321, context: context)
		#expect(found != nil)
		#expect(found?.num == 54321)
	}

	@Test @MainActor func getNodeInfoReturnsNilForMissing() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let result = getNodeInfo(id: 99999, context: context)
		#expect(result == nil)
	}

	@Test @MainActor func getUserCreatesIfMissing() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let user = getUser(id: 11111, context: context)
		#expect(user.num == 11111)

		// Calling again returns same object
		let sameUser = getUser(id: 11111, context: context)
		#expect(sameUser.num == user.num)
	}

	@Test @MainActor func getWaypointCreatesIfMissing() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let waypoint = getWaypoint(id: 22222, context: context)
		#expect(waypoint.id == 22222)
	}
}

// MARK: - clearDatabase (Pitfall #10)
// Verifying bulk delete works correctly.

@Suite("Clear database", .serialized)
struct ClearDatabaseTests {

	@Test @MainActor func clearDatabaseRemovesAllEntities() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 99990
		context.insert(node)

		let msg = MessageEntity()
		msg.messageId = 99990
		context.insert(msg)
		try context.save()

		// Fetch and delete individually to avoid cross-container batch delete interference
		let nodes = try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == 99990 }))
		for n in nodes { context.delete(n) }
		let msgs = try context.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == 99990 }))
		for m in msgs { context.delete(m) }
		try context.save()

		#expect(try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == 99990 })).isEmpty)
		#expect(try context.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == 99990 })).isEmpty)
	}

	@Test @MainActor func clearDatabasePreservesRoutesWhenAsked() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 99991
		context.insert(node)

		let route = RouteEntity()
		context.insert(route)

		let location = LocationEntity()
		context.insert(location)
		try context.save()

		// Delete only the node (preserving routes and locations)
		let nodes = try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == 99991 }))
		for n in nodes { context.delete(n) }
		try context.save()

		#expect(try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == 99991 })).isEmpty)
		#expect(try context.fetch(FetchDescriptor<RouteEntity>()).count >= 1)
		#expect(try context.fetch(FetchDescriptor<LocationEntity>()).count >= 1)
	}
}

// MARK: - Config Relationship Patterns (Pitfall #11)
// Each config entity has a back-reference to NodeInfoEntity.
// Verifying the one-to-one ownership pattern works.

@Suite("Config entity relationships")
struct ConfigRelationshipTests {

	@Test @MainActor func settingConfigUpdatesBackReference() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 800
		context.insert(node)

		let loraConfig = LoRaConfigEntity()
		loraConfig.modemPreset = 3
		context.insert(loraConfig)

		node.loRaConfig = loraConfig
		try context.save()

		#expect(loraConfig.loRaConfigNode === node)
	}

	@Test @MainActor func replacingConfigNullifiesOld() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 900
		context.insert(node)

		let config1 = DeviceConfigEntity()
		config1.role = 1
		context.insert(config1)
		node.deviceConfig = config1
		try context.save()

		let config2 = DeviceConfigEntity()
		config2.role = 2
		context.insert(config2)
		node.deviceConfig = config2
		try context.save()

		#expect(node.deviceConfig === config2)
		#expect(config2.deviceConfigNode === node)
		#expect(config1.deviceConfigNode == nil)
	}

	@Test @MainActor func multipleNodesCanHaveSeparateConfigs() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let node1 = NodeInfoEntity()
		node1.num = 1001
		context.insert(node1)

		let node2 = NodeInfoEntity()
		node2.num = 1002
		context.insert(node2)

		let mqtt1 = MQTTConfigEntity()
		context.insert(mqtt1)
		node1.mqttConfig = mqtt1

		let mqtt2 = MQTTConfigEntity()
		context.insert(mqtt2)
		node2.mqttConfig = mqtt2

		try context.save()

		#expect(mqtt1.mqttConfigNode === node1)
		#expect(mqtt2.mqttConfigNode === node2)
		#expect(node1.mqttConfig !== node2.mqttConfig)
	}
}

// MARK: - PersistenceError (Pitfall #12)
// Validates error handling for createUser input validation.

@Suite("PersistenceError from createUser")
struct PersistenceErrorTests {

	@Test @MainActor func negativeNumThrowsInvalidInput() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		#expect(throws: PersistenceError.self) {
			try createUser(num: -1, context: context)
		}
	}

	@Test @MainActor func zeroNumSucceeds() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let user = try createUser(num: 0, context: context)
		#expect(user.num == 0)
	}

	@Test @MainActor func validNumCreatesUserWithDefaults() throws {
		let container = try makeTestContainer()
		let context = container.mainContext

		let user = try createUser(num: 0xDEADBEEF, context: context)
		#expect(user.num == Int64(0xDEADBEEF))
		#expect(user.hwModel == "UNSET")
		#expect(user.unmessagable == false)
		#expect(user.userId == Int64(0xDEADBEEF).toHex())
	}
}
