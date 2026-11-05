//
//  LegacyStoreRecovery.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/3/26.
//

import Foundation
import OSLog
import SwiftData

/// 2.7.25 gave the app an app group, and from then on SwiftData opened the store in the group
/// container. A device that already had a store kept it in the app's own Application Support,
/// where nothing read or wrote it again, so its history disappeared from the app. Backups kept
/// copying that file, filed under whichever radio was being switched away from.
///
/// Once, at launch, before any radio connects: the old store is merged into the live one when
/// they belong to the same radio (or the live one has no radio yet), and otherwise filed as that
/// radio's backup. Backups copied from it under other radios are removed. The old file is then
/// renamed so this does not run again; it is kept, not deleted. A failed attempt is retried on the
/// next launch, up to `maxAttempts` times.
enum LegacyStoreRecovery {

	enum Outcome: Equatable {
		case nothingToDo
		case merged
		case filedAsBackup(nodeNum: Int64)
		case failed
	}

	nonisolated static let attemptsKey = "legacyStoreRecoveryAttempts"
	nonisolated static let maxAttempts = 3
	nonisolated static let recoveredSuffix = ".recovered"

	/// Where the store was before the app group.
	nonisolated static var legacyStoreURL: URL {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Meshtastic.store")
	}

	@MainActor
	@discardableResult
	static func recoverIfNeeded(
		into container: ModelContainer,
		liveStoreURL: URL,
		legacyStoreURL: URL = legacyStoreURL,
		backups: NodeBackupManager = .shared,
		defaults: UserDefaults = .standard
	) -> Outcome {
		let fm = FileManager.default
		guard legacyStoreURL.standardizedFileURL != liveStoreURL.standardizedFileURL,
			  fm.fileExists(atPath: legacyStoreURL.path) else {
			return .nothingToDo
		}
		// Counted before the work, so a crash part way through can't repeat on every launch.
		// Success renames the old file, which ends the retries on its own.
		let attempts = defaults.integer(forKey: attemptsKey)
		guard attempts < maxAttempts else { return .nothingToDo }
		defaults.set(attempts + 1, forKey: attemptsKey)

		// When the old build last wrote the store. Backups made after it are copies of it.
		let frozenAt = ["", "-wal"].compactMap { suffix in
			(try? fm.attributesOfItem(atPath: legacyStoreURL.path + suffix))?[.modificationDate] as? Date
		}.max() ?? .distantPast

		do {
			let schema = Schema(versionedSchema: MeshtasticSchema.current)
			let legacyContainer = try NodeBackupManager.stagedBackupContainer(for: legacyStoreURL, schema: schema)
			let legacyContext = ModelContext(legacyContainer)
			legacyContext.autosaveEnabled = false

			let legacyMyInfos = try legacyContext.fetch(FetchDescriptor<MyInfoEntity>())
			let legacyNums = Set(legacyMyInfos.map(\.myNodeNum))
			let legacyDeviceKeys = Set(legacyMyInfos.compactMap { BackupKey.forDevice($0.deviceId) })

			let liveContext = container.mainContext
			let liveNums = Set(try liveContext.fetch(FetchDescriptor<MyInfoEntity>()).map(\.myNodeNum))

			// Copies of the old store filed under other radios hold the wrong radio's data. Removed
			// only once the old store's data is safe, in the live store or in its own backup.
			func removeCopiedBackups() {
				let removed = backups.removeBackups(
					createdAfter: frozenAt.addingTimeInterval(60),
					exceptNodes: legacyNums,
					exceptDevices: legacyDeviceKeys
				)
				if removed > 0 {
					Logger.backup.warning("💾 Removed \(removed) backups copied from the old store under other radios")
				}
			}

			if liveNums.isEmpty || !liveNums.isDisjoint(with: legacyNums) {
				try merge(from: legacyContext, into: liveContext)
				parkLegacyStore(at: legacyStoreURL)
				removeCopiedBackups()
				Logger.data.info("💾 Merged the store left in Application Support into the live store")
				return .merged
			}

			// A different radio: the old store becomes that radio's backup, restored when the
			// user switches to it.
			guard let legacyInfo = legacyMyInfos.first else {
				parkLegacyStore(at: legacyStoreURL)
				return .nothingToDo
			}
			let legacyName = try legacyContext.fetch(FetchDescriptor<UserEntity>())
				.first { $0.num == legacyInfo.myNodeNum }?.longName
			let nodeNum = legacyInfo.myNodeNum
			let deviceId = legacyInfo.deviceId
			Task { @MainActor in
				let result = await backups.createBackup(forNode: nodeNum, deviceId: deviceId, nodeName: legacyName, from: legacyStoreURL)
				if case .success = result {
					parkLegacyStore(at: legacyStoreURL)
					removeCopiedBackups()
					Logger.data.info("💾 Filed the store left in Application Support as the backup for node \(nodeNum.toHex(), privacy: .public)")
				} else {
					Logger.data.error("💾 Could not file the old store as a backup; it stays where it is and is tried again next launch")
				}
			}
			return .filedAsBackup(nodeNum: nodeNum)
		} catch {
			// Drop a partial merge so a later save of the main context doesn't write it.
			container.mainContext.rollback()
			Logger.data.error("💾 Recovering the store left in Application Support failed; it stays where it is: \(error.localizedDescription, privacy: .public)")
			return .failed
		}
	}

	/// Adds what the old store has and the live one doesn't, linked to the live nodes and users.
	@MainActor
	static func merge(from legacyContext: ModelContext, into liveContext: ModelContext) throws {
		let hadAutosave = liveContext.autosaveEnabled
		liveContext.autosaveEnabled = false
		defer { liveContext.autosaveEnabled = hadAutosave }

		let existing = try StoreMergeIndex(liveContext)
		let nodesByNum = try NodeBackupManager.importNodes(from: legacyContext, into: liveContext, existing: existing)
		let usersByNum = try NodeBackupManager.importUsers(from: legacyContext, into: liveContext, nodesByNum: nodesByNum, existing: existing)
		let myInfosByNodeNum = try NodeBackupManager.importMyInfo(from: legacyContext, into: liveContext, nodesByNum: nodesByNum, existing: existing)
		try NodeBackupManager.importChannels(from: legacyContext, into: liveContext, myInfosByNodeNum: myInfosByNodeNum, existing: existing)
		try NodeBackupManager.importMetadata(from: legacyContext, into: liveContext, nodesByNum: nodesByNum, existing: existing)
		try NodeBackupManager.importPositions(from: legacyContext, into: liveContext, nodesByNum: nodesByNum, existing: existing)
		try NodeBackupManager.importTelemetry(from: legacyContext, into: liveContext, nodesByNum: nodesByNum, existing: existing)
		try NodeBackupManager.importMessages(from: legacyContext, into: liveContext, usersByNum: usersByNum, existing: existing)
		try NodeBackupManager.importWaypoints(from: legacyContext, into: liveContext, existing: existing)
		try NodeBackupManager.importTraceRoutes(from: legacyContext, into: liveContext, nodesByNum: nodesByNum, existing: existing)
		try NodeBackupManager.importPaxCounters(from: legacyContext, into: liveContext, nodesByNum: nodesByNum, existing: existing)
		try liveContext.save()
	}

	/// Renamed rather than deleted: nothing opens it again, and the data stays on the device.
	nonisolated static func parkLegacyStore(at url: URL) {
		let fm = FileManager.default
		for suffix in ["", "-wal", "-shm"] {
			let from = URL(fileURLWithPath: url.path + suffix)
			guard fm.fileExists(atPath: from.path) else { continue }
			let to = URL(fileURLWithPath: url.path + recoveredSuffix + suffix)
			try? fm.removeItem(at: to)
			do {
				try fm.moveItem(at: from, to: to)
			} catch {
				Logger.data.error("💾 Could not rename \(from.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
	}
}

/// What the live store already holds, so a merge adds only what is missing. Nodes and users are
/// kept as they are and the imported rows link to them.
struct StoreMergeIndex {

	struct RowKey: Hashable {
		let num: Int64
		let kind: Int32
		let time: Date?
	}

	let nodesByNum: [Int64: NodeInfoEntity]
	let usersByNum: [Int64: UserEntity]
	let myInfoNodeNums: Set<Int64>
	let metadataNodeNums: Set<Int64>
	let positionKeys: Set<RowKey>
	let telemetryKeys: Set<RowKey>
	let messageIds: Set<Int64>
	let waypointIds: Set<Int64>
	let traceRouteIds: Set<Int64>
	let paxKeys: Set<RowKey>

	init(_ context: ModelContext) throws {
		nodesByNum = Dictionary(try context.fetch(FetchDescriptor<NodeInfoEntity>()).map { ($0.num, $0) }) { first, _ in first }
		usersByNum = Dictionary(try context.fetch(FetchDescriptor<UserEntity>()).map { ($0.num, $0) }) { first, _ in first }
		myInfoNodeNums = Set(try context.fetch(FetchDescriptor<MyInfoEntity>()).map(\.myNodeNum))
		metadataNodeNums = Set(try context.fetch(FetchDescriptor<DeviceMetadataEntity>()).compactMap { $0.metadataNode?.num })
		positionKeys = Set(try context.fetch(FetchDescriptor<PositionEntity>()).map {
			RowKey(num: $0.nodePosition?.num ?? 0, kind: 0, time: $0.time)
		})
		telemetryKeys = Set(try context.fetch(FetchDescriptor<TelemetryEntity>()).map {
			RowKey(num: $0.ownerNodeNum ?? 0, kind: $0.metricsType, time: $0.time)
		})
		messageIds = Set(try context.fetch(FetchDescriptor<MessageEntity>()).map(\.messageId))
		waypointIds = Set(try context.fetch(FetchDescriptor<WaypointEntity>()).map(\.id))
		traceRouteIds = Set(try context.fetch(FetchDescriptor<TraceRouteEntity>()).map(\.id))
		paxKeys = Set(try context.fetch(FetchDescriptor<PaxCounterEntity>()).map {
			RowKey(num: $0.paxNode?.num ?? 0, kind: 0, time: $0.time)
		})
	}
}
