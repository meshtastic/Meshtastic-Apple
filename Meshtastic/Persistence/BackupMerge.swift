//
//  BackupMerge.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import OSLog
import SwiftData

/// Merges one radio's backup into the shared store (feature 021, D-09, T030).
///
/// Before the shared store, switching radios backed up the store, cleared it and restored the
/// next radio's backup, so each radio's history sits in its own backup. The merge brings it into
/// the one store every radio now shares:
/// 1. The backup is read through a staged, disposable copy, and `MultiRadioBackfill` runs on
///    that copy with the backup's radio as owner. Its messages then carry `messageKey` and
///    `localNodeNum`, and its nodes an observation for that radio.
/// 2. Rows are merged by key. What the shared store already has wins; only missing rows are
///    added, linked to the shared store's nodes and users. `lastHeard`/`firstHeard` widen, and a
///    user with no public key or names takes them from the backup.
///
/// Merging is idempotent: a second run adds nothing, so an interrupted merge resumes by running
/// again. The backup file itself is never changed.
enum BackupMerge {

	struct Result: Equatable {
		var nodes = 0
		var users = 0
		var radios = 0
		var channels = 0
		var messages = 0
		var positions = 0
		var telemetry = 0
		var observations = 0
		var receptions = 0
		var waypoints = 0
		var traceRoutes = 0

		var total: Int {
			nodes + users + radios + channels + messages + positions + telemetry + observations + receptions + waypoints + traceRoutes
		}
	}

	/// Merges `backup` (a staged copy of the backup of `radioNum`) into `live` and saves `live`.
	@discardableResult
	static func merge(from backup: ModelContext, radioNum: Int64, into live: ModelContext) throws -> Result {
		try backfill(backup, radioNum: radioNum)
		var result = Result()
		var nodes = try mergeNodes(from: backup, into: live, result: &result)
		let newNodeNums = nodes.inserted
		let users = try mergeUsers(from: backup, into: live, nodes: nodes.byNum, result: &result)
		try mergeRadios(from: backup, into: live, nodes: nodes.byNum, result: &result)
		try mergeNodeHistory(from: backup, into: live, nodes: &nodes.byNum, newNodeNums: newNodeNums, result: &result)
		try mergeMessages(from: backup, into: live, users: users, result: &result)
		try mergeKeyedRows(from: backup, into: live, result: &result)
		if live.hasChanges {
			try live.save()
		}
		Logger.backup.info("💾 Merged the backup of \(radioNum.toHex(), privacy: .public): \(result.total) rows added")
		return result
	}

	// MARK: - Steps

	private static func backfill(_ backup: ModelContext, radioNum: Int64) throws {
		var chunks = 0
		while try MultiRadioBackfill.runChunk(in: backup, ownRadio: radioNum, chunkSize: 2000).total > 0 {
			chunks += 1
			guard chunks < 10_000 else { break }
		}
	}

	private static func mergeNodes(from backup: ModelContext, into live: ModelContext, result: inout Result) throws -> (byNum: [Int64: NodeInfoEntity], inserted: Set<Int64>) {
		var byNum = Dictionary(try live.fetch(FetchDescriptor<NodeInfoEntity>()).map { ($0.num, $0) }, uniquingKeysWith: { first, _ in first })
		var inserted: Set<Int64> = []
		for src in try backup.fetch(FetchDescriptor<NodeInfoEntity>()) {
			if let existing = byNum[src.num] {
				existing.firstHeard = earliest(existing.firstHeard, src.firstHeard)
				existing.lastHeard = latest(existing.lastHeard, src.lastHeard)
				continue
			}
			let dst = NodeBackupManager.copied(src)
			live.insert(dst)
			byNum[dst.num] = dst
			inserted.insert(dst.num)
			result.nodes += 1
		}
		return (byNum, inserted)
	}

	private static func mergeUsers(from backup: ModelContext, into live: ModelContext, nodes: [Int64: NodeInfoEntity], result: inout Result) throws -> [Int64: UserEntity] {
		var byNum = Dictionary(try live.fetch(FetchDescriptor<UserEntity>()).map { ($0.num, $0) }, uniquingKeysWith: { first, _ in first })
		for src in try backup.fetch(FetchDescriptor<UserEntity>()) {
			if let existing = byNum[src.num] {
				// Fill gaps only. An existing key is never replaced (first key wins, as on the mesh).
				if existing.publicKey == nil, let key = src.publicKey {
					existing.publicKey = key
					existing.pkiEncrypted = src.pkiEncrypted
				}
				if existing.longName == nil { existing.longName = src.longName }
				if existing.shortName == nil { existing.shortName = src.shortName }
				if existing.userNode == nil, let nodeNum = src.userNode?.num { existing.userNode = nodes[nodeNum] }
				continue
			}
			let dst = NodeBackupManager.copied(src)
			if let nodeNum = src.userNode?.num { dst.userNode = nodes[nodeNum] }
			live.insert(dst)
			byNum[dst.num] = dst
			result.users += 1
		}
		return byNum
	}

	/// The backup's radio (its `MyInfoEntity` and channels), unless the shared store knows it.
	private static func mergeRadios(from backup: ModelContext, into live: ModelContext, nodes: [Int64: NodeInfoEntity], result: inout Result) throws {
		let known = Set(try live.fetch(FetchDescriptor<MyInfoEntity>()).map(\.myNodeNum))
		for src in try backup.fetch(FetchDescriptor<MyInfoEntity>()) where !known.contains(src.myNodeNum) {
			let dst = NodeBackupManager.copied(src)
			dst.myInfoNode = nodes[src.myNodeNum]
			live.insert(dst)
			result.radios += 1
			for srcChannel in src.channels {
				let channel = NodeBackupManager.copied(srcChannel)
				channel.myInfoChannel = dst
				live.insert(channel)
				result.channels += 1
			}
		}
	}

	/// Positions and telemetry by node, and metadata and PAX counts for nodes the store didn't have.
	private static func mergeNodeHistory(from backup: ModelContext, into live: ModelContext, nodes: inout [Int64: NodeInfoEntity], newNodeNums: Set<Int64>, result: inout Result) throws {
		for src in try backup.fetch(FetchDescriptor<NodeInfoEntity>()) {
			guard let node = nodes[src.num] else { continue }
			let isNew = newNodeNums.contains(src.num)
			let livePositions = isNew ? [] : node.positions
			let knownPositions = Set(livePositions.map { positionKey($0) })
			for position in src.positions where !knownPositions.contains(positionKey(position)) {
				let dst = NodeBackupManager.copied(position)
				// A new node keeps its latest position; an existing one keeps its own.
				dst.latest = isNew && position.latest
				dst.nodePosition = node
				if dst.latest { node.latestPositionCache = dst }
				live.insert(dst)
				result.positions += 1
			}
			let knownTelemetry = Set((isNew ? [] : node.telemetries).map { telemetryKey($0) })
			for telemetry in src.telemetries where !knownTelemetry.contains(telemetryKey(telemetry)) {
				let dst = NodeBackupManager.copied(telemetry)
				dst.nodeTelemetry = node
				live.insert(dst)
				result.telemetry += 1
			}
			guard isNew else { continue }
			if let metadata = src.metadata {
				let dst = NodeBackupManager.copied(metadata)
				dst.metadataNode = node
				live.insert(dst)
			}
			for pax in src.pax {
				let dst = NodeBackupManager.copied(pax)
				dst.paxNode = node
				live.insert(dst)
			}
		}
	}

	private static func mergeMessages(from backup: ModelContext, into live: ModelContext, users: [Int64: UserEntity], result: inout Result) throws {
		var liveKeys = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageKey != nil })
		liveKeys.propertiesToFetch = [\.messageKey]
		var known = Set(try live.fetch(liveKeys).compactMap(\.messageKey))
		for src in try backup.fetch(FetchDescriptor<MessageEntity>()) {
			if let key = src.messageKey {
				guard !known.contains(key) else { continue }
				known.insert(key)
			} else {
				// No sender, so no key: skip it if a row with the same id and time is already there.
				let messageId = src.messageId
				let timestamp = src.messageTimestamp
				let twin = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == messageId && $0.messageTimestamp == timestamp })
				guard (try live.fetchCount(twin)) == 0 else { continue }
			}
			let dst = NodeBackupManager.copied(src)
			if let fromNum = src.fromUser?.num { dst.fromUser = users[fromNum] }
			if let toNum = src.toUser?.num { dst.toUser = users[toNum] }
			live.insert(dst)
			result.messages += 1
		}
	}

	/// Observations, receptions, waypoints and trace routes: each has its own key.
	private static func mergeKeyedRows(from backup: ModelContext, into live: ModelContext, result: inout Result) throws {
		let observationKeys = Set(try live.fetch(FetchDescriptor<NodeObservationEntity>()).map(\.key))
		for src in try backup.fetch(FetchDescriptor<NodeObservationEntity>()) where !observationKeys.contains(src.key) {
			live.insert(NodeBackupManager.copied(src))
			result.observations += 1
		}
		let receptionKeys = Set(try live.fetch(FetchDescriptor<PacketReceptionEntity>()).map(\.key))
		for src in try backup.fetch(FetchDescriptor<PacketReceptionEntity>()) where !receptionKeys.contains(src.key) {
			live.insert(NodeBackupManager.copied(src))
			result.receptions += 1
		}
		let waypointIds = Set(try live.fetch(FetchDescriptor<WaypointEntity>()).map(\.id))
		for src in try backup.fetch(FetchDescriptor<WaypointEntity>()) where !waypointIds.contains(src.id) {
			live.insert(NodeBackupManager.copied(src))
			result.waypoints += 1
		}
		let liveNodes = Dictionary(try live.fetch(FetchDescriptor<NodeInfoEntity>()).map { ($0.num, $0) }, uniquingKeysWith: { first, _ in first })
		let traceRouteIds = Set(try live.fetch(FetchDescriptor<TraceRouteEntity>()).map(\.id))
		for src in try backup.fetch(FetchDescriptor<TraceRouteEntity>()) where !traceRouteIds.contains(src.id) {
			let dst = NodeBackupManager.copied(src)
			if let nodeNum = src.node?.num { dst.node = liveNodes[nodeNum] }
			live.insert(dst)
			NodeBackupManager.insertCopiedChildren(of: src, onto: dst, in: live)
			result.traceRoutes += 1
		}
	}

	// MARK: - Keys

	private static func positionKey(_ position: PositionEntity) -> String {
		"\(position.time?.timeIntervalSince1970 ?? 0):\(position.latitudeI):\(position.longitudeI)"
	}

	private static func telemetryKey(_ telemetry: TelemetryEntity) -> String {
		"\(telemetry.metricsType):\(telemetry.time?.timeIntervalSince1970 ?? 0)"
	}

	private static func earliest(_ lhs: Date?, _ rhs: Date?) -> Date? {
		guard let lhs else { return rhs }
		guard let rhs else { return lhs }
		return min(lhs, rhs)
	}

	private static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
		guard let lhs else { return rhs }
		guard let rhs else { return lhs }
		return max(lhs, rhs)
	}
}
