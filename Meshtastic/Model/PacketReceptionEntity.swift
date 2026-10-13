//
//  PacketReceptionEntity.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import SwiftData

/// One local radio's reception of one mesh packet (feature 021, D-08).
///
/// When several of the user's radios hear the same packet, the packet is stored once (a message,
/// a position, telemetry) and each radio's reception is recorded here: signal, hops, the relay it
/// came through. It is also how ingest tells a packet it has already handled from a new one.
/// Kept for a limited time (see `retentionDays` and `retentionRowLimit`).
@Model
final class PacketReceptionEntity {
	/// Retention: receptions older than this are pruned.
	static let retentionDays = 30
	/// Retention: at most this many rows are kept, newest first.
	static let retentionRowLimit = 50_000

	/// `"\(radioNum):\(fromNum):\(packetId)"`. Unique per radio, sender and packet.
	@Attribute(.unique) var key: String = ""
	/// Node number of the local radio that received the packet.
	var radioNum: Int64 = 0
	/// Node number of the sender.
	var fromNum: Int64 = 0
	/// The mesh packet id. Only unique per sender, which is why the key includes `fromNum`.
	var packetId: Int64 = 0
	var toNum: Int64 = 0
	var portNum: Int32 = 0
	/// The receiving radio's channel slot.
	var channel: Int32 = 0
	var rxTime: Date?
	var snr: Float = 0.0
	var rssi: Int32 = 0
	var hopStart: Int32 = 0
	var hopLimit: Int32 = 0
	/// Last byte of the node that relayed the packet to this radio, 0 when unknown.
	var relayNode: Int64 = 0
	var viaMqtt: Bool = false

	init() {}

	init(radioNum: Int64, fromNum: Int64, packetId: Int64) {
		self.key = Self.key(radioNum: radioNum, fromNum: fromNum, packetId: packetId)
		self.radioNum = radioNum
		self.fromNum = fromNum
		self.packetId = packetId
	}

	/// Hops the packet travelled to reach this radio, or nil when the sender's firmware does not
	/// report a starting hop count.
	var hopsAway: Int32? {
		guard hopStart > 0, hopStart >= hopLimit else { return nil }
		return hopStart - hopLimit
	}

	static func key(radioNum: Int64, fromNum: Int64, packetId: Int64) -> String {
		"\(radioNum):\(fromNum):\(packetId)"
	}

	/// Deletes up to `limit` receptions that are past retention: older than `maxAgeDays`, or
	/// beyond the newest `rowLimit` rows. Does not save. Returns how many it deleted, so a caller
	/// can run it in chunks until it returns 0.
	@discardableResult
	static func prune(
		in context: ModelContext,
		now: Date = .now,
		maxAgeDays: Int = retentionDays,
		rowLimit: Int = retentionRowLimit,
		limit: Int = 1_000
	) throws -> Int {
		let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
		var expired = FetchDescriptor<PacketReceptionEntity>(predicate: #Predicate { ($0.rxTime ?? cutoff) < cutoff })
		expired.fetchLimit = limit
		let old = try context.fetch(expired)
		for reception in old { context.delete(reception) }
		guard old.isEmpty else { return old.count }

		let excess = try context.fetchCount(FetchDescriptor<PacketReceptionEntity>()) - rowLimit
		guard excess > 0 else { return 0 }
		var oldest = FetchDescriptor<PacketReceptionEntity>(sortBy: [SortDescriptor(\.rxTime)])
		oldest.fetchLimit = min(excess, limit)
		let overflow = try context.fetch(oldest)
		for reception in overflow { context.delete(reception) }
		return overflow.count
	}
}
