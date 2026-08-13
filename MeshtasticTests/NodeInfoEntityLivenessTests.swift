//
//  NodeInfoEntityLivenessTests.swift
//  MeshtasticTests
//

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
}
