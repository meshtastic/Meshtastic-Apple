//
//  NeighborLinkEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//

import Foundation
import OSLog
import SwiftData

/// One entry from a Neighbor Info report: `reporterNum` heard `neighborNum` directly, at `snr` dB.
///
/// The link is one way. It is the neighbor's signal as the reporter hears it, not the other way
/// round. Nodes are stored as plain numbers with no relationship to `NodeInfoEntity`, so saving a
/// report never loads a node's other rows, and the rows survive a node being deleted or
/// renumbered until the clean-up code below removes or rewrites them.
@Model
final class NeighborLinkEntity {
	/// `"reporterNum:neighborNum"`, so each reporter has at most one row per neighbor.
	@Attribute(.unique) var key: String = ""
	var reporterNum: Int64 = 0
	var neighborNum: Int64 = 0
	/// SNR in dB, measured by the reporter.
	var snr: Float = 0
	/// When the report arrived. Reports don't say how old each entry is.
	var receivedAt: Date = Date.distantPast
	/// How often the reporter says it sends a report. Used to decide when a row is too old.
	var reporterIntervalSecs: Int32 = 0
	/// Whether the report reached us over MQTT rather than from the radio's own LoRa.
	var viaMqtt: Bool = false

	init() {}

	static func key(reporter: Int64, neighbor: Int64) -> String {
		"\(reporter):\(neighbor)"
	}

	/// Rows that mention any of `nodeNums`, on either side.
	static func predicate(involving nodeNums: [Int64]) -> Predicate<NeighborLinkEntity> {
		#Predicate<NeighborLinkEntity> {
			nodeNums.contains($0.reporterNum) || nodeNums.contains($0.neighborNum)
		}
	}

	/// Deletes the rows of nodes that are being deleted. Does not save.
	static func deleteAll(forNodes nodeNums: [Int64], in context: ModelContext) {
		guard !nodeNums.isEmpty else { return }
		do {
			for row in try context.fetch(FetchDescriptor(predicate: predicate(involving: nodeNums))) {
				context.delete(row)
			}
		} catch {
			Logger.data.error("💥 [NeighborLinkEntity] Failed to delete neighbor links for removed nodes: \(error.localizedDescription, privacy: .public)")
		}
	}
}
