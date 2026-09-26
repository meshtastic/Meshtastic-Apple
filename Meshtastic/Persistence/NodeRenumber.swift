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

		do {
			try rewrite(from: oldNum, to: newNum, in: context)
			try context.save()
			Logger.data.info("💾 [Database] Renumbered \(oldNum.toHex(), privacy: .public) to \(newNum.toHex(), privacy: .public)")
			return true
		} catch {
			// The whole rewrite lands in the one save above, so a failure anywhere — a fetch
			// as much as the save — leaves the store on the old number instead of half moved.
			// The rollback drops the edits still sitting unsaved in the context; without it the
			// next unrelated save would commit them.
			context.rollback()
			Logger.data.error("💾 [Database] Renumbering \(oldNum.toHex(), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	/// Stages every edit in the context without saving, so the caller can commit or discard
	/// the whole rewrite at once.
	private static func rewrite(from oldNum: Int64, to newNum: Int64, in context: ModelContext) throws {
		try foldExistingRows(from: oldNum, to: newNum, in: context)

		// The node itself.
		if let user = try fetchUser(num: oldNum, in: context) {
			user.num = newNum
			user.userId = newNum.toHex()
			user.numString = String(newNum)
		}
		if let node = try fetchNode(num: oldNum, in: context) {
			node.num = newNum
			node.id = newNum
		}
		for myInfo in try fetchAll(MyInfoEntity.self, in: context) where myInfo.myNodeNum == oldNum {
			myInfo.myNodeNum = newNum
		}

		// Everything that stores a node number loose rather than as a relationship.
		for route in try fetchAll(TraceRouteEntity.self, in: context) {
			if route.fromNum == oldNum { route.fromNum = newNum }
			if route.toNum == oldNum { route.toNum = newNum }
			for hop in route.hops where hop.num == oldNum { hop.num = newNum }
			for snapshot in route.nodePositions where snapshot.num == oldNum { snapshot.num = newNum }
		}
		let relayed = try context.fetch(
			FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.relayNode == oldNum })
		)
		for message in relayed { message.relayNode = newNum }
		for waypoint in try fetchAll(WaypointEntity.self, in: context) {
			if waypoint.createdBy == oldNum { waypoint.createdBy = newNum }
			if waypoint.lastUpdatedBy == oldNum { waypoint.lastUpdatedBy = newNum }
		}
		for discovered in try fetchAll(DiscoveredNodeEntity.self, in: context) where discovered.nodeNum == oldNum {
			discovered.nodeNum = newNum
		}
		for beacon in try fetchAll(DiscoveredBeaconEntity.self, in: context) where beacon.nodeNum == oldNum {
			beacon.nodeNum = newNum
		}
		try rewriteMultiRadioRows(from: oldNum, to: newNum, in: context)
	}

	/// The feature-021 columns and keys that carry node numbers: message numbers and keys,
	/// per-radio observations and packet receptions. The number can be either the observed
	/// node or the local radio. Rows already stored under the new number lose to the old ones,
	/// the same way `foldExistingRows` keeps the old node.
	private static func rewriteMultiRadioRows(from oldNum: Int64, to newNum: Int64, in context: ModelContext) throws {
		let old: Int64? = oldNum
		let messages = try context.fetch(FetchDescriptor<MessageEntity>(
			predicate: #Predicate { $0.fromNum == old || $0.toNum == old || $0.localNodeNum == old }
		))
		for message in messages {
			if message.fromNum == oldNum {
				message.fromNum = newNum
				if message.messageKey != nil {
					message.messageKey = MessageEntity.key(fromNum: newNum, messageId: message.messageId)
				}
			}
			if message.toNum == oldNum { message.toNum = newNum }
			if message.localNodeNum == oldNum { message.localNodeNum = newNum }
		}

		let observations = try context.fetch(FetchDescriptor<NodeObservationEntity>(
			predicate: #Predicate { $0.radioNum == oldNum || $0.nodeNum == oldNum }
		))
		let targetObservationKeys = Set(observations.map {
			NodeObservationEntity.key(radioNum: swap($0.radioNum, oldNum, newNum), nodeNum: swap($0.nodeNum, oldNum, newNum))
		})
		for existing in try context.fetch(FetchDescriptor<NodeObservationEntity>(
			predicate: #Predicate { $0.radioNum == newNum || $0.nodeNum == newNum }
		)) where targetObservationKeys.contains(existing.key) {
			context.delete(existing)
		}
		for observation in observations {
			observation.radioNum = swap(observation.radioNum, oldNum, newNum)
			observation.nodeNum = swap(observation.nodeNum, oldNum, newNum)
			observation.key = NodeObservationEntity.key(radioNum: observation.radioNum, nodeNum: observation.nodeNum)
		}

		let receptions = try context.fetch(FetchDescriptor<PacketReceptionEntity>(
			predicate: #Predicate { $0.radioNum == oldNum || $0.fromNum == oldNum || $0.toNum == oldNum }
		))
		let targetReceptionKeys = Set(receptions.map {
			PacketReceptionEntity.key(radioNum: swap($0.radioNum, oldNum, newNum), fromNum: swap($0.fromNum, oldNum, newNum), packetId: $0.packetId)
		})
		for existing in try context.fetch(FetchDescriptor<PacketReceptionEntity>(
			predicate: #Predicate { $0.radioNum == newNum || $0.fromNum == newNum }
		)) where targetReceptionKeys.contains(existing.key) {
			context.delete(existing)
		}
		for reception in receptions {
			reception.radioNum = swap(reception.radioNum, oldNum, newNum)
			reception.fromNum = swap(reception.fromNum, oldNum, newNum)
			reception.toNum = swap(reception.toNum, oldNum, newNum)
			reception.key = PacketReceptionEntity.key(radioNum: reception.radioNum, fromNum: reception.fromNum, packetId: reception.packetId)
		}
	}

	private static func swap(_ value: Int64, _ oldNum: Int64, _ newNum: Int64) -> Int64 {
		value == oldNum ? newNum : value
	}

	/// The app can hear a radio on the mesh before it connects to it, so the new number may
	/// already have rows of its own. They have to go, because `num` is unique — but their
	/// messages move to the surviving node first so none are orphaned.
	private static func foldExistingRows(from oldNum: Int64, to newNum: Int64, in context: ModelContext) throws {
		guard let keeper = try fetchUser(num: oldNum, in: context) else { return }

		if let duplicate = try fetchUser(num: newNum, in: context), duplicate !== keeper {
			for message in duplicate.sentMessages { message.fromUser = keeper }
			for message in duplicate.receivedMessages { message.toUser = keeper }
			context.delete(duplicate)
		}
		if let duplicateNode = try fetchNode(num: newNum, in: context), duplicateNode !== keeper.userNode {
			context.delete(duplicateNode)
		}
	}

	// MARK: - Fetch helpers

	private static func fetchUser(num: Int64, in context: ModelContext) throws -> UserEntity? {
		try context.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == num })).first
	}

	private static func fetchNode(num: Int64, in context: ModelContext) throws -> NodeInfoEntity? {
		try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })).first
	}

	private static func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
		try context.fetch(FetchDescriptor<T>())
	}
}
