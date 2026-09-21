//
//  AmbientLightingUpsertTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/21/26.
//
import Foundation
import SwiftData
import Testing
import MeshtasticProtobufs

@testable import Meshtastic

/// The ambient lighting upsert used to pick its branch by looking at the node's *canned
/// message* config. On a node that had an ambient lighting config but no canned message
/// config it took the insert branch, so a second config arriving from the radio built a
/// fresh entity and left the previous one behind with nothing pointing at it.
@Suite("Ambient lighting ingestion", .serialized)
struct AmbientLightingUpsertTests {

	@MainActor
	private func seedNode(_ nodeNum: Int64) throws -> NodeInfoEntity {
		let context = PersistenceController.shared.context
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		for existing in try context.fetch(descriptor) {
			context.delete(existing)
		}
		for orphan in try context.fetch(FetchDescriptor<AmbientLightingConfigEntity>()) {
			context.delete(orphan)
		}
		try context.save()

		let node = NodeInfoEntity()
		node.num = nodeNum
		context.insert(node)
		try context.save()
		MeshPackets.recreateShared()
		return node
	}

	private func config(red: UInt32, green: UInt32, blue: UInt32) -> ModuleConfig.AmbientLightingConfig {
		var config = ModuleConfig.AmbientLightingConfig()
		config.ledState = true
		config.current = 10
		config.red = red
		config.green = green
		config.blue = blue
		return config
	}

	@Test @MainActor func aSecondConfigUpdatesTheEntityRatherThanReplacingIt() async throws {
		let nodeNum: Int64 = 0x00E0_0401
		_ = try seedNode(nodeNum)

		// First config from the radio creates the entity.
		await MeshPackets.shared.upsertAmbientLightingModuleConfigPacket(
			config: config(red: 10, green: 20, blue: 30), nodeNum: nodeNum)

		// Second one must update that same entity. The node has no canned message config,
		// which is what used to send this down the insert branch a second time.
		await MeshPackets.shared.upsertAmbientLightingModuleConfigPacket(
			config: config(red: 40, green: 200, blue: 90), nodeNum: nodeNum)

		let context = ModelContext(PersistenceController.shared.container)
		let stored = try context.fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		).first?.ambientLightingConfig
		#expect(stored?.red == 40)
		#expect(stored?.green == 200)
		#expect(stored?.blue == 90)

		// The part that failed before: the first entity was left in the store with nothing
		// referring to it.
		let all = try context.fetch(FetchDescriptor<AmbientLightingConfigEntity>())
		#expect(all.count == 1, "the second config should update the entity, not orphan it")
	}

	@Test @MainActor func aNodeWithACannedMessageConfigStillStoresItsColor() async throws {
		let nodeNum: Int64 = 0x00E0_0402
		let node = try seedNode(nodeNum)

		// The old branch keyed on this being present, so cover it too: the colour has to
		// land either way.
		let context = PersistenceController.shared.context
		let canned = CannedMessageConfigEntity()
		context.insert(canned)
		node.cannedMessageConfig = canned
		try context.save()

		await MeshPackets.shared.upsertAmbientLightingModuleConfigPacket(
			config: config(red: 1, green: 2, blue: 3), nodeNum: nodeNum)

		let read = ModelContext(PersistenceController.shared.container)
		let stored = try read.fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		).first?.ambientLightingConfig
		#expect(stored?.red == 1)
		#expect(stored?.green == 2)
		#expect(stored?.blue == 3)
	}
}
