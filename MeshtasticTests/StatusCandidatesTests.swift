//
//  StatusCandidatesTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

/// `NodeInfoEntity.statusCandidates` is the store-side match for `statusMessageDisplay`: it finds
/// a node with a live broadcast or a configured status, leaves out the rest and the radio, and
/// lists the latest heard first. Run against a store, since a predicate through a relationship
/// can compile and still fail when fetched.
@Suite("NodeInfoEntity.statusCandidates")
@MainActor
struct StatusCandidatesTests {

	private func makeContext() throws -> ModelContext {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"StatusCandidatesTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		return ModelContext(try ModelContainer(for: schema, configurations: config))
	}

	@discardableResult
	private func makeNode(_ num: Int64, heard: TimeInterval, broadcast: String? = nil, configured: String? = nil, in context: ModelContext) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.lastHeard = Date(timeIntervalSince1970: heard)
		node.nodeStatus = broadcast
		context.insert(node)
		if let configured {
			let config = StatusMessageConfigEntity()
			config.nodeStatus = configured
			context.insert(config)
			node.statusMessageConfig = config
		}
		return node
	}

	@Test func findsBroadcastAndConfiguredStatusesLatestFirst() throws {
		let context = try makeContext()
		makeNode(1, heard: 100, broadcast: "On the ridge", in: context)
		makeNode(2, heard: 300, configured: "Base camp", in: context)
		makeNode(3, heard: 200, broadcast: "Moving", configured: "Old", in: context)
		makeNode(4, heard: 400, configured: "", in: context)
		makeNode(5, heard: 500, in: context)
		try context.save()

		let descriptor = NodeInfoEntity.statusCandidates(excluding: -1)
		#expect(try context.fetch(descriptor).map(\.num) == [2, 3, 1])
		#expect(try context.fetchCount(descriptor) == 3)
	}

	@Test func leavesOutTheRadio() throws {
		let context = try makeContext()
		makeNode(1, heard: 100, broadcast: "On the ridge", in: context)
		makeNode(2, heard: 200, broadcast: "Base", in: context)
		try context.save()

		let descriptor = NodeInfoEntity.statusCandidates(excluding: 2)
		#expect(try context.fetch(descriptor).map(\.num) == [1])
		#expect(try context.fetchCount(descriptor) == 1)
	}
}
