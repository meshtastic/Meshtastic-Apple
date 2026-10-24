//
//  NodeInfoEntityLivenessTests.swift
//  MeshtasticTests
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Node info liveness")
@MainActor
struct NodeInfoEntityLivenessTests {

	@Test("A node does not expose a deleted user relationship")
	func deletedUserIsNotLive() throws {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 1
		let user = UserEntity()
		user.num = 1
		user.hwModel = "HELTEC_V3"
		node.user = user
		context.insert(node)
		try context.save()

		context.delete(user)
		try context.save()

		#expect(node.liveUser == nil)
		#expect(NodeInfoItemSummary(user: user) == nil)
	}

	@Test("Hardware summary keeps only value data from a live user")
	func hardwareSummaryCapturesLiveUser() throws {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 2
		let user = UserEntity()
		user.num = 2
		user.hwModel = "HELTEC_V3"
		user.hwModelId = 43
		node.user = user
		context.insert(node)
		try context.save()

		let summary = try #require(NodeInfoItemSummary(user: user))
		context.delete(user)
		try context.save()

		#expect(summary.hwModel == "HELTEC_V3")
		#expect(summary.hwModelId == 43)
		#expect(NodeInfoItemSummary(user: user) == nil)
	}

	// MARK: - latestPosition across contexts
	// A second context stands in for the ingest actor. The main context never learns about that
	// context's deletes: its node keeps pointing at the old row, and the handle still reports
	// `modelContext != nil` and `isDeleted == false`. Reading a persisted property on it trapped.

	private func makeContainer() throws -> ModelContainer {
		try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
	}

	/// A node with one latest position, inserted and saved through its own context so the main
	/// context has not loaded either row.
	private func seedNodeWithPosition(_ container: ModelContainer, num: Int64, latitudeI: Int32) throws {
		let context = ModelContext(container)
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		context.insert(node)
		let position = PositionEntity()
		position.latitudeI = latitudeI
		position.longitudeI = -1_223_000_000
		position.latest = true
		position.time = Date()
		position.nodePosition = node
		context.insert(position)
		node.latestPositionCache = position
		try context.save()
	}

	private func fetchNode(_ context: ModelContext, num: Int64) throws -> NodeInfoEntity {
		var descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		descriptor.fetchLimit = 1
		return try #require(try context.fetch(descriptor).first)
	}

	private func positionPacket(from nodeNum: UInt32, latitude: Double, precisionBits: UInt32) throws -> MeshPacket {
		var position = Position()
		position.latitudeI = Int32(latitude * 1e7)
		position.longitudeI = Int32(-122.3321 * 1e7)
		position.precisionBits = precisionBits
		var dataMessage = DataMessage()
		dataMessage.payload = try position.serializedData()
		dataMessage.portnum = .positionApp
		var packet = MeshPacket()
		packet.from = nodeNum
		packet.decoded = dataMessage
		return packet
	}

	@Test("A cached position another context replaced is read from the store, not the stale handle")
	func replacedCachedPositionIsReadFromTheStore() throws {
		let container = try makeContainer()
		try seedNodeWithPosition(container, num: 3, latitudeI: 476_000_000)
		// Fetch the node without touching its position, so the cache stays an unloaded fault.
		let node = try fetchNode(container.mainContext, num: 3)

		// The ingest side moves the node: new row, cache repointed, old row deleted, saved.
		let ingest = ModelContext(container)
		let ingestNode = try fetchNode(ingest, num: 3)
		let old = try #require(ingestNode.latestPositionCache)
		let moved = PositionEntity()
		moved.latitudeI = 477_000_000
		moved.longitudeI = -1_223_000_000
		moved.latest = true
		moved.time = Date()
		moved.nodePosition = ingestNode
		ingest.insert(moved)
		ingestNode.latestPositionCache = moved
		ingest.delete(old)
		try ingest.save()

		// The main context's node still points at the deleted row.
		#expect(node.latestPosition?.latitudeI == 477_000_000)
	}

	@Test("A cached position another context deleted with no replacement reads as nil")
	func deletedCachedPositionWithoutReplacementIsNil() throws {
		let container = try makeContainer()
		try seedNodeWithPosition(container, num: 4, latitudeI: 476_000_000)
		let node = try fetchNode(container.mainContext, num: 4)

		let ingest = ModelContext(container)
		let ingestNode = try fetchNode(ingest, num: 4)
		let old = try #require(ingestNode.latestPositionCache)
		ingest.delete(old)
		try ingest.save()

		#expect(node.latestPosition == nil)
	}

	@Test("A live cached position is returned as is")
	func liveCachedPositionIsReturned() throws {
		let container = try makeContainer()
		try seedNodeWithPosition(container, num: 5, latitudeI: 476_000_000)
		let node = try fetchNode(container.mainContext, num: 5)
		let cached = try #require(node.latestPositionCache)

		let latest = try #require(node.latestPosition)
		#expect(latest.persistentModelID == cached.persistentModelID)
		#expect(latest.latitudeI == 476_000_000)
	}

	@Test("A reduced-precision move through the ingest actor is read from the store")
	func reducedPrecisionMoveThroughIngestIsReadFromTheStore() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		await mesh.upsertPositionPacket(packet: try positionPacket(from: 6, latitude: 47.6062, precisionBits: 13))
		await mesh.flushDebouncedSaves()
		let node = try fetchNode(container.mainContext, num: 6)

		// About 1 km north: the ingest side inserts a new row and deletes the old one.
		await mesh.upsertPositionPacket(packet: try positionPacket(from: 6, latitude: 47.6152, precisionBits: 13))
		await mesh.flushDebouncedSaves()

		#expect(node.latestPosition?.latitudeI == Int32(47.6152 * 1e7))
	}

	// MARK: - latestPosition on the actor between debounced saves
	// Inside the save window the cached row is the actor's own unsaved insert, with a temporary
	// persistentModelID. The accessor hands it back without a store fetch.

	@Test("A second fix inside the save window reuses the pending row")
	func secondFixInsideTheSaveWindowReusesThePendingRow() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		await mesh.upsertPositionPacket(packet: try positionPacket(from: 7, latitude: 47.6062, precisionBits: 13))
		let first = try #require(try await mesh.latestPositionOnActor(num: 7))
		#expect(first.id.storeIdentifier == nil)

		// A few meters on, inside the near-duplicate radius, with no save in between.
		await mesh.upsertPositionPacket(packet: try positionPacket(from: 7, latitude: 47.60625, precisionBits: 13))
		let second = try #require(try await mesh.latestPositionOnActor(num: 7))
		#expect(second.id == first.id)
		#expect(second.latitudeI == Int32(47.60625 * 1e7))
		#expect(second.rowCount == 1)

		await mesh.flushDebouncedSaves()
		let nodeNum: Int64 = 7
		let saved = try ModelContext(container).fetch(FetchDescriptor<PositionEntity>(
			predicate: #Predicate { $0.nodePosition?.num == nodeNum }
		))
		#expect(saved.count == 1)
		#expect(saved.first?.latest == true)
	}

	@Test("A NodeInfo position still pending when the first fix arrives is read back")
	func pendingNodeInfoPositionIsReadBackOnTheFirstFix() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		// The node-DB dump path: a new node and its position, left for the debounced save.
		var nodeInfo = NodeInfo()
		nodeInfo.num = 8
		nodeInfo.position.latitudeI = Int32(47.6062 * 1e7)
		nodeInfo.position.longitudeI = Int32(-122.3321 * 1e7)
		_ = await mesh.nodeInfoPacket(nodeInfo: nodeInfo, channel: 0, deferSave: true)

		await mesh.upsertPositionPacket(packet: try positionPacket(from: 8, latitude: 47.6062, precisionBits: 13))
		let read = try #require(try await mesh.latestPositionOnActor(num: 8))
		#expect(read.id.storeIdentifier == nil)
		#expect(read.latitudeI == Int32(47.6062 * 1e7))
		#expect(read.rowCount == 1)
		await mesh.flushDebouncedSaves()
	}

	@Test("A near-duplicate fix after a save reuses the saved row with no save in between")
	func nearDuplicateFixAfterASaveReusesTheSavedRow() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		await mesh.upsertPositionPacket(packet: try positionPacket(from: 9, latitude: 47.6062, precisionBits: 13))
		await mesh.flushDebouncedSaves()
		let saved = try #require(try await mesh.latestPositionOnActor(num: 9))
		#expect(saved.id.storeIdentifier != nil)

		// Inside the near-duplicate radius: the saved row is edited in place and read before the save.
		await mesh.upsertPositionPacket(packet: try positionPacket(from: 9, latitude: 47.60625, precisionBits: 13))
		let read = try #require(try await mesh.latestPositionOnActor(num: 9))
		#expect(read.id == saved.id)
		#expect(read.latitudeI == Int32(47.60625 * 1e7))
		#expect(read.rowCount == 1)
		await mesh.flushDebouncedSaves()
	}
}

/// What a read of `latestPosition` on the actor's own context returned, as values.
private struct ActorPositionRead {
	let id: PersistentIdentifier
	let latitudeI: Int32
	/// Position rows the actor's context holds for the node, pending inserts included.
	let rowCount: Int
}

private extension MeshPackets {
	/// Reads the node's latest position on the actor's own context, the way the ingest path does.
	func latestPositionOnActor(num: Int64) throws -> ActorPositionRead? {
		var descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		descriptor.fetchLimit = 1
		guard let node = try modelContext.fetch(descriptor).first, let latest = node.latestPosition else { return nil }
		let rows = try modelContext.fetch(FetchDescriptor<PositionEntity>(
			predicate: #Predicate { $0.nodePosition?.num == num }
		))
		return ActorPositionRead(id: latest.persistentModelID, latitudeI: latest.latitudeI, rowCount: rows.count)
	}
}
