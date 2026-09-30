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
///
/// Each test owns an in-memory container and its own `MeshPackets`, rather than reaching
/// for the shared ones. Other suites recreate `PersistenceController.shared` and
/// `MeshPackets.shared` mid-run, and `.serialized` only orders tests inside one suite — a
/// reset landing while a test here is suspended at an `await` would invalidate the actor
/// or hand it an empty container.
@Suite("Ambient lighting ingestion")
struct AmbientLightingUpsertTests {

	private func freshMesh() throws -> (MeshPackets, ModelContainer) {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		return (MeshPackets(modelContainer: container), container)
	}

	private func seedNode(_ nodeNum: Int64, in container: ModelContainer) throws -> NodeInfoEntity {
		let context = ModelContext(container)
		let node = NodeInfoEntity()
		node.num = nodeNum
		context.insert(node)
		try context.save()
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

	private func storedConfig(
		_ nodeNum: Int64, in container: ModelContainer
	) throws -> AmbientLightingConfigEntity? {
		try ModelContext(container).fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		).first?.ambientLightingConfig
	}

	@Test func aSecondConfigUpdatesTheEntityRatherThanReplacingIt() async throws {
		let (mesh, container) = try freshMesh()
		let nodeNum: Int64 = 0x00E0_0401
		_ = try seedNode(nodeNum, in: container)

		// First config from the radio creates the entity.
		await mesh.upsertAmbientLightingModuleConfigPacket(
			config: config(red: 10, green: 20, blue: 30), nodeNum: nodeNum)

		// Second one must update that same entity. The node has no canned message config,
		// which is what used to send this down the insert branch a second time.
		await mesh.upsertAmbientLightingModuleConfigPacket(
			config: config(red: 40, green: 200, blue: 90), nodeNum: nodeNum)

		let stored = try storedConfig(nodeNum, in: container)
		#expect(stored?.red == 40)
		#expect(stored?.green == 200)
		#expect(stored?.blue == 90)

		// The part that failed before: the first entity was left in the store with nothing
		// referring to it.
		let all = try ModelContext(container).fetch(FetchDescriptor<AmbientLightingConfigEntity>())
		#expect(all.count == 1, "the second config should update the entity, not orphan it")
	}

	@Test func aNodeWithACannedMessageConfigStillStoresItsColor() async throws {
		let (mesh, container) = try freshMesh()
		let nodeNum: Int64 = 0x00E0_0402
		let context = ModelContext(container)
		let node = NodeInfoEntity()
		node.num = nodeNum
		context.insert(node)
		// The old branch keyed on this being present, so cover it too: the colour has to
		// land either way.
		let canned = CannedMessageConfigEntity()
		context.insert(canned)
		node.cannedMessageConfig = canned
		try context.save()

		await mesh.upsertAmbientLightingModuleConfigPacket(
			config: config(red: 1, green: 2, blue: 3), nodeNum: nodeNum)

		let stored = try storedConfig(nodeNum, in: container)
		#expect(stored?.red == 1)
		#expect(stored?.green == 2)
		#expect(stored?.blue == 3)
	}
}
