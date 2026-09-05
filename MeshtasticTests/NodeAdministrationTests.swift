//
//  NodeAdministrationTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/30/26.
//
//  Covers NodeInfoEntity.hasBeenAdministered: set when a correlated admin response
//  carrying a session passkey is ingested, and not set by the local config download,
//  non-response admin variants, or uncorrelated/unsolicited responses. Also covers
//  the hasLiveAdminSession and firmwareSupportsStatusMessage gates the editor uses.
//

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("Node administration tracking", .serialized)
@MainActor
struct NodeAdministrationTests {

	/// The connected node's number — admin responses are addressed to it.
	private static let myNum: Int64 = 0x0BEEF

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

	private func adminPacket(
		from num: Int64,
		message: AdminMessage,
		to: Int64 = NodeAdministrationTests.myNum,
		requestID: UInt32 = 4242
	) throws -> MeshPacket {
		var packet = MeshPacket()
		packet.from = UInt32(num)
		packet.to = UInt32(to)
		packet.decoded.portnum = .adminApp
		packet.decoded.payload = try message.serializedData()
		packet.decoded.requestID = requestID
		return packet
	}

	private func deviceConfigResponse(passkey: Data?) -> AdminMessage {
		var admin = AdminMessage()
		if let passkey {
			admin.sessionPasskey = passkey
		}
		var config = Config()
		config.device = Config.DeviceConfig()
		admin.getConfigResponse = config
		return admin
	}

	@Test func configResponseWithPasskeyMarksAdministered() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x11AA22
		try seedNode(num: num, in: container)

		let admin = deviceConfigResponse(passkey: Data([0xA5, 0x5A, 0x99, 0x01]))
		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin), connectedNodeNum: Self.myNum)

		let node = try fetchNode(num: num, in: container)
		#expect(node.hasBeenAdministered)
		#expect(node.sessionPasskey == Data([0xA5, 0x5A, 0x99, 0x01]))
		#expect(node.sessionExpiration != nil)
	}

	@Test func refetchMakesReceivedSessionVisibleToRetainedNode() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x13AB34
		try seedNode(num: num, in: container)
		let mainContext = container.mainContext
		let cachedNode = try #require(getNodeInfo(id: num, context: mainContext))
		#expect(!cachedNode.hasLiveAdminSession)

		var admin = AdminMessage()
		admin.sessionPasskey = Data([0xA5, 0x5A])
		var metadata = DeviceMetadata()
		metadata.firmwareVersion = "2.8.0"
		admin.getDeviceMetadataResponse = metadata
		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin), connectedNodeNum: Self.myNum)

		let result = await RemoteAdminSessionWaiter.wait(
			timeout: .milliseconds(20),
			isLive: { getNodeInfo(id: num, context: mainContext)?.hasLiveAdminSession == true },
			isConnected: { true }, targetIsCurrent: { true })
		#expect(result == .active)
		#expect(cachedNode.hasLiveAdminSession)
		#expect(cachedNode.metadata?.firmwareVersion == "2.8")
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

		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin), connectedNodeNum: Self.myNum)

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

		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin), connectedNodeNum: Self.myNum)

		let node = try fetchNode(num: num, in: container)
		#expect(node.hasBeenAdministered)
	}

	@Test func responseWithoutPasskeyDoesNotMark() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x44DD55
		try seedNode(num: num, in: container)

		let admin = deviceConfigResponse(passkey: nil)
		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin), connectedNodeNum: Self.myNum)

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

		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin), connectedNodeNum: Self.myNum)

		let node = try fetchNode(num: num, in: container)
		#expect(!node.hasBeenAdministered)
	}

	@Test func uncorrelatedResponseDoesNotMark() async throws {
		// requestID == 0 means the message is not a reply to a request we sent.
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x77AA88
		try seedNode(num: num, in: container)

		let admin = deviceConfigResponse(passkey: Data([0x01]))
		await mesh.adminAppPacket(
			packet: try adminPacket(from: num, message: admin, requestID: 0),
			connectedNodeNum: Self.myNum
		)

		let node = try fetchNode(num: num, in: container)
		#expect(!node.hasBeenAdministered)
	}

	@Test func responseAddressedToAnotherNodeDoesNotMark() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x88BB99
		try seedNode(num: num, in: container)

		let admin = deviceConfigResponse(passkey: Data([0x01]))
		await mesh.adminAppPacket(
			packet: try adminPacket(from: num, message: admin, to: 0x0D00D),
			connectedNodeNum: Self.myNum
		)

		let node = try fetchNode(num: num, in: container)
		#expect(!node.hasBeenAdministered)
	}

	@Test func unknownConnectedNodeDoesNotMark() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0x99CC00
		try seedNode(num: num, in: container)

		let admin = deviceConfigResponse(passkey: Data([0x01]))
		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: admin), connectedNodeNum: nil)

		let node = try fetchNode(num: num, in: container)
		#expect(!node.hasBeenAdministered)
	}

	@Test func markIsNeverCleared() async throws {
		let (mesh, container) = try freshMesh()
		let num: Int64 = 0xAADD11
		try seedNode(num: num, in: container)

		let withPasskey = deviceConfigResponse(passkey: Data([0x01]))
		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: withPasskey), connectedNodeNum: Self.myNum)

		// A later response without a passkey must not clear the flag.
		let withoutPasskey = deviceConfigResponse(passkey: nil)
		await mesh.adminAppPacket(packet: try adminPacket(from: num, message: withoutPasskey), connectedNodeNum: Self.myNum)

		let node = try fetchNode(num: num, in: container)
		#expect(node.hasBeenAdministered)
	}
}

@Suite("Admin session and firmware gates", .serialized)
@MainActor
struct AdminSessionGateTests {

	private func freshNode() throws -> (NodeInfoEntity, ModelContext) {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let context = ModelContext(container)
		let node = NodeInfoEntity()
		node.num = 0x1234
		node.id = 0x1234
		context.insert(node)
		return (node, context)
	}

	@Test func liveSessionRequiresNonEmptyPasskeyAndFutureExpiration() throws {
		let (node, _) = try freshNode()
		node.sessionPasskey = Data([0x01, 0x02])
		node.sessionExpiration = Date().addingTimeInterval(300)
		#expect(node.hasLiveAdminSession)
	}

	@Test func emptyPasskeyIsNotALiveSession() throws {
		let (node, _) = try freshNode()
		node.sessionPasskey = Data()
		node.sessionExpiration = Date().addingTimeInterval(300)
		#expect(!node.hasLiveAdminSession)
	}

	@Test func expiredSessionIsNotLive() throws {
		let (node, _) = try freshNode()
		node.sessionPasskey = Data([0x01, 0x02])
		node.sessionExpiration = Date().addingTimeInterval(-1)
		#expect(!node.hasLiveAdminSession)
	}

	@Test func missingExpirationIsNotLive() throws {
		let (node, _) = try freshNode()
		node.sessionPasskey = Data([0x01, 0x02])
		node.sessionExpiration = nil
		#expect(!node.hasLiveAdminSession)
	}

	@Test func unknownFirmwareIsPermissive() throws {
		let (node, _) = try freshNode()
		#expect(node.firmwareSupportsStatusMessage)
	}

	@Test func olderFirmwareDoesNotSupportStatusMessage() throws {
		let (node, context) = try freshNode()
		let metadata = DeviceMetadataEntity()
		metadata.firmwareVersion = "2.7.15"
		context.insert(metadata)
		node.metadata = metadata
		#expect(!node.firmwareSupportsStatusMessage)
	}

	@Test func minimumFirmwareSupportsStatusMessage() throws {
		let (node, context) = try freshNode()
		let metadata = DeviceMetadataEntity()
		metadata.firmwareVersion = "2.8.0"
		context.insert(metadata)
		node.metadata = metadata
		#expect(node.firmwareSupportsStatusMessage)
	}

	@Test func newerFirmwareWithBuildHashSupportsStatusMessage() throws {
		let (node, context) = try freshNode()
		let metadata = DeviceMetadataEntity()
		metadata.firmwareVersion = "2.9.1.3a0c08b"
		context.insert(metadata)
		node.metadata = metadata
		#expect(node.firmwareSupportsStatusMessage)
	}
}
