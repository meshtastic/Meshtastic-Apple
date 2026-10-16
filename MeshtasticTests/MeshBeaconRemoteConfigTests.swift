//
//  MeshBeaconRemoteConfigTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//
//  Covers storing a Mesh Beacon module config that a remote node sends back
//  in answer to a get-module-config admin request.
//

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("Mesh Beacon remote config", .serialized)
@MainActor
struct MeshBeaconRemoteConfigTests {

	private static let myNum: Int64 = 0x0BEEF

	@Test func moduleConfigResponseStoresMeshBeaconConfig() async throws {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let mesh = MeshPackets(modelContainer: container)
		let num: Int64 = 0x33CC44

		let seedContext = ModelContext(container)
		let seeded = NodeInfoEntity()
		seeded.id = num
		seeded.num = num
		seedContext.insert(seeded)
		try seedContext.save()

		var beacon = ModuleConfig.MeshBeaconConfig()
		beacon.broadcastMessage = "Join us"
		beacon.broadcastIntervalSecs = 7200
		var moduleConfig = ModuleConfig()
		moduleConfig.meshBeacon = beacon
		var admin = AdminMessage()
		admin.sessionPasskey = Data([0x0A, 0x0B, 0x0C])
		admin.getModuleConfigResponse = moduleConfig

		var packet = MeshPacket()
		packet.from = UInt32(num)
		packet.to = UInt32(Self.myNum)
		packet.decoded.portnum = .adminApp
		packet.decoded.payload = try admin.serializedData()
		packet.decoded.requestID = 4242

		await mesh.adminAppPacket(packet: packet, connectedNodeNum: Self.myNum)

		let node = try #require(ModelContext(container).fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		).first)
		let stored = try #require(node.meshBeaconConfig)
		#expect(stored.broadcastMessage == "Join us")
		#expect(stored.broadcastIntervalSecs == 7200)
		#expect(node.sessionPasskey == Data([0x0A, 0x0B, 0x0C]))
	}

	@Test func responseWithoutPasskeyKeepsStoredSession() async throws {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let mesh = MeshPackets(modelContainer: container)
		let num: Int64 = 0x44DD55
		let expiration = Date().addingTimeInterval(200)

		let seedContext = ModelContext(container)
		let seeded = NodeInfoEntity()
		seeded.id = num
		seeded.num = num
		seeded.sessionPasskey = Data([0x01, 0x02])
		seeded.sessionExpiration = expiration
		seedContext.insert(seeded)
		try seedContext.save()

		var moduleConfig = ModuleConfig()
		moduleConfig.meshBeacon = ModuleConfig.MeshBeaconConfig()
		var admin = AdminMessage()
		admin.getModuleConfigResponse = moduleConfig

		var packet = MeshPacket()
		packet.from = UInt32(num)
		packet.to = UInt32(Self.myNum)
		packet.decoded.portnum = .adminApp
		packet.decoded.payload = try admin.serializedData()
		packet.decoded.requestID = 4242

		await mesh.adminAppPacket(packet: packet, connectedNodeNum: Self.myNum)

		let node = try #require(ModelContext(container).fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		).first)
		#expect(node.meshBeaconConfig != nil)
		#expect(node.sessionPasskey == Data([0x01, 0x02]))
		#expect(node.sessionExpiration == expiration)
	}
}
