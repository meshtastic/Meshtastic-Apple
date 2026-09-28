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

	/// Runs the backfill to the end in one go, attributing old rows to `ownRadio` (T162): at launch,
	/// before a merge, and after a restore, rather than only in background passes, which a Mac
	/// that stays in front may never get. Rolls back and rethrows on failure.
	///
	/// Each chunk is saved, then the actor is given back before the next one, so packets every
	/// radio delivers meanwhile are handled between chunks instead of waiting for the whole
	/// table; a TCP or serial radio would otherwise miss its heartbeat answer and drop (T194).
	///
	/// `othersObserved` is whether other radios already had observations; decided here when not
	/// given. A radio joining gives the answer from before its first packet (T230).
	@discardableResult
	func drainMultiRadioBackfill(ownRadio: Int64, othersObserved given: Bool? = nil) async throws -> Int {
		var total = 0
		var chunks = 0
		do {
			// Decided once: packets let through between chunks create other radios' observations,
			// which mustn't stop this radio's for the rest of the nodes (T220).
			let othersObserved = try given ?? MultiRadioBackfill.otherRadiosHaveObservations(than: ownRadio, in: modelContext)
			while !invalidated {
				let filled = try MultiRadioBackfill.runChunk(in: modelContext, ownRadio: ownRadio, chunkSize: 2000, othersObserved: othersObserved).total
				guard filled > 0 else { break }
				total += filled
				chunks += 1
				guard chunks < 10_000 else { break }
				await Task.yield()
				// Packets handled while the actor was given back wrote to this same context; save
				// them before the next chunk, so a chunk that fails only rolls back itself (T205).
				savePendingChanges(caller: "drainMultiRadioBackfill")
			}
		} catch {
			modelContext.rollback()
			throw error
		}
		return total
	}

	/// Whether the store already holds `radioNum`'s data, so its backup would only be an older
	/// copy: the store's own radio, a radio connected with this version, or one with observations.
	/// A stray `MyInfoEntity` alone, which stores from before the multi-radio fix can carry,
	/// doesn't count, so it no longer blocks that radio's real backup (T166).
	func storeHoldsData(ofRadio radioNum: Int64, ownRadio: Int64) -> Bool {
		var descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == radioNum })
		descriptor.fetchLimit = 1
		guard let myInfo = try? modelContext.fetch(descriptor).first else { return false }
		if radioNum == ownRadio || myInfo.lastConnected != nil { return true }
		var observed = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum == radioNum })
		observed.fetchLimit = 1
		return ((try? modelContext.fetchCount(observed)) ?? 0) > 0
	}

	/// Whether radios other than `ownRadio` have observations, which stops the backfill creating
	/// `ownRadio`'s (T142).
	func otherRadiosHaveObservations(than ownRadio: Int64) -> Bool {
		(try? MultiRadioBackfill.otherRadiosHaveObservations(than: ownRadio, in: modelContext)) ?? true
	}

	/// Whether messages still wait for the backfill (a store from before feature 021, or a
	/// restored backup). Channel keys aren't counted: a radio without LoRa settings keeps its
	/// channels keyless, and they're set when its settings arrive (T144).
	func hasPendingBackfill() -> Bool {
		var messages = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.fromNum == nil })
		messages.fetchLimit = 1
		return ((try? modelContext.fetchCount(messages)) ?? 0) > 0
	}

	/// Merges each backup into the shared store, on the ingest actor so no packet write can race it.
	///
	/// The store's own backfill is drained first: the merge matches messages on `messageKey`, and a
	/// live row still waiting for its key would otherwise get a duplicate from the backup.
	///
	/// A backup for a radio the store already knows is skipped rather than merged. It can only be an
	/// older snapshot of what the store has, and merging it would bring back anything deleted since.
	func mergeBackups(_ backups: [PendingBackupMerge], ownRadio: Int64) async -> [String: BackupMergeOutcome] {
		var outcomes: [String: BackupMergeOutcome] = [:]
		guard !invalidated else { return outcomes }
		do {
			try await drainMultiRadioBackfill(ownRadio: ownRadio)
		} catch {
			Logger.backup.error("💥 [Merge] The store's backfill failed, so no backup was merged: \(error.localizedDescription, privacy: .public)")
			return outcomes
		}

		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		for backup in backups {
			guard !invalidated else { break }
			let radioNum = backup.radioNum
			guard !storeHoldsData(ofRadio: radioNum, ownRadio: ownRadio) else {
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
