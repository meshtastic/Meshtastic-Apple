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
/// Once, after launch and before any radio connects (see `StoreUpgrade`): the old store is merged
/// into the live one when they belong to the same radio (or the live one has no radio yet), and
/// otherwise filed as that radio's backup. Backups copied from it under other radios are removed.
/// The old file is then renamed so this does not run again; it is kept, not deleted. A failed
/// attempt is retried on the next launch, up to `maxAttempts` times.
enum LegacyStoreRecovery {

	enum Outcome: Equatable {
		case nothingToDo
		case merged
		case filedAsBackup(nodeNum: Int64)
		case failed
	}

	nonisolated static let attemptsKey = "legacyStoreRecoveryAttempts"
	nonisolated static let firstAttemptKey = "legacyStoreRecoveryFirstAttempt"
	nonisolated static let maxAttempts = 3
	nonisolated static let recoveredSuffix = ".recovered"

	/// Where the store was before the app group.
	nonisolated static var legacyStoreURL: URL {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Meshtastic.store")
	}

	/// Whether there is an old store left to recover.
	nonisolated static func isPending(
		liveStoreURL: URL,
		legacyStoreURL: URL = legacyStoreURL,
		defaults: UserDefaults = .standard
	) -> Bool {
		legacyStoreURL.standardizedFileURL != liveStoreURL.standardizedFileURL
			&& FileManager.default.fileExists(atPath: legacyStoreURL.path)
			&& defaults.integer(forKey: attemptsKey) < maxAttempts
	}

	/// The old store's radio, read off the main thread.
	private struct LegacyRadio: Sendable {
		let nodeNum: Int64
		let deviceId: Data?
		let name: String?
	}

	private struct Inspection: Sendable {
		let legacyNums: Set<Int64>
		let legacyDeviceKeys: Set<String>
		let merged: Bool
		let radio: LegacyRadio?
	}

	@MainActor
	@discardableResult
	static func recoverIfNeeded(
		into container: ModelContainer,
		liveStoreURL: URL,
		legacyStoreURL: URL = legacyStoreURL,
		backups: NodeBackupManager = .shared,
		defaults: UserDefaults = .standard
	) async -> Outcome {
		guard isPending(liveStoreURL: liveStoreURL, legacyStoreURL: legacyStoreURL, defaults: defaults) else {
			return .nothingToDo
		}
		// Counted before the work, so a crash part way through can't repeat on every launch.
		// Success renames the old file, which ends the retries on its own.
		defaults.set(defaults.integer(forKey: attemptsKey) + 1, forKey: attemptsKey)
		// Backups made from here on copy the live store, so they are never the old store's copies,
		// even if this attempt fails and a later one does the cleanup.
		if defaults.object(forKey: firstAttemptKey) == nil {
			defaults.set(Date(), forKey: firstAttemptKey)
		}
		let firstAttempt = defaults.object(forKey: firstAttemptKey) as? Date ?? Date()

		// When the old build last wrote the store. Backups made after it are copies of it.
		let fm = FileManager.default
		let frozenAt = ["", "-wal"].compactMap { suffix in
			(try? fm.attributesOfItem(atPath: legacyStoreURL.path + suffix))?[.modificationDate] as? Date
		}.max() ?? .distantPast

		let inspection: Inspection
		do {
			// Off the main thread: a merge of a large store takes a while.
			inspection = try await Task.detached(priority: .userInitiated) {
				try inspectAndMergeIfSameRadio(legacyStoreURL: legacyStoreURL, into: container)
			}.value
		} catch {
			Logger.data.error("💾 Recovering the store left in Application Support failed; it stays where it is: \(error.localizedDescription, privacy: .public)")
			return .failed
		}

		// Copies of the old store filed under other radios hold the wrong radio's data. Removed
		// only once the old store's data is safe, in the live store or in its own backup.
		func removeCopiedBackups() {
			let removed = backups.removeBackups(
				createdAfter: frozenAt.addingTimeInterval(60),
				before: firstAttempt,
				exceptNodes: inspection.legacyNums,
				exceptDevices: inspection.legacyDeviceKeys
			)
			if removed > 0 {
				Logger.backup.warning("💾 Removed \(removed) backups copied from the old store under other radios")
			}
		}

		if inspection.merged {
			parkLegacyStore(at: legacyStoreURL)
			removeCopiedBackups()
			Logger.data.info("💾 Merged the store left in Application Support into the live store")
			return .merged
		}

		// A different radio: the old store becomes that radio's backup, restored when the
		// user switches to it.
		guard let radio = inspection.radio else {
			parkLegacyStore(at: legacyStoreURL)
			return .nothingToDo
		}
		let result = await backups.createBackup(forNode: radio.nodeNum, deviceId: radio.deviceId, nodeName: radio.name, from: legacyStoreURL)
		guard case .success = result else {
			Logger.data.error("💾 Could not file the old store as a backup; it stays where it is and is tried again next launch")
			return .failed
		}
		parkLegacyStore(at: legacyStoreURL)
		removeCopiedBackups()
		Logger.data.info("💾 Filed the store left in Application Support as the backup for node \(radio.nodeNum.toHex(), privacy: .public)")
		return .filedAsBackup(nodeNum: radio.nodeNum)
	}

	/// Reads which radio the old store belongs to and, when the live store is for the same radio
	/// or none yet, merges it in. Uses its own contexts; nothing is saved unless the merge succeeds.
	private nonisolated static func inspectAndMergeIfSameRadio(legacyStoreURL: URL, into container: ModelContainer) throws -> Inspection {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let legacyContainer = try NodeBackupManager.stagedBackupContainer(for: legacyStoreURL, schema: schema)
		let legacyContext = ModelContext(legacyContainer)
		legacyContext.autosaveEnabled = false

		let legacyMyInfos = try legacyContext.fetch(FetchDescriptor<MyInfoEntity>())
		let legacyNums = Set(legacyMyInfos.map(\.myNodeNum))
		let legacyDeviceKeys = Set(legacyMyInfos.compactMap { BackupKey.forDevice($0.deviceId) })

		let liveContext = ModelContext(container)
		liveContext.autosaveEnabled = false
		let liveNums = Set(try liveContext.fetch(FetchDescriptor<MyInfoEntity>()).map(\.myNodeNum))

		if liveNums.isEmpty || !liveNums.isDisjoint(with: legacyNums) {
			try merge(from: legacyContext, into: liveContext)
			return Inspection(legacyNums: legacyNums, legacyDeviceKeys: legacyDeviceKeys, merged: true, radio: nil)
		}
		let radio = legacyMyInfos.first.map { info in
			LegacyRadio(
				nodeNum: info.myNodeNum,
				deviceId: info.deviceId,
				name: (try? legacyContext.fetch(FetchDescriptor<UserEntity>()))?.first { $0.num == info.myNodeNum }?.longName
			)
		}
		return Inspection(legacyNums: legacyNums, legacyDeviceKeys: legacyDeviceKeys, merged: false, radio: radio)
	}

	/// Adds what the old store has and the live one doesn't, linked to the live nodes and users.
	nonisolated static func merge(from legacyContext: ModelContext, into liveContext: ModelContext) throws {
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
