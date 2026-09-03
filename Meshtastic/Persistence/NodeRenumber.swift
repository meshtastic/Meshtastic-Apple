//
//  NodeRenumber.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/2/26.
//

import Foundation
import SwiftData
import OSLog

/// Moves everything the app stored for one node number onto another.
///
/// A radio that upgrades to 2.8 comes back with a different node number. It is the same
/// radio, and everything the app holds for it — messages, positions, telemetry, settings,
/// trace routes — is keyed to the number it used to report. Without this the app sees a
/// stranger where its own radio used to be.
enum NodeRenumber {

	/// Rewrites every reference to `oldNum` as `newNum`. Expects to run before any data for
	/// `newNum` is ingested, and saves the context itself.
	@discardableResult
	static func apply(from oldNum: Int64, to newNum: Int64, in context: ModelContext) -> Bool {
		guard oldNum != newNum, oldNum != 0, newNum != 0 else { return false }

		foldExistingRows(from: oldNum, to: newNum, in: context)

		// The node itself.
		if let user = fetchUser(num: oldNum, in: context) {
			user.num = newNum
			user.userId = newNum.toHex()
			user.numString = String(newNum)
		}
		if let node = fetchNode(num: oldNum, in: context) {
			node.num = newNum
			node.id = newNum
		}
		for myInfo in fetchAll(MyInfoEntity.self, in: context) where myInfo.myNodeNum == oldNum {
			myInfo.myNodeNum = newNum
		}

		// Everything that stores a node number loose rather than as a relationship.
		for route in fetchAll(TraceRouteEntity.self, in: context) {
			if route.fromNum == oldNum { route.fromNum = newNum }
			if route.toNum == oldNum { route.toNum = newNum }
			for hop in route.hops where hop.num == oldNum { hop.num = newNum }
			for snapshot in route.nodePositions where snapshot.num == oldNum { snapshot.num = newNum }
		}
		let relayed = (try? context.fetch(
			FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.relayNode == oldNum })
		)) ?? []
		for message in relayed { message.relayNode = newNum }
		for waypoint in fetchAll(WaypointEntity.self, in: context) {
			if waypoint.createdBy == oldNum { waypoint.createdBy = newNum }
			if waypoint.lastUpdatedBy == oldNum { waypoint.lastUpdatedBy = newNum }
		}
		for discovered in fetchAll(DiscoveredNodeEntity.self, in: context) where discovered.nodeNum == oldNum {
			discovered.nodeNum = newNum
		}
		for beacon in fetchAll(DiscoveredBeaconEntity.self, in: context) where beacon.nodeNum == oldNum {
			beacon.nodeNum = newNum
		}

		do {
			try context.save()
			Logger.data.info("💾 [Database] Renumbered \(oldNum.toHex(), privacy: .public) to \(newNum.toHex(), privacy: .public)")
			return true
		} catch {
			Logger.data.error("💾 [Database] Renumbering \(oldNum.toHex(), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	/// The app can hear a radio on the mesh before it connects to it, so the new number may
	/// already have rows of its own. They have to go before the rewrite, because `num` is
	/// unique — but their messages move to the surviving node first so none are orphaned.
	private static func foldExistingRows(from oldNum: Int64, to newNum: Int64, in context: ModelContext) {
		guard let keeper = fetchUser(num: oldNum, in: context) else { return }

		if let duplicate = fetchUser(num: newNum, in: context), duplicate !== keeper {
			for message in duplicate.sentMessages { message.fromUser = keeper }
			for message in duplicate.receivedMessages { message.toUser = keeper }
			context.delete(duplicate)
		}
		if let duplicateNode = fetchNode(num: newNum, in: context), duplicateNode !== keeper.userNode {
			context.delete(duplicateNode)
		}
		try? context.save()
	}

	// MARK: - Fetch helpers

	private static func fetchUser(num: Int64, in context: ModelContext) -> UserEntity? {
		try? context.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == num })).first
	}

	private static func fetchNode(num: Int64, in context: ModelContext) -> NodeInfoEntity? {
		try? context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })).first
	}

	private static func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
		(try? context.fetch(FetchDescriptor<T>())) ?? []
	}
}
