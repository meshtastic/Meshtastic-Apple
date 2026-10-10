//
//  MessageKeyMigrationSpikeTests.swift
//  MeshtasticTests
//
//  Copyright(c) Meshtastic 2026.
//
//  Spike for feature 021 (T020): can uniqueness move from `messageId` to a sender-scoped
//  `messageKey` through SwiftData's automatic lightweight migration, the way this project
//  evolves its schema (one VersionedSchema, additive changes; see SchemaHistoryUpgradeTests)?
//
//  Uses throwaway models on scratch stores, never the app's schema or store.
//

import Foundation
import SwiftData
import Testing

// Same entity name in each enum, same version identifier: exactly how the app's live models
// change between releases while MeshtasticSchemaV1 stays at 1.0.0.

enum SpikeSchemaBefore: VersionedSchema {
	static var versionIdentifier = Schema.Version(1, 0, 0)
	static var models: [any PersistentModel.Type] { [SpikeMessage.self] }

	@Model final class SpikeMessage {
		@Attribute(.unique) var messageId: Int64 = 0
		var fromNum: Int64 = 0
		var payload: String = ""
		init(messageId: Int64, fromNum: Int64, payload: String) {
			self.messageId = messageId
			self.fromNum = fromNum
			self.payload = payload
		}
	}
}

/// Step 1: keep `messageId` unique, add an optional unique `messageKey`.
enum SpikeSchemaBothUnique: VersionedSchema {
	static var versionIdentifier = Schema.Version(1, 0, 0)
	static var models: [any PersistentModel.Type] { [SpikeMessage.self] }

	@Model final class SpikeMessage {
		@Attribute(.unique) var messageId: Int64 = 0
		var fromNum: Int64 = 0
		var payload: String = ""
		@Attribute(.unique) var messageKey: String?
		init(messageId: Int64, fromNum: Int64, payload: String, messageKey: String?) {
			self.messageId = messageId
			self.fromNum = fromNum
			self.payload = payload
			self.messageKey = messageKey
		}
	}
}

/// Step 2: `messageId` no longer unique; `messageKey` is the only unique attribute.
enum SpikeSchemaKeyOnly: VersionedSchema {
	static var versionIdentifier = Schema.Version(1, 0, 0)
	static var models: [any PersistentModel.Type] { [SpikeMessage.self] }

	@Model final class SpikeMessage {
		var messageId: Int64 = 0
		var fromNum: Int64 = 0
		var payload: String = ""
		@Attribute(.unique) var messageKey: String?
		init(messageId: Int64, fromNum: Int64, payload: String, messageKey: String?) {
			self.messageId = messageId
			self.fromNum = fromNum
			self.payload = payload
			self.messageKey = messageKey
		}
	}
}

@Suite("Message key migration spike", .serialized)
struct MessageKeyMigrationSpikeTests {
	private static func key(_ fromNum: Int64, _ messageId: Int64) -> String { "\(fromNum):\(messageId)" }

	private func scratchStore() throws -> URL {
		let folder = FileManager.default.temporaryDirectory
			.appendingPathComponent("message-key-spike-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return folder.appendingPathComponent("Spike.store")
	}

	private func container<S: VersionedSchema>(_ schema: S.Type, at url: URL) throws -> ModelContainer {
		let schema = Schema(versionedSchema: S.self)
		return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
	}

	/// Three existing messages, as a released store holds them.
	private func seedBefore(at url: URL) throws {
		let container = try container(SpikeSchemaBefore.self, at: url)
		let context = ModelContext(container)
		context.insert(SpikeSchemaBefore.SpikeMessage(messageId: 1, fromNum: 100, payload: "one"))
		context.insert(SpikeSchemaBefore.SpikeMessage(messageId: 2, fromNum: 100, payload: "two"))
		context.insert(SpikeSchemaBefore.SpikeMessage(messageId: 3, fromNum: 200, payload: "three"))
		try context.save()
	}

	/// Backfill the key the way the app would after the upgrade: in code, resumable.
	private func backfill<M: PersistentModel>(_ context: ModelContext, _ type: M.Type, fromNum: KeyPath<M, Int64>, messageId: KeyPath<M, Int64>, key: ReferenceWritableKeyPath<M, String?>) throws {
		for message in try context.fetch(FetchDescriptor<M>()) where message[keyPath: key] == nil {
			message[keyPath: key] = Self.key(message[keyPath: fromNum], message[keyPath: messageId])
		}
		try context.save()
	}

	@Test func addingAnOptionalUniqueKeyMigratesAPopulatedStore() throws {
		let url = try scratchStore()
		try seedBefore(at: url)

		let context = ModelContext(try container(SpikeSchemaBothUnique.self, at: url))
		let migrated = try context.fetch(FetchDescriptor<SpikeSchemaBothUnique.SpikeMessage>())
		#expect(migrated.count == 3)
		#expect(migrated.allSatisfy { $0.messageKey == nil })
		#expect(Set(migrated.map(\.payload)) == ["one", "two", "three"])

		try backfill(context, SpikeSchemaBothUnique.SpikeMessage.self, fromNum: \.fromNum, messageId: \.messageId, key: \.messageKey)
		let keys = try context.fetch(FetchDescriptor<SpikeSchemaBothUnique.SpikeMessage>()).compactMap(\.messageKey)
		#expect(Set(keys) == [Self.key(100, 1), Self.key(100, 2), Self.key(200, 3)])
	}

	@Test func droppingMessageIdUniquenessLetsTwoSendersShareAnId() throws {
		let url = try scratchStore()
		try seedBefore(at: url)
		// Step 1 then step 2, each a separate release's worth of lightweight migration.
		do {
			let context = ModelContext(try container(SpikeSchemaBothUnique.self, at: url))
			try backfill(context, SpikeSchemaBothUnique.SpikeMessage.self, fromNum: \.fromNum, messageId: \.messageId, key: \.messageKey)
		}

		let context = ModelContext(try container(SpikeSchemaKeyOnly.self, at: url))
		#expect(try context.fetchCount(FetchDescriptor<SpikeSchemaKeyOnly.SpikeMessage>()) == 3)

		// A different sender picked the same random packet id: previously this row would have
		// replaced message 1 (the upsert on the unique messageId). Now it is its own message.
		context.insert(SpikeSchemaKeyOnly.SpikeMessage(messageId: 1, fromNum: 300, payload: "collision", messageKey: Self.key(300, 1)))
		try context.save()
		let all = try context.fetch(FetchDescriptor<SpikeSchemaKeyOnly.SpikeMessage>())
		#expect(all.count == 4)
		#expect(all.first { $0.messageKey == Self.key(100, 1) }?.payload == "one")
		#expect(all.first { $0.messageKey == Self.key(300, 1) }?.payload == "collision")
	}

	@Test func sameSenderAndIdStillCollapsesToOneMessage() throws {
		let url = try scratchStore()
		try seedBefore(at: url)
		do {
			let context = ModelContext(try container(SpikeSchemaBothUnique.self, at: url))
			try backfill(context, SpikeSchemaBothUnique.SpikeMessage.self, fromNum: \.fromNum, messageId: \.messageId, key: \.messageKey)
		}
		let context = ModelContext(try container(SpikeSchemaKeyOnly.self, at: url))

		// The same packet heard by a second radio, or the mesh echo of a message we sent.
		context.insert(SpikeSchemaKeyOnly.SpikeMessage(messageId: 2, fromNum: 100, payload: "two, again", messageKey: Self.key(100, 2)))
		try context.save()
		let fresh = ModelContext(context.container)
		let matching = try fresh.fetch(FetchDescriptor<SpikeSchemaKeyOnly.SpikeMessage>()).filter { $0.messageKey == Self.key(100, 2) }
		#expect(matching.count == 1)
		#expect(try fresh.fetchCount(FetchDescriptor<SpikeSchemaKeyOnly.SpikeMessage>()) == 3)
	}

	/// What users will actually do: nothing ships until feature 021 is done, so every upgrade
	/// goes straight from today's schema to the final one in a single open.
	@Test func singleStepUpgradeMovesUniquenessAndKeepsEveryRow() throws {
		let url = try scratchStore()
		try seedBefore(at: url)

		let context = ModelContext(try container(SpikeSchemaKeyOnly.self, at: url))
		let migrated = try context.fetch(FetchDescriptor<SpikeSchemaKeyOnly.SpikeMessage>())
		#expect(migrated.count == 3)
		#expect(migrated.allSatisfy { $0.messageKey == nil })

		try backfill(context, SpikeSchemaKeyOnly.SpikeMessage.self, fromNum: \.fromNum, messageId: \.messageId, key: \.messageKey)
		context.insert(SpikeSchemaKeyOnly.SpikeMessage(messageId: 1, fromNum: 300, payload: "collision", messageKey: Self.key(300, 1)))
		context.insert(SpikeSchemaKeyOnly.SpikeMessage(messageId: 3, fromNum: 200, payload: "three, again", messageKey: Self.key(200, 3)))
		try context.save()

		let fresh = ModelContext(context.container)
		let all = try fresh.fetch(FetchDescriptor<SpikeSchemaKeyOnly.SpikeMessage>())
		#expect(all.count == 4)
		#expect(all.filter { $0.messageId == 1 }.count == 2)
		#expect(all.filter { $0.messageKey == Self.key(200, 3) }.count == 1)
	}

	@Test func manyRowsCanWaitForTheirKeyAtOnce() throws {
		// NULLs never collide in a unique index, so rows written before the backfill coexist.
		let url = try scratchStore()
		let context = ModelContext(try container(SpikeSchemaKeyOnly.self, at: url))
		for id in 1...50 {
			context.insert(SpikeSchemaKeyOnly.SpikeMessage(messageId: Int64(id % 5), fromNum: 1, payload: "\(id)", messageKey: nil))
		}
		try context.save()
		#expect(try ModelContext(context.container).fetchCount(FetchDescriptor<SpikeSchemaKeyOnly.SpikeMessage>()) == 50)
	}
}
