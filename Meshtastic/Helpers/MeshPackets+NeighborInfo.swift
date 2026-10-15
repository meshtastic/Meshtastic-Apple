//
//  MeshPackets+NeighborInfo.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//

import Foundation
import MeshtasticProtobufs
import OSLog
import SwiftData

extension MeshPackets {

	/// Rows are kept at least this long, or three of the reporter's intervals if that is longer.
	static let neighborLinkMinimumAge: TimeInterval = 24 * 60 * 60
	/// About 200 reporters with a full list of 10. Real meshes come nowhere near this.
	static let maxNeighborLinks = 2_000

	/// Saves a Neighbor Info report. The report replaces everything stored for its reporter:
	/// listed neighbors are updated or added, and neighbors no longer listed are removed.
	///
	/// The reporter is the packet's sender. `last_sent_by_id` is ignored, because on 2.7 and 2.8
	/// every radio that passes the report on overwrites it with its own number.
	func neighborInfoPacket(_ neighborInfo: NeighborInfo, packet: MeshPacket, now: Date = Date()) {
		let reporter = Int64(packet.from)
		guard reporter != 0 else { return }
		if neighborInfo.nodeID != 0 && neighborInfo.nodeID != packet.from {
			Logger.mesh.warning("[Neighbor Info] Report from \(packet.from.toHex(), privacy: .public) names \(neighborInfo.nodeID.toHex(), privacy: .public) as the reporter, ignoring it")
			return
		}

		// Node 0 is the placeholder a node sends when it asks for a report.
		var listed: [Int64: Float] = [:]
		for neighbor in neighborInfo.neighbors where neighbor.nodeID != 0 && Int64(neighbor.nodeID) != reporter {
			listed[Int64(neighbor.nodeID)] = neighbor.snr
		}
		// The firmware only sends a report when it has at least one neighbor, so an empty list
		// is a request, not a node saying it hears nobody.
		guard !listed.isEmpty else { return }

		let interval = Int32(clamping: neighborInfo.nodeBroadcastIntervalSecs)
		guard let receivedAt = Self.neighborReportTime(packet: packet, interval: interval, now: now) else {
			Logger.mesh.info("[Neighbor Info] Skipped a report from \(packet.from.toHex(), privacy: .public) that is too old to keep")
			return
		}
		do {
			let existing = try modelContext.fetch(FetchDescriptor<NeighborLinkEntity>(
				predicate: #Predicate { $0.reporterNum == reporter }
			))
			// A report the radio replays after the node database can be older than what we have.
			if existing.contains(where: { $0.receivedAt > receivedAt }) {
				Logger.mesh.info("[Neighbor Info] Skipped an older report from \(packet.from.toHex(), privacy: .public)")
				return
			}
			for row in existing {
				if let snr = listed.removeValue(forKey: row.neighborNum) {
					row.snr = snr
					row.receivedAt = receivedAt
					row.reporterIntervalSecs = interval
					row.viaMqtt = packet.viaMqtt
				} else {
					modelContext.delete(row)
				}
			}
			for (neighbor, snr) in listed {
				let row = NeighborLinkEntity()
				row.key = NeighborLinkEntity.key(reporter: reporter, neighbor: neighbor)
				row.reporterNum = reporter
				row.neighborNum = neighbor
				row.snr = snr
				row.receivedAt = receivedAt
				row.reporterIntervalSecs = interval
				row.viaMqtt = packet.viaMqtt
				modelContext.insert(row)
			}
			savePendingChanges()
		} catch {
			Logger.data.error("💥 [NeighborLinkEntity] Failed to save a report from \(packet.from.toHex(), privacy: .public): \(error.localizedDescription, privacy: .public)")
		}
	}

	/// When the radio received the report, if it says and the time is believable; otherwise now.
	/// Nil when the radio's time says the report is older than pruning would keep, as happens
	/// when the radio replays old packets after the node database.
	nonisolated static func neighborReportTime(packet: MeshPacket, interval: Int32, now: Date) -> Date? {
		// Before 2020 means the radio's clock was never set.
		guard packet.rxTime > 1_577_836_800 else { return now }
		let rxTime = Date(timeIntervalSince1970: TimeInterval(packet.rxTime))
		guard rxTime <= now else { return now }
		guard now.timeIntervalSince(rxTime) <= neighborLinkMaxAge(interval: interval) else { return nil }
		return rxTime
	}

	/// How long a row is kept: a day, or three of the reporter's intervals if that is longer.
	nonisolated static func neighborLinkMaxAge(interval: Int32) -> TimeInterval {
		Swift.max(neighborLinkMinimumAge, 3 * TimeInterval(interval))
	}

	/// Deletes rows older than a day, or three of the reporter's intervals if that is longer,
	/// then the oldest rows over `cap`. Does not save. Returns how many rows went.
	///
	/// Reads every row in one fetch and decides in memory, newest first. The table is capped at a
	/// couple of thousand small rows and this runs at connect and on backgrounding, not per packet.
	@discardableResult
	func pruneNeighborLinks(now: Date = Date(), cap: Int = MeshPackets.maxNeighborLinks) -> Int {
		let rows: [NeighborLinkEntity]
		do {
			rows = try modelContext.fetch(FetchDescriptor<NeighborLinkEntity>())
				.sorted { $0.receivedAt > $1.receivedAt }
		} catch {
			Logger.data.error("💥 [NeighborLinkEntity] Failed to prune neighbor links: \(error.localizedDescription, privacy: .public)")
			return 0
		}
		var kept = 0
		var removed = 0
		for row in rows {
			if now.timeIntervalSince(row.receivedAt) > Self.neighborLinkMaxAge(interval: row.reporterIntervalSecs) || kept >= cap {
				modelContext.delete(row)
				removed += 1
			} else {
				kept += 1
			}
		}
		if removed > 0 {
			Logger.data.info("🗄️ [NeighborLinkEntity] Pruned \(removed, privacy: .public) neighbor link(s)")
		}
		return removed
	}

	/// Prunes and saves. Called once the connection is up.
	func pruneNeighborLinksAndSave() {
		guard pruneNeighborLinks() > 0 else { return }
		savePendingChanges()
	}
}
