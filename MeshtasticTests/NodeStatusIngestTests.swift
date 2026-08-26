//
//  NodeStatusIngestTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/26/26.
//
//  Pins the status message receive chain end to end at the app boundary: a
//  NODE_STATUS_APP packet updates the node's live status, and a StatusMessage
//  module config packet creates the config entity the editor form requires
//  (the form disables itself while statusMessageConfig is nil). Written while
//  running down a "status message not working" report, to prove which links
//  the app owns and that they hold.
//

import Foundation
import SwiftData
import Testing
import MeshtasticProtobufs

@testable import Meshtastic

@Suite("Node status ingest")
struct NodeStatusIngestTests {

	private func makeContainer() throws -> ModelContainer {
		try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
	}

	private func seedNode(_ context: ModelContext, num: Int64) throws {
		let node = NodeInfoEntity()
		node.num = num
		context.insert(node)
		try context.save()
	}

	private func statusPacket(from num: UInt32, status: String) -> MeshPacket {
		var statusMessage = StatusMessage()
		statusMessage.status = status
		var packet = MeshPacket()
		packet.from = num
		packet.decoded.portnum = .nodeStatusApp
		packet.decoded.payload = (try? statusMessage.serializedData()) ?? Data()
		return packet
	}

	@Test func statusBroadcastUpdatesTheNode() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		try seedNode(context, num: 0x0BEE_F001)

		let mesh = MeshPackets(modelContainer: container)
		await mesh.upsertNodeStatusPacket(packet: statusPacket(from: 0x0BEE_F001, status: "Hiking Tiger Mountain"))
		await mesh.flushDebouncedSaves()

		let num: Int64 = 0x0BEE_F001
		let node = try #require(try context.fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		).first)
		#expect(node.nodeStatus == "Hiking Tiger Mountain")
		#expect(node.statusMessageDisplay == "Hiking Tiger Mountain", "the node list reads statusMessageDisplay")
	}

	@Test func emptyStatusClearsTheStoredValue() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		try seedNode(context, num: 0x0BEE_F002)

		let mesh = MeshPackets(modelContainer: container)
		await mesh.upsertNodeStatusPacket(packet: statusPacket(from: 0x0BEE_F002, status: "Set"))
		await mesh.upsertNodeStatusPacket(packet: statusPacket(from: 0x0BEE_F002, status: ""))
		await mesh.flushDebouncedSaves()

		let num: Int64 = 0x0BEE_F002
		let node = try #require(try context.fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		).first)
		#expect(node.nodeStatus == nil, "an empty broadcast clears the status, matching Android")
	}

	@Test func statusFromUnknownNodeIsDroppedWithoutCrashing() async throws {
		let container = try makeContainer()
		let mesh = MeshPackets(modelContainer: container)
		// No node row exists — the handler must log and drop, not trap.
		await mesh.upsertNodeStatusPacket(packet: statusPacket(from: 0x0BEE_F003, status: "Ghost"))
		await mesh.flushDebouncedSaves()
		let context = ModelContext(container)
		let count = try context.fetchCount(FetchDescriptor<NodeInfoEntity>())
		#expect(count == 0)
	}

	@Test func moduleConfigPacketCreatesTheEntityTheFormNeeds() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		try seedNode(context, num: 0x0BEE_F004)

		var config = ModuleConfig.StatusMessageConfig()
		config.nodeStatus = "Configured status"
		let mesh = MeshPackets(modelContainer: container)
		await mesh.upsertStatusMessageModuleConfigPacket(config: config, nodeNum: 0x0BEE_F004)
		await mesh.flushDebouncedSaves()

		let num: Int64 = 0x0BEE_F004
		let node = try #require(try context.fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		).first)
		// The editor form is disabled while statusMessageConfig is nil, so this
		// entity existing after the config dump is what makes the screen usable.
		#expect(node.statusMessageConfig != nil)
		#expect(node.statusMessageConfig?.nodeStatus == "Configured status")
	}
}
