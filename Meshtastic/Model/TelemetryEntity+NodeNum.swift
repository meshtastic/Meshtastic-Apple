//
//  TelemetryEntity+NodeNum.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//

import Foundation
import OSLog
import SwiftData

// Telemetry rows are tied to their node by `nodeNum`, not by the `nodeTelemetry` relationship.
// Setting the relationship makes SwiftData update `NodeInfoEntity.telemetries`, which loads every
// telemetry row the node has, and it did that on the main thread for nearly every packet. Rows
// saved before `nodeNum` existed only have the relationship; a one-time backfill copies the number
// across, and until it finishes the lookups below match either one.

extension TelemetryEntity {

	/// The node this row belongs to, from `nodeNum` or, for a row the backfill has not reached
	/// yet, from the relationship.
	var ownerNodeNum: Int64? {
		nodeNum != 0 ? nodeNum : nodeTelemetry?.num
	}

	/// All telemetry for one node.
	static func predicate(forNode nodeNum: Int64) -> Predicate<TelemetryEntity> {
		if TelemetryNodeNumBackfill.isComplete {
			return #Predicate<TelemetryEntity> { $0.nodeNum == nodeNum }
		}
		return #Predicate<TelemetryEntity> { $0.nodeNum == nodeNum || $0.nodeTelemetry?.num == nodeNum }
	}

	/// One metrics type for one node.
	static func predicate(forNode nodeNum: Int64, metricsType: Int32) -> Predicate<TelemetryEntity> {
		if TelemetryNodeNumBackfill.isComplete {
			return #Predicate<TelemetryEntity> { $0.nodeNum == nodeNum && $0.metricsType == metricsType }
		}
		return #Predicate<TelemetryEntity> {
			$0.metricsType == metricsType && ($0.nodeNum == nodeNum || $0.nodeTelemetry?.num == nodeNum)
		}
	}

	/// All telemetry for any of `nodeNums`.
	static func predicate(forNodes nodeNums: [Int64]) -> Predicate<TelemetryEntity> {
		if TelemetryNodeNumBackfill.isComplete {
			return #Predicate<TelemetryEntity> { nodeNums.contains($0.nodeNum) }
		}
		return #Predicate<TelemetryEntity> {
			nodeNums.contains($0.nodeNum) || ($0.nodeTelemetry.flatMap { nodeNums.contains($0.num) } ?? false)
		}
	}

	/// One metrics type for any of `nodeNums`.
	static func predicate(forNodes nodeNums: [Int64], metricsType: Int32) -> Predicate<TelemetryEntity> {
		if TelemetryNodeNumBackfill.isComplete {
			return #Predicate<TelemetryEntity> { $0.metricsType == metricsType && nodeNums.contains($0.nodeNum) }
		}
		return #Predicate<TelemetryEntity> {
			$0.metricsType == metricsType
				&& (nodeNums.contains($0.nodeNum) || ($0.nodeTelemetry.flatMap { nodeNums.contains($0.num) } ?? false))
		}
	}

	/// Deletes the telemetry of nodes that are being deleted. New rows have no relationship, so the
	/// node's `.nullify` rule never reaches them and they would be left behind. Rows are deleted one
	/// by one rather than with a batch delete, because older rows are still linked to a node that
	/// may be deleted in the same save. Does not save.
	static func deleteAll(forNodes nodeNums: [Int64], in context: ModelContext) {
		guard !nodeNums.isEmpty else { return }
		var descriptor = FetchDescriptor<TelemetryEntity>(predicate: predicate(forNodes: nodeNums))
		descriptor.propertiesToFetch = [\.nodeNum]
		do {
			for row in try context.fetch(descriptor) {
				context.delete(row)
			}
		} catch {
			Logger.data.error("💥 [TelemetryEntity] Failed to delete telemetry for removed nodes: \(error.localizedDescription, privacy: .public)")
		}
	}
}

/// Copies the node number onto telemetry rows saved before `TelemetryEntity.nodeNum` existed.
enum TelemetryNodeNumBackfill {

	static let completedKey = "telemetryNodeNumBackfillComplete"
	static let chunkSize = 500

	/// Once true, telemetry lookups use `nodeNum` alone.
	static var isComplete: Bool {
		get { UserDefaults.standard.bool(forKey: completedKey) }
		set { UserDefaults.standard.set(newValue, forKey: completedKey) }
	}

	/// Starts the backfill in the background unless it has already finished. It stops, without
	/// recording completion, if a database reset starts or the container is replaced, and tries
	/// again on the next launch.
	@MainActor
	static func startIfNeeded(persistence: PersistenceController, appState: AppState) {
		guard !isComplete, !persistence.isProvisionalPendingFirstUnlock else { return }
		let container = persistence.container
		let generation = persistence.containerGeneration
		let shouldContinue: @MainActor @Sendable () -> Bool = { [weak persistence, weak appState] in
			guard let persistence, let appState else { return false }
			return !appState.isDatabaseResetting && persistence.containerGeneration == generation
		}
		// Detached so the actor is created, and so runs, off the main thread.
		Task.detached(priority: .utility) {
			let worker = TelemetryNodeNumBackfillActor(modelContainer: container)
			if await worker.run(chunkSize: chunkSize, shouldContinue: shouldContinue) {
				isComplete = true
				Logger.data.info("💾 [TelemetryEntity] Node number backfill complete")
			}
		}
	}
}

@ModelActor
actor TelemetryNodeNumBackfillActor {

	/// Fills `nodeNum` from the relationship in chunks, saving each one. Returns true once no row
	/// is left to fill, false if it stopped early.
	func run(chunkSize: Int, shouldContinue: @MainActor @Sendable () -> Bool) async -> Bool {
		var filledTotal = 0
		while true {
			guard await shouldContinue() else {
				Logger.data.info("💾 [TelemetryEntity] Node number backfill paused after \(filledTotal, privacy: .public) rows")
				return false
			}
			var descriptor = FetchDescriptor<TelemetryEntity>(
				predicate: #Predicate<TelemetryEntity> {
					$0.nodeNum == 0 && $0.nodeTelemetry != nil && $0.nodeTelemetry?.num != 0
				}
			)
			descriptor.fetchLimit = chunkSize
			let rows: [TelemetryEntity]
			do {
				rows = try modelContext.fetch(descriptor)
			} catch {
				Logger.data.error("💥 [TelemetryEntity] Node number backfill fetch failed: \(error.localizedDescription, privacy: .public)")
				return false
			}
			var filled = 0
			for row in rows {
				if let num = row.nodeTelemetry?.num, num != 0 {
					row.nodeNum = num
					filled += 1
				}
			}
			// Nothing matched, or nothing more can be filled: done.
			guard filled > 0 else {
				if filledTotal > 0 {
					Logger.data.info("💾 [TelemetryEntity] Node number backfill filled \(filledTotal, privacy: .public) rows")
				}
				return true
			}
			do {
				try modelContext.save()
			} catch {
				modelContext.rollback()
				Logger.data.error("💥 [TelemetryEntity] Node number backfill save failed: \(error.localizedDescription, privacy: .public)")
				return false
			}
			filledTotal += filled
			await Task.yield()
		}
	}
}
