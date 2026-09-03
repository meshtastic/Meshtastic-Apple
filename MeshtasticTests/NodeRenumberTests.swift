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
		defer { cleanUp(context) }
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

		// Heard during a discovery scan, before the upgrade.
		let discovered = DiscoveredNodeEntity()
		discovered.nodeNum = old
		context.insert(discovered)

		let beacon = DiscoveredBeaconEntity()
		beacon.nodeNum = old
		context.insert(beacon)

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
		#expect(discovered.nodeNum == new)
		#expect(beacon.nodeNum == new)
		// The node keeps its history rather than starting over.
		#expect(user.sentMessages.contains { $0.messageId == 90_001 })

		// Read it back from a context that saw none of the edits, so this proves the rewrite
		// was written to the store rather than just applied to instances in memory.
		let fresh = makeContext()
		let stored = try fresh.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == new }))
		#expect(stored.count == 1)
		#expect(stored.first?.longName == "Test Radio")
		let storedRoute = try fresh.fetch(FetchDescriptor<TraceRouteEntity>(predicate: #Predicate { $0.id == 90_002 })).first
		#expect(storedRoute?.fromNum == new)
		let goneUnderOldNumber = try fresh.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == old }))
		#expect(goneUnderOldNumber.isEmpty)
	}

	@Test("Rows already stored under the new number are folded in, not orphaned")
	func foldsRowsAlreadyUnderTheNewNumber() throws {
		let context = makeContext()
		defer { cleanUp(context) }
		let old = Self.oldNum + 0x10
		let new = Self.newNum + 0x10

		let keeper = UserEntity()
		keeper.num = old
		keeper.userId = old.toHex()
		keeper.longName = "The Radio With The History"
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
		heardOnMesh.longName = "Heard On Mesh"
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

		let addressed = MessageEntity()
		addressed.messageId = 90_011
		addressed.messagePayload = "sent to it after the upgrade"
		addressed.toUser = heardOnMesh
		context.insert(addressed)

		try context.save()

		#expect(NodeRenumber.apply(from: old, to: new, in: context))

		let fresh = makeContext()
		let users = try fresh.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == new }))
		#expect(users.count == 1, "one node, not two")
		#expect(users.first?.longName == "The Radio With The History", "the row with the history is the one that survives")
		let nodes = try fresh.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == new }))
		#expect(nodes.count == 1)

		let sent = try fresh.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == 90_010 })).first
		#expect(sent != nil, "the message that arrived under the new number is kept")
		#expect(sent?.fromUser?.num == new)
		#expect(sent?.fromUser?.longName == "The Radio With The History")

		let received = try fresh.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == 90_011 })).first
		#expect(received != nil, "a message addressed to the new number is kept too")
		#expect(received?.toUser?.num == new)
		#expect(received?.toUser?.longName == "The Radio With The History")
	}

	@Test("Refuses a no-op or a zero node number")
	func refusesNonsense() throws {
		let context = makeContext()
		defer { cleanUp(context) }

		let user = UserEntity()
		user.num = Self.oldNum + 0x20
		user.userId = user.num.toHex()
		context.insert(user)
		try context.save()

		let seeded = user.num
		#expect(!NodeRenumber.apply(from: seeded, to: seeded, in: context))
		#expect(!NodeRenumber.apply(from: 0, to: seeded, in: context))
		#expect(!NodeRenumber.apply(from: seeded, to: 0, in: context))

		// A refused call changes nothing.
		#expect(user.num == seeded)
		let fresh = makeContext()
		let stored = try fresh.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == seeded }))
		#expect(stored.count == 1, "the seeded row is still there under its own number")
	}

	/// The container is shared with every other suite, so leave nothing behind.
	private func cleanUp(_ context: ModelContext) {
		let range: (Int64) -> Bool = { $0 > 0x0BAD_0000 && $0 < 0x0BAE_0000 }
		for user in (try? context.fetch(FetchDescriptor<UserEntity>())) ?? [] where range(user.num) {
			context.delete(user)
		}
		for node in (try? context.fetch(FetchDescriptor<NodeInfoEntity>())) ?? [] where range(node.num) {
			context.delete(node)
		}
		for myInfo in (try? context.fetch(FetchDescriptor<MyInfoEntity>())) ?? [] where range(myInfo.myNodeNum) {
			context.delete(myInfo)
		}
		for discovered in (try? context.fetch(FetchDescriptor<DiscoveredNodeEntity>())) ?? [] where range(discovered.nodeNum) {
			context.delete(discovered)
		}
		for beacon in (try? context.fetch(FetchDescriptor<DiscoveredBeaconEntity>())) ?? [] where range(beacon.nodeNum) {
			context.delete(beacon)
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
