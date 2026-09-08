//
//  ConnectedNodeKeyTrustTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/7/26.
//

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

/// Covers the production routing in `MeshPackets.nodeInfoPacket`: the connected radio's own
/// user record accepts a changed key as ground truth, while every other node in the dump
/// keeps first-wins.
@Suite("Connected node key trust", .serialized)
@MainActor
struct ConnectedNodeKeyTrustTests {

	private let keyA = Data(repeating: 0x11, count: 32)
	private let keyB = Data(repeating: 0xAB, count: 32)

	private func makeNodeInfo(num: UInt32, publicKey: Data) -> NodeInfo {
		var user = User()
		user.id = "!\(String(num, radix: 16))"
		user.longName = "Node \(num)"
		user.shortName = String(num % 10000)
		user.publicKey = publicKey
		var nodeInfo = NodeInfo()
		nodeInfo.num = num
		nodeInfo.user = user
		return nodeInfo
	}

	@Test("the dump replaces the connected node's own key but not another node's")
	func dumpReplacesOwnKeyOnly() async throws {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let mesh = MeshPackets(modelContainer: container)
		let ownNum: UInt32 = 100
		let otherNum: UInt32 = 200

		// First dump stores keyA for both nodes.
		_ = await mesh.nodeInfoPacket(nodeInfo: makeNodeInfo(num: ownNum, publicKey: keyA), channel: 0, connectedNodeNum: Int64(ownNum))
		_ = await mesh.nodeInfoPacket(nodeInfo: makeNodeInfo(num: otherNum, publicKey: keyA), channel: 0, connectedNodeNum: Int64(ownNum))

		// The radio regenerated its keypair (2.8 upgrade or factory reset); the other node's
		// key change is a possible substitution and must be refused.
		_ = await mesh.nodeInfoPacket(nodeInfo: makeNodeInfo(num: ownNum, publicKey: keyB), channel: 0, connectedNodeNum: Int64(ownNum))
		_ = await mesh.nodeInfoPacket(nodeInfo: makeNodeInfo(num: otherNum, publicKey: keyB), channel: 0, connectedNodeNum: Int64(ownNum))

		let context = ModelContext(container)
		let own = Int64(ownNum)
		let other = Int64(otherNum)
		let ownUser = try #require(try context.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == own })).first)
		let otherUser = try #require(try context.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == other })).first)

		#expect(ownUser.publicKey == keyB)      // ground truth from the radio itself
		#expect(ownUser.keyMatch == true)
		#expect(ownUser.newPublicKey == nil)

		#expect(otherUser.publicKey == keyA)    // first-wins: stored key stands
		#expect(otherUser.keyMatch == false)
		#expect(otherUser.newPublicKey == keyB)
	}
}
