//
//  ShowcaseNodeSnapshot.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
@preconcurrency import SwiftData

/// What the showcase needs to know about one node, copied out of SwiftData so the scene never
/// holds a model object. Unlike the spatial map, nodes without a position are included.
struct ShowcaseNodeSnapshot: Identifiable, Equatable, Sendable {
	let id: Int64
	let shortName: String
	let longName: String
	/// The hardware model's name as stored, e.g. "TBEAM" or "T_ECHO"; nil when unknown.
	let hwModel: String?
	/// The hardware's display name when the catalog had one.
	let hardwareName: String?
	let role: DeviceRoles?
	let lastHeard: Date?
	let isOnline: Bool
	let isFavorite: Bool
	let viaMqtt: Bool
	let isConnectedRadio: Bool
	let hopsAway: Int
	let snr: Float
	let rssi: Int32
	let hasPosition: Bool
}

/// The order the showcase fills its places in: the connected radio, favorites, then everyone else
/// by when they were last heard, newest first (so online nodes come before offline ones).
enum ShowcaseNodeOrdering {
	static let limit = 500

	struct Key {
		let num: Int64
		let isFavorite: Bool
		let lastHeard: Date?
	}

	/// Indexes into `keys` in showcase order, at most `limit` of them.
	static func order(_ keys: [Key], connectedNodeNum: Int64?, limit: Int = limit) -> [Int] {
		let sorted = keys.indices.sorted { lhs, rhs in
			let left = keys[lhs], right = keys[rhs]
			let leftConnected = left.num == connectedNodeNum, rightConnected = right.num == connectedNodeNum
			if leftConnected != rightConnected { return leftConnected }
			if left.isFavorite != right.isFavorite { return left.isFavorite }
			switch (left.lastHeard, right.lastHeard) {
			case let (leftDate?, rightDate?) where leftDate != rightDate: return leftDate > rightDate
			case (.some, nil): return true
			case (nil, .some): return false
			default: return left.num < right.num
			}
		}
		return Array(sorted.prefix(limit))
	}
}

/// Reads the showcase's nodes on its own context, off the main actor. One fetch of every node that
/// isn't ignored; only the nodes that make the cut have their user and position read.
@ModelActor
actor ShowcaseSnapshotReader {
	struct Result: Equatable, Sendable {
		let nodes: [ShowcaseNodeSnapshot]
		/// Every node that isn't ignored, including those past the limit.
		let totalCount: Int
	}

	func read(connectedNodeNum: Int64?, limit: Int = ShowcaseNodeOrdering.limit, now: Date = Date()) -> Result {
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.ignored == false })
		let fetched = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.modelContext != nil && !$0.isDeleted }
		let keys = fetched.map { ShowcaseNodeOrdering.Key(num: $0.num, isFavorite: $0.favorite, lastHeard: $0.lastHeard) }
		let order = ShowcaseNodeOrdering.order(keys, connectedNodeNum: connectedNodeNum, limit: limit)
		let onlineSince = now.addingTimeInterval(-ShowcaseLayout.onlineWindow)
		let nodes = order.map { index -> ShowcaseNodeSnapshot in
			let node = fetched[index]
			let user = node.user
			return ShowcaseNodeSnapshot(
				id: node.num,
				shortName: user?.shortName ?? "?",
				longName: user?.longName ?? node.num.toHex(),
				hwModel: user?.hwModel,
				hardwareName: user?.hwDisplayName,
				role: user.flatMap { DeviceRoles(rawValue: Int($0.role)) },
				lastHeard: node.lastHeard,
				isOnline: node.lastHeard.map { $0 > onlineSince } ?? false,
				isFavorite: node.favorite,
				viaMqtt: node.viaMqtt,
				isConnectedRadio: node.num == connectedNodeNum,
				hopsAway: Int(node.hopsAway),
				snr: node.snr,
				rssi: node.rssi,
				// A nil link needs no query. Otherwise go through the accessor, which confirms
				// the row in the store (one keyed lookup) where the raw link can't.
				hasPosition: node.latestPositionCache != nil && node.latestPosition != nil
			)
		}
		return Result(nodes: nodes, totalCount: fetched.count)
	}
}
