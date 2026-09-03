//
//  NodeRenumberTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/2/26.
//

import Testing
import Foundation
import SwiftData
@testable import Meshtastic

/// A radio that upgrades to 2.8 reports a different node number. Everything the app stored
/// for it is keyed to the old one, so it all has to move.
@Suite("Node renumber")
@MainActor
struct NodeRenumberTests {

	private static let oldNum: Int64 = 0x0BAD_0001
	private static let newNum: Int64 = 0x0BAD_0002

	private func makeContext() -> ModelContext {
		ModelContext(sharedModelContainer)
	}

	@Test("Everything keyed to the old number moves to the new one")
	func rewritesEveryReference() throws {
		let context = makeContext()
		let old = Self.oldNum
		let new = Self.newNum

		let user = UserEntity()
		user.num = old
		user.userId = old.toHex()
		user.longName = "Test Radio"
		context.insert(user)

		let node = NodeInfoEntity()
		node.num = old
		node.id = old
		node.user = user
		context.insert(node)

		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = old
		myInfo.peripheralId = "PERIPHERAL-1"
		context.insert(myInfo)

		let message = MessageEntity()
		message.messageId = 90_001
		message.messagePayload = "sent before the upgrade"
		message.relayNode = old
		message.fromUser = user
		context.insert(message)

		let route = TraceRouteEntity()
		route.id = 90_002
		route.fromNum = old
		route.toNum = 42
		context.insert(route)

		let hop = TraceRouteHopEntity()
		hop.num = old
		hop.traceRoute = route
		context.insert(hop)

		let snapshot = TraceRouteNodePositionEntity()
		snapshot.num = old
		snapshot.traceRoute = route
		context.insert(snapshot)

		let waypoint = WaypointEntity()
		waypoint.id = 90_003
		waypoint.createdBy = old
		waypoint.lastUpdatedBy = old
		context.insert(waypoint)

		try context.save()

		#expect(NodeRenumber.apply(from: old, to: new, in: context))

		#expect(user.num == new)
		#expect(user.userId == new.toHex())
		#expect(user.numString == String(new))
		#expect(node.num == new)
		#expect(node.id == new)
		#expect(myInfo.myNodeNum == new)
		#expect(message.relayNode == new)
		#expect(route.fromNum == new)
		#expect(route.toNum == 42, "an unrelated node number is left alone")
		#expect(hop.num == new)
		#expect(snapshot.num == new)
		#expect(waypoint.createdBy == new)
		#expect(waypoint.lastUpdatedBy == new)
		// The node keeps its history rather than starting over.
		#expect(user.sentMessages.contains { $0.messageId == 90_001 })

		cleanUp(context)
	}

	@Test("Rows already stored under the new number are folded in, not orphaned")
	func foldsRowsAlreadyUnderTheNewNumber() throws {
		let context = makeContext()
		let old = Self.oldNum + 0x10
		let new = Self.newNum + 0x10

		let keeper = UserEntity()
		keeper.num = old
		keeper.userId = old.toHex()
		context.insert(keeper)

		let keeperNode = NodeInfoEntity()
		keeperNode.num = old
		keeperNode.id = old
		keeperNode.user = keeper
		context.insert(keeperNode)

		// The app heard the radio on the mesh under its new number before connecting to it.
		let heardOnMesh = UserEntity()
		heardOnMesh.num = new
		heardOnMesh.userId = new.toHex()
		context.insert(heardOnMesh)

		let heardNode = NodeInfoEntity()
		heardNode.num = new
		heardNode.id = new
		heardNode.user = heardOnMesh
		context.insert(heardNode)

		let recent = MessageEntity()
		recent.messageId = 90_010
		recent.messagePayload = "arrived after the upgrade"
		recent.fromUser = heardOnMesh
		context.insert(recent)

		try context.save()

		#expect(NodeRenumber.apply(from: old, to: new, in: context))

		let users = try context.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == new }))
		#expect(users.count == 1, "one node, not two")
		let nodes = try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == new }))
		#expect(nodes.count == 1)

		let survivor = try context.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == 90_010 })).first
		#expect(survivor != nil, "the message that arrived under the new number is kept")
		#expect(survivor?.fromUser?.num == new)

		cleanUp(context)
	}

	@Test("Refuses a no-op or a zero node number")
	func refusesNonsense() {
		let context = makeContext()
		#expect(!NodeRenumber.apply(from: 5, to: 5, in: context))
		#expect(!NodeRenumber.apply(from: 0, to: 5, in: context))
		#expect(!NodeRenumber.apply(from: 5, to: 0, in: context))
	}

	/// The container is shared with every other suite, so leave nothing behind.
	private func cleanUp(_ context: ModelContext) {
		for user in (try? context.fetch(FetchDescriptor<UserEntity>())) ?? [] where user.num > 0x0BAD_0000 && user.num < 0x0BAE_0000 {
			context.delete(user)
		}
		for node in (try? context.fetch(FetchDescriptor<NodeInfoEntity>())) ?? [] where node.num > 0x0BAD_0000 && node.num < 0x0BAE_0000 {
			context.delete(node)
		}
		for myInfo in (try? context.fetch(FetchDescriptor<MyInfoEntity>())) ?? [] where myInfo.myNodeNum > 0x0BAD_0000 && myInfo.myNodeNum < 0x0BAE_0000 {
			context.delete(myInfo)
		}
		for message in (try? context.fetch(FetchDescriptor<MessageEntity>())) ?? [] where message.messageId >= 90_000 && message.messageId < 91_000 {
			context.delete(message)
		}
		for route in (try? context.fetch(FetchDescriptor<TraceRouteEntity>())) ?? [] where route.id >= 90_000 && route.id < 91_000 {
			context.delete(route)
		}
		for waypoint in (try? context.fetch(FetchDescriptor<WaypointEntity>())) ?? [] where waypoint.id >= 90_000 && waypoint.id < 91_000 {
			context.delete(waypoint)
		}
		try? context.save()
	}
}
