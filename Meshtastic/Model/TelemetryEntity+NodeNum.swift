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

	// Before the backfill a row is a node's when its nodeNum matches or, for a row the backfill
	// hasn't reached, when its old relationship points at the node. Node 0 isn't a node, and every
	// unreached row has nodeNum 0, so a lookup for 0 matches nothing. Handling that here, outside
	// the predicates, keeps each one small enough for the compiler to type-check quickly; a
	// version with the node 0 case inside timed out on CI.

	/// No rows: the lookup for node 0.
	private static let noRows = #Predicate<TelemetryEntity> { _ in false }

	/// All telemetry for one node.
	static func predicate(forNode nodeNum: Int64) -> Predicate<TelemetryEntity> {
		guard nodeNum != 0 else { return noRows }
		if TelemetryNodeNumBackfill.isComplete {
			return #Predicate<TelemetryEntity> { $0.nodeNum == nodeNum }
		}
		return #Predicate<TelemetryEntity> { $0.nodeNum == nodeNum || $0.nodeTelemetry?.num == nodeNum }
	}

	/// One metrics type for one node.
	static func predicate(forNode nodeNum: Int64, metricsType: Int32) -> Predicate<TelemetryEntity> {
		guard nodeNum != 0 else { return noRows }
		if TelemetryNodeNumBackfill.isComplete {
			return #Predicate<TelemetryEntity> { $0.nodeNum == nodeNum && $0.metricsType == metricsType }
		}
		return #Predicate<TelemetryEntity> {
			$0.metricsType == metricsType && ($0.nodeNum == nodeNum || $0.nodeTelemetry?.num == nodeNum)
		}
	}

	/// All telemetry for any of `nodeNums`.
	static func predicate(forNodes nodeNums: [Int64]) -> Predicate<TelemetryEntity> {
		let nums = nodeNums.filter { $0 != 0 }
		guard !nums.isEmpty else { return noRows }
		if TelemetryNodeNumBackfill.isComplete {
			return #Predicate<TelemetryEntity> { nums.contains($0.nodeNum) }
		}
		return #Predicate<TelemetryEntity> {
			nums.contains($0.nodeNum) || ($0.nodeTelemetry.flatMap { nums.contains($0.num) } ?? false)
		}
	}

	/// One metrics type for any of `nodeNums`.
	static func predicate(forNodes nodeNums: [Int64], metricsType: Int32) -> Predicate<TelemetryEntity> {
		let nums = nodeNums.filter { $0 != 0 }
		guard !nums.isEmpty else { return noRows }
		if TelemetryNodeNumBackfill.isComplete {
			return #Predicate<TelemetryEntity> { $0.metricsType == metricsType && nums.contains($0.nodeNum) }
		}
		return #Predicate<TelemetryEntity> {
			$0.metricsType == metricsType
				&& (nums.contains($0.nodeNum) || ($0.nodeTelemetry.flatMap { nums.contains($0.num) } ?? false))
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
		// Detached so the actor is created, and called, off the main thread.
		Task.detached(priority: .utility) {
			let worker = TelemetryNodeNumBackfillActor(modelContainer: container)
			if await run(using: worker, chunkSize: chunkSize, shouldContinue: shouldContinue) {
				isComplete = true
				Logger.data.info("💾 [TelemetryEntity] Node number backfill complete")
			}
		}
	}

	/// Fills `nodeNum` in chunks until no row is left. Returns true once done, false if it stopped
	/// early. The check that it should go on runs here, between chunks, and not inside the actor:
	/// a model actor that awaits the main actor resumes its work on the main thread.
	static func run(
		using worker: TelemetryNodeNumBackfillActor,
		chunkSize: Int,
		shouldContinue: @MainActor @Sendable () -> Bool
	) async -> Bool {
		var filledTotal = 0
		while true {
			guard await shouldContinue() else {
				Logger.data.info("💾 [TelemetryEntity] Node number backfill paused after \(filledTotal, privacy: .public) rows")
				return false
			}
			guard let filled = await worker.fillChunk(limit: chunkSize) else { return false }
			guard filled > 0 else {
				if filledTotal > 0 {
					Logger.data.info("💾 [TelemetryEntity] Node number backfill filled \(filledTotal, privacy: .public) rows")
				}
				return true
			}
			filledTotal += filled
			await Task.yield()
		}
	}
}

@ModelActor
actor TelemetryNodeNumBackfillActor {

	/// Fills `nodeNum` from the relationship on up to `limit` rows and saves. Returns how many
	/// were filled (0 when none are left), or nil if the fetch or save failed.
	func fillChunk(limit: Int) -> Int? {
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> {
				$0.nodeNum == 0 && $0.nodeTelemetry != nil && $0.nodeTelemetry?.num != 0
			}
		)
		descriptor.fetchLimit = limit
		let rows: [TelemetryEntity]
		do {
			rows = try modelContext.fetch(descriptor)
		} catch {
			Logger.data.error("💥 [TelemetryEntity] Node number backfill fetch failed: \(error.localizedDescription, privacy: .public)")
			return nil
		}
		var filled = 0
		for row in rows {
			if let num = row.nodeTelemetry?.num, num != 0 {
				row.nodeNum = num
				filled += 1
			}
		}
		guard filled > 0 else { return 0 }
		do {
			try modelContext.save()
		} catch {
			modelContext.rollback()
			Logger.data.error("💥 [TelemetryEntity] Node number backfill save failed: \(error.localizedDescription, privacy: .public)")
			return nil
		}
		return filled
	}
}
