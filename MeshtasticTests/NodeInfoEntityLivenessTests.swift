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
		#expect(NodeInfoItem(node: node).hardware.isEmpty)
	}
}
