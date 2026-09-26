//
//  MeshPackets+BackupMerge.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import OSLog
import SwiftData

// MARK: - Backup merge (feature 021, D-09, T030)

extension MeshPackets {

	/// One backup waiting to be merged: the radio it belongs to and its store file.
	struct PendingBackupMerge: Sendable {
		let key: String
		let radioNum: Int64
		let storeURL: URL
	}

	enum BackupMergeOutcome: Sendable, Equatable {
		/// Merged; `rows` were added.
		case merged(rows: Int)
		/// The shared store already holds this radio, so the backup is an older copy of data it has.
		case alreadyKnown
		case failed(String)
	}

	/// Merges each backup into the shared store, on the ingest actor so no packet write can race it.
	///
	/// The store's own backfill is drained first: the merge matches messages on `messageKey`, and a
	/// live row still waiting for its key would otherwise get a duplicate from the backup.
	///
	/// A backup for a radio the store already knows is skipped rather than merged. It can only be an
	/// older snapshot of what the store has, and merging it would bring back anything deleted since.
	func mergeBackups(_ backups: [PendingBackupMerge], ownRadio: Int64) -> [String: BackupMergeOutcome] {
		var outcomes: [String: BackupMergeOutcome] = [:]
		guard !invalidated else { return outcomes }
		do {
			var chunks = 0
			while try MultiRadioBackfill.runChunk(in: modelContext, ownRadio: ownRadio, chunkSize: 2000).total > 0 {
				chunks += 1
				guard chunks < 10_000 else { break }
			}
		} catch {
			modelContext.rollback()
			Logger.backup.error("💥 [Merge] The store's backfill failed, so no backup was merged: \(error.localizedDescription, privacy: .public)")
			return outcomes
		}

		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		for backup in backups {
			guard !invalidated else { break }
			let radioNum = backup.radioNum
			let known = (try? modelContext.fetchCount(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == radioNum }))) ?? 0
			guard known == 0 else {
				outcomes[backup.key] = .alreadyKnown
				continue
			}
			do {
				let container = try NodeBackupManager.stagedBackupContainer(for: backup.storeURL, schema: schema)
				let staged = ModelContext(container)
				staged.autosaveEnabled = false
				let result = try BackupMerge.merge(from: staged, radioNum: radioNum, into: modelContext)
				outcomes[backup.key] = .merged(rows: result.total)
			} catch {
				modelContext.rollback()
				Logger.backup.error("💥 [Merge] Merging the backup of \(radioNum.toHex(), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
				outcomes[backup.key] = .failed(error.localizedDescription)
			}
		}
		return outcomes
	}
}
