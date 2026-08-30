//
//  NodeAdministrationTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/30/26.
//
//  Covers NodeInfoEntity.hasBeenAdministered: set when an admin response carrying a
//  session passkey is ingested, and not set by the local config download or by
//  non-response admin variants.
//

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("Node administration tracking", .serialized)
@MainActor
struct NodeAdministrationTests {

	private func freshMesh() throws -> (MeshPackets, ModelContainer) {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		return (MeshPackets(modelContainer: container), container)
	}

	private func seedNode(num: Int64, in container: ModelContainer) throws {
		let context = ModelContext(container)
		let node = NodeInfoEntity()
		node.id = num
		node.num = num
		context.insert(node)
		try context.save()
	}

	private func fetchNode(num: Int64, in container: ModelContainer) throws -> NodeInfoEntity {
		let context = ModelContext(container)
		return try #require(context.fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		).first)
	}

	private func adminPacket(from num: Int64, message: AdminMessage) throws -> MeshPacket {
		var packet = MeshPacket()
		packet.from = UInt32(num)
		packet.decoded.portnum = .adminApp
		packet.decoded.payload = try message.serializedData()
		return packet
	}

	@Test func configResponseWithPasskeyMarksAdministered() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x11AA22
		try seedNode(num: num, in: container)

		var admin = AdminMessage()
		admin.sessionPasskey = Data([0xA5, 0x5A, 0x99, 0x01])
		var config = Config()
		config.device = Config.DeviceConfig()
		admin.getConfigResponse = config

		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin))

		let node = try fetchNode(num: num, in: container)
		#expect(node.hasBeenAdministered)
		#expect(node.sessionPasskey == Data([0xA5, 0x5A, 0x99, 0x01]))
		#expect(node.sessionExpiration != nil)
	}

	@Test func moduleConfigResponseWithPasskeyMarksAdministered() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x22BB33
		try seedNode(num: num, in: container)

		var admin = AdminMessage()
		admin.sessionPasskey = Data([0x01, 0x02, 0x03])
		var moduleConfig = ModuleConfig()
		moduleConfig.statusmessage = ModuleConfig.StatusMessageConfig()
		admin.getModuleConfigResponse = moduleConfig

		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin))

		let node = try fetchNode(num: num, in: container)
		#expect(node.hasBeenAdministered)
	}

	@Test func metadataResponseWithPasskeyMarksUnknownNode() async throws {
		// A metadata response is the first admin exchange when selecting a remote node,
		// and its handler creates the node if it has never been heard.
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x33CC44

		var admin = AdminMessage()
		admin.sessionPasskey = Data([0x0F, 0xF0])
		var metadata = DeviceMetadata()
		metadata.firmwareVersion = "2.8.0"
		admin.getDeviceMetadataResponse = metadata

		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin))

		let node = try fetchNode(num: num, in: container)
		#expect(node.hasBeenAdministered)
	}

	@Test func responseWithoutPasskeyDoesNotMark() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x44DD55
		try seedNode(num: num, in: container)

		var admin = AdminMessage()
		var config = Config()
		config.device = Config.DeviceConfig()
		admin.getConfigResponse = config

		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin))

		let node = try fetchNode(num: num, in: container)
		#expect(!node.hasBeenAdministered)
	}

	@Test func localConfigDownloadDoesNotMark() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x55EE66
		try seedNode(num: num, in: container)

		var config = Config()
		config.device = Config.DeviceConfig()
		await mesh.localConfig(config: config, nodeNum: num, nodeLongName: "Test Node")

		let node = try fetchNode(num: num, in: container)
		#expect(!node.hasBeenAdministered)
		// The local download still stamps the (empty) passkey as before.
		#expect(node.sessionPasskey == Data())
	}

	@Test func setConfigRequestWithPasskeyDoesNotMark() async throws {
		// Only response variants count — a set request is something we (or another
		// node) sent, not proof this node answered us.
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x66FF77
		try seedNode(num: num, in: container)

		var admin = AdminMessage()
		admin.sessionPasskey = Data([0x09, 0x09])
		var config = Config()
		config.device = Config.DeviceConfig()
		admin.setConfig = config

		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin))

		let node = try fetchNode(num: num, in: container)
		#expect(!node.hasBeenAdministered)
	}

	@Test func markIsNeverCleared() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x77AA88
		try seedNode(num: num, in: container)

		var withPasskey = AdminMessage()
		withPasskey.sessionPasskey = Data([0x01])
		var config = Config()
		config.device = Config.DeviceConfig()
		withPasskey.getConfigResponse = config
		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: withPasskey))

		// A later response without a passkey must not clear the flag.
		var withoutPasskey = AdminMessage()
		withoutPasskey.getConfigResponse = config
		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: withoutPasskey))

		let node = try fetchNode(num: num, in: container)
		#expect(node.hasBeenAdministered)
	}
}
