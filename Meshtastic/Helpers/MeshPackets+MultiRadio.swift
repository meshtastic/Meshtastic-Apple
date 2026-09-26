//
//  MeshPackets+MultiRadio.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import OSLog
import SwiftData

// MARK: - Multi-radio maintenance (feature 021)

extension MeshPackets {

	/// Runs the backfill and reception pruning in committed chunks until both are done, the
	/// budget is spent, or the app comes back to the foreground. Part of the background
	/// maintenance pass, for the same reason as the eviction: writes to many rows can't race a
	/// view rendering them there, and it can stop at any chunk and resume on the next pass.
	///
	/// `ownRadio` is the radio the store holds data for (0 when none has connected yet).
	func runMultiRadioMaintenance(ownRadio: Int64, budget: Duration = .seconds(3)) async {
		let deadline = ContinuousClock.now + budget
		func shouldContinue() -> Bool {
			!invalidated && !Self.appIsActive && !Self.backgroundTimeExpired && ContinuousClock.now < deadline
		}

		var backfilled = 0
		while shouldContinue() {
			do {
				let result = try MultiRadioBackfill.runChunk(in: modelContext, ownRadio: ownRadio)
				backfilled += result.total
				guard result.total > 0 else { break }
			} catch {
				modelContext.rollback()
				Logger.data.error("💥 [MultiRadio] Backfill chunk failed: \(error.localizedDescription, privacy: .public)")
				return
			}
			await Task.yield()
		}

		var pruned = 0
		while shouldContinue() {
			do {
				let removed = try PacketReceptionEntity.prune(in: modelContext)
				guard removed > 0 else { break }
				try modelContext.save()
				pruned += removed
			} catch {
				modelContext.rollback()
				Logger.data.error("💥 [MultiRadio] Reception prune failed: \(error.localizedDescription, privacy: .public)")
				return
			}
			await Task.yield()
		}

		if backfilled > 0 || pruned > 0 {
			Logger.data.info("🗄️ [MultiRadio] Backfilled \(backfilled) rows, pruned \(pruned) receptions")
		}
	}
}
