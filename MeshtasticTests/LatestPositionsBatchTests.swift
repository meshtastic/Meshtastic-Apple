//
//  LatestPositionsBatchTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/28/26.
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Latest positions for many nodes")
struct LatestPositionsBatchTests {

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"LatestPositionsBatchTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		return try ModelContainer(for: schema, configurations: config)
	}

	@discardableResult
	private func insertPosition(_ latitudeI: Int32, time: TimeInterval, latest: Bool = false, for node: NodeInfoEntity, in context: ModelContext) -> PositionEntity {
		let position = PositionEntity()
		position.latitudeI = latitudeI
		position.longitudeI = -1_221_234_567
		position.time = Date(timeIntervalSince1970: time)
		position.latest = latest
		position.nodePosition = node
		context.insert(position)
		return position
	}

	private func insertNode(_ num: Int64, in context: ModelContext) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		context.insert(node)
		return node
	}

	@Test func matchesLatestPositionForEveryKindOfNode() throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		// The cache wins over a row flagged latest, as in latestPosition.
		let cachedNode = insertNode(1, in: context)
		let cached = insertPosition(100, time: 1_000, for: cachedNode, in: context)
		insertPosition(101, time: 2_000, latest: true, for: cachedNode, in: context)
		cachedNode.latestPositionCache = cached
		// No cache: the newest row by time, flagged or not, as latestPosition's fallback.
		let flaggedNode = insertNode(2, in: context)
		insertPosition(200, time: 1_000, latest: true, for: flaggedNode, in: context)
		insertPosition(201, time: 3_000, latest: true, for: flaggedNode, in: context)
		insertPosition(202, time: 4_000, for: flaggedNode, in: context)
		// No position at all.
		let emptyNode = insertNode(3, in: context)
		try context.save()

		let positions = NodeInfoEntity.latestPositions(for: [cachedNode, flaggedNode, emptyNode], context: context)
		#expect(positions[cachedNode.persistentModelID]?.latitudeI == 100)
		#expect(positions[flaggedNode.persistentModelID]?.latitudeI == 202)
		#expect(positions[flaggedNode.persistentModelID]?.latitudeI == flaggedNode.latestPosition?.latitudeI)
		#expect(positions[emptyNode.persistentModelID] == nil)
	}

	@Test func anUnsavedCachedPositionIsUsedAsIs() throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		let node = insertNode(1, in: context)
		try context.save()
		let unsaved = insertPosition(300, time: 1_000, for: node, in: context)
		node.latestPositionCache = unsaved

		let positions = NodeInfoEntity.latestPositions(for: [node], context: context)
		#expect(positions[node.persistentModelID]?.latitudeI == 300)
	}

	/// The crash #2698 fixed: another context deleted the cached row. It must not be read; the
	/// node falls back to its newest remaining row.
	@Test func aCachedPositionDeletedElsewhereFallsBack() throws {
		let container = try makeContainer()
		let reader = ModelContext(container)
		let node = insertNode(1, in: reader)
		let cached = insertPosition(400, time: 2_000, for: node, in: reader)
		insertPosition(401, time: 1_000, latest: true, for: node, in: reader)
		node.latestPositionCache = cached
		try reader.save()

		let writer = ModelContext(container)
		let cachedID = cached.persistentModelID
		let doomed = try #require(try writer.fetch(FetchDescriptor<PositionEntity>(predicate: #Predicate { $0.persistentModelID == cachedID })).first)
		writer.delete(doomed)
		try writer.save()

		let positions = NodeInfoEntity.latestPositions(for: [node], context: reader)
		#expect(positions[node.persistentModelID]?.latitudeI == 401)
	}

	@Test func manyNodesMatchTheirOwnLatestPosition() throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		for num in 1...1_500 {
			let node = insertNode(Int64(num), in: context)
			for step in 0..<5 {
				let position = insertPosition(Int32(num * 10 + step), time: TimeInterval(step), latest: step == 4, for: node, in: context)
				// Every third node has no cache, so both fetches are used.
				if step == 4, num % 3 != 0 { node.latestPositionCache = position }
			}
		}
		try context.save()

		let fresh = ModelContext(container)
		let nodes = try fresh.fetch(FetchDescriptor<NodeInfoEntity>())
		let positions = NodeInfoEntity.latestPositions(for: nodes, context: fresh)
		#expect(positions.count == 1_500)
		#expect(nodes.allSatisfy { positions[$0.persistentModelID]?.latitudeI == $0.latestPosition?.latitudeI })
	}
}
