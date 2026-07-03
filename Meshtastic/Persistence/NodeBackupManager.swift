//
//  NodeBackupManager.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import CryptoKit
import OSLog
import SQLite3
import SwiftData

/// Core backup/restore service for node database snapshots.
///
/// `NodeBackupManager` is `@MainActor`-isolated for state consistency.
/// File I/O operations run on a background thread via `Task.detached` with `.userInitiated` priority.
@MainActor
final class NodeBackupManager: NodeBackupManaging {

	// MARK: - Singleton

	static let shared = NodeBackupManager()

	// MARK: - Constants

	private static let indexFileName = "backup-index.json"
	private static let storeFileName = "Meshtastic.store"
	private static let walFileName = "Meshtastic.store-wal"
	private static let shmFileName = "Meshtastic.store-shm"
	private static let maximumBackupCount = 50
	/// Minimum free disk space required for backup (50 MB)
	private static let minimumFreeDiskSpace: Int64 = 50 * 1024 * 1024

	// MARK: - Properties

	private var backupIndex: BackupIndex
	private let backupBaseURL: URL
	private let fileManager = FileManager.default

	// MARK: - Initialization

	private init() {
		let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		backupBaseURL = appSupport.appendingPathComponent("NodeBackups", isDirectory: true)

		// Ensure backup directory exists
		try? FileManager.default.createDirectory(at: backupBaseURL, withIntermediateDirectories: true)

		// Load or create index
		backupIndex = Self.loadIndex(from: backupBaseURL)

		// Validate index consistency on launch (T029)
		validateIndexConsistency()
	}

	/// Initializer for testing with a custom base URL.
	init(baseURL: URL) {
		backupBaseURL = baseURL
		try? FileManager.default.createDirectory(at: backupBaseURL, withIntermediateDirectories: true)
		backupIndex = Self.loadIndex(from: backupBaseURL)
		validateIndexConsistency()
	}

	// MARK: - Index Management

	private static func loadIndex(from baseURL: URL) -> BackupIndex {
		let indexURL = baseURL.appendingPathComponent(indexFileName)
		guard let data = try? Data(contentsOf: indexURL),
			  let index = try? JSONDecoder().decode(BackupIndex.self, from: data) else {
			return BackupIndex()
		}
		return index
	}

	private func saveIndex() {
		let indexURL = backupBaseURL.appendingPathComponent(Self.indexFileName)
		backupIndex.lastModified = .now
		guard let data = try? JSONEncoder().encode(backupIndex) else {
			Logger.backup.error("Failed to encode backup index")
			return
		}
		do {
			try data.write(to: indexURL, options: .atomic)
		} catch {
			Logger.backup.error("Failed to save backup index: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - T029: Index Consistency Validation

	/// Validates backup index consistency on launch. Removes entries for orphaned or missing files.
	private func validateIndexConsistency() {
		var modified = false
		for (nodeNum, entry) in backupIndex.entries {
			let nodeDir = backupBaseURL.appendingPathComponent(entry.backupPath, isDirectory: true)
			let sqliteFile = nodeDir.appendingPathComponent(Self.storeFileName)
			if !fileManager.fileExists(atPath: sqliteFile.path) {
				Logger.backup.warning("Orphaned index entry for node \(nodeNum) — backup file missing, removing entry")
				backupIndex.entries.removeValue(forKey: nodeNum)
				modified = true
			}
		}

		// Check for orphaned directories without index entries
		if let contents = try? fileManager.contentsOfDirectory(at: backupBaseURL, includingPropertiesForKeys: nil) {
			for item in contents {
				let name = item.lastPathComponent
				// Skip index file
				if name == Self.indexFileName { continue }
				// If it's a directory with a numeric name but no index entry, clean it up
				if let nodeNum = Int64(name), backupIndex.entries[nodeNum] == nil {
					Logger.backup.warning("Orphaned backup directory for node \(nodeNum) — removing")
					try? fileManager.removeItem(at: item)
					modified = true
				}
			}
		}

		if modified {
			saveIndex()
		}
	}

	// MARK: - T006: SHA-256 Checksum

	/// Computes SHA-256 checksum of the file at the given URL.
	private func computeChecksum(for fileURL: URL) async throws -> String {
		try await Task.detached(priority: .userInitiated) {
			let data = try Data(contentsOf: fileURL)
			let digest = SHA256.hash(data: data)
			return digest.map { String(format: "%02x", $0) }.joined()
		}.value
	}

	// MARK: - T026: Disk Space Check

	/// Checks if sufficient disk space is available for a backup.
	private func hasSufficientDiskSpace() -> Bool {
		do {
			let values = try backupBaseURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
			if let available = values.volumeAvailableCapacityForImportantUsage {
				return available > Self.minimumFreeDiskSpace
			}
		} catch {
			Logger.backup.warning("Could not determine available disk space: \(error.localizedDescription, privacy: .public)")
		}
		// If we can't determine space, proceed with backup attempt
		return true
	}

	// MARK: - T007: Create Backup

	func createBackup(forNode nodeNum: Int64, nodeName: String?) async -> NodeBackupResult {
		Logger.backup.info("Creating backup for node \(nodeNum)")

		// T026: Check disk space
		guard hasSufficientDiskSpace() else {
			Logger.backup.warning("Insufficient disk space for backup of node \(nodeNum)")
			return .skipped(reason: "Not enough storage for backup")
		}

		// Retry-once logic (FR-004)
		for attempt in 1...2 {
			do {
				let entry = try await performBackup(forNode: nodeNum, nodeName: nodeName)
				Logger.backup.info("Backup created for node \(nodeNum): \(entry.fileSize) bytes, checksum: \(entry.checksum, privacy: .public)")
				return .success(entry)
			} catch {
				if attempt == 1 {
					Logger.backup.warning("Backup attempt 1 failed for node \(nodeNum), retrying: \(error.localizedDescription, privacy: .public)")
				} else {
					Logger.backup.error("Backup failed after retry for node \(nodeNum): \(error.localizedDescription, privacy: .public)")
					return .skipped(reason: "Backup failed: \(error.localizedDescription)")
				}
			}
		}

		return .skipped(reason: "Backup failed unexpectedly")
	}

	private func performBackup(forNode nodeNum: Int64, nodeName: String?) async throws -> BackupEntry {
		let nodeDirName = "\(nodeNum)"
		let nodeBackupDir = backupBaseURL.appendingPathComponent(nodeDirName, isDirectory: true)

		// Create or clean destination directory
		if fileManager.fileExists(atPath: nodeBackupDir.path) {
			try fileManager.removeItem(at: nodeBackupDir)
		}
		try fileManager.createDirectory(at: nodeBackupDir, withIntermediateDirectories: true)

		// Get source database path
		let sourceURL = self.activeDatabaseURL()

		// Copy files on background thread
		let fileSize = try await Task.detached(priority: .userInitiated) { [fileManager] in
			var totalSize: Int64 = 0

			// Copy .store
			let sqliteSrc = sourceURL
			let sqliteDst = nodeBackupDir.appendingPathComponent(Self.storeFileName)
			if fileManager.fileExists(atPath: sqliteSrc.path) {
				try fileManager.copyItem(at: sqliteSrc, to: sqliteDst)
				let attrs = try fileManager.attributesOfItem(atPath: sqliteDst.path)
				totalSize += (attrs[.size] as? Int64) ?? 0
			}

			// Copy .sqlite-wal if present
			let walSrc = sourceURL.deletingLastPathComponent().appendingPathComponent(Self.walFileName)
			let walDst = nodeBackupDir.appendingPathComponent(Self.walFileName)
			if fileManager.fileExists(atPath: walSrc.path) {
				try fileManager.copyItem(at: walSrc, to: walDst)
				let attrs = try fileManager.attributesOfItem(atPath: walDst.path)
				totalSize += (attrs[.size] as? Int64) ?? 0
			}

			// Copy .sqlite-shm if present
			let shmSrc = sourceURL.deletingLastPathComponent().appendingPathComponent(Self.shmFileName)
			let shmDst = nodeBackupDir.appendingPathComponent(Self.shmFileName)
			if fileManager.fileExists(atPath: shmSrc.path) {
				try fileManager.copyItem(at: shmSrc, to: shmDst)
				let attrs = try fileManager.attributesOfItem(atPath: shmDst.path)
				totalSize += (attrs[.size] as? Int64) ?? 0
			}

			return totalSize
		}.value

		// Compute checksum
		let sqliteDst = nodeBackupDir.appendingPathComponent(Self.storeFileName)
		let checksum = try await computeChecksum(for: sqliteDst)

		// Update index
		let entry = BackupEntry(
			nodeNum: nodeNum,
			nodeName: nodeName,
			createdAt: .now,
			fileSize: fileSize,
			checksum: checksum,
			backupPath: nodeDirName
		)
		backupIndex.entries[nodeNum] = entry
		enforceBackupLimit(keeping: nodeNum)
		saveIndex()
		scheduleBackupCompaction(for: entry)

		return entry
	}

	private func scheduleBackupCompaction(for entry: BackupEntry) {
		Task.detached(priority: .utility) { [backupBaseURL] in
			do {
				let compactedEntry = try Self.compactBackupSnapshot(entry, backupBaseURL: backupBaseURL)
				await MainActor.run {
					guard self.backupIndex.entries[entry.nodeNum]?.createdAt == entry.createdAt else {
						return
					}
					self.backupIndex.entries[entry.nodeNum] = compactedEntry
					self.saveIndex()
					Logger.backup.info("Compacted backup for node \(entry.nodeNum) to \(compactedEntry.fileSize) bytes")
				}
			} catch {
				Logger.backup.warning("Failed to compact backup for node \(entry.nodeNum): \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	nonisolated private static func compactBackupSnapshot(_ entry: BackupEntry, backupBaseURL: URL) throws -> BackupEntry {
		let fileManager = FileManager.default
		let backupDir = backupBaseURL.appendingPathComponent(entry.backupPath, isDirectory: true)
		let storeURL = backupDir.appendingPathComponent(storeFileName)
		let walURL = backupDir.appendingPathComponent(walFileName)
		let shmURL = backupDir.appendingPathComponent(shmFileName)

		guard fileManager.fileExists(atPath: storeURL.path) else {
			throw BackupError.fileNotFound
		}

		if fileManager.fileExists(atPath: walURL.path) || fileManager.fileExists(atPath: shmURL.path) {
			try runSQLiteCompaction(at: storeURL)
			try removeBackupSidecarIfPresent(at: walURL, fileManager: fileManager)
			try removeBackupSidecarIfPresent(at: shmURL, fileManager: fileManager)
		}

		let attrs = try fileManager.attributesOfItem(atPath: storeURL.path)
		let compactedSize = (attrs[.size] as? Int64) ?? entry.fileSize
		let compactedChecksum = try computeChecksumSync(for: storeURL)

		var compactedEntry = entry
		compactedEntry.fileSize = compactedSize
		compactedEntry.checksum = compactedChecksum
		return compactedEntry
	}

	nonisolated private static func removeBackupSidecarIfPresent(at fileURL: URL, fileManager: FileManager) throws {
		guard fileManager.fileExists(atPath: fileURL.path) else {
			return
		}

		try fileManager.removeItem(at: fileURL)
	}

	nonisolated private static func runSQLiteCompaction(at storeURL: URL) throws {
		var database: OpaquePointer?
		let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
		guard sqlite3_open_v2(storeURL.path, &database, openFlags, nil) == SQLITE_OK, let database else {
			let message = database.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } } ?? "Unable to open backup database"
			sqlite3_close(database)
			throw AccessoryError.appError(message)
		}
		defer {
			sqlite3_close(database)
		}

		try executeSQLite("PRAGMA wal_checkpoint(TRUNCATE);", database: database)
		try executeSQLite("PRAGMA journal_mode=DELETE;", database: database)
		try executeSQLite("VACUUM;", database: database)
	}

	nonisolated private static func executeSQLite(_ sql: String, database: OpaquePointer) throws {
		var errorMessage: UnsafeMutablePointer<CChar>?
		guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
			let message = errorMessage.map { String(cString: $0) } ?? "SQLite command failed"
			sqlite3_free(errorMessage)
			throw AccessoryError.appError(message)
		}
	}

	nonisolated private static func computeChecksumSync(for fileURL: URL) throws -> String {
		let data = try Data(contentsOf: fileURL)
		let digest = SHA256.hash(data: data)
		return digest.map { String(format: "%02x", $0) }.joined()
	}

	private func enforceBackupLimit(keeping nodeNum: Int64) {
		guard backupIndex.entries.count > Self.maximumBackupCount else { return }

		let overflowEntries = backupIndex.entries.values
			.filter { $0.nodeNum != nodeNum }
			.sorted { $0.createdAt < $1.createdAt }
			.prefix(max(0, backupIndex.entries.count - Self.maximumBackupCount))

		for entry in overflowEntries {
			let nodeBackupDir = backupBaseURL.appendingPathComponent(entry.backupPath, isDirectory: true)
			try? fileManager.removeItem(at: nodeBackupDir)
			backupIndex.entries.removeValue(forKey: entry.nodeNum)
			Logger.backup.info("Pruned oldest backup for node \(entry.nodeNum) to enforce limit of \(Self.maximumBackupCount)")
		}
	}

	// MARK: - T009: Query Methods

	func hasBackup(forNode nodeNum: Int64) -> Bool {
		backupIndex.entries[nodeNum] != nil
	}

	func listBackups() -> [BackupEntry] {
		Array(backupIndex.entries.values).sorted { $0.createdAt > $1.createdAt }
	}

	/// Resolves a node number for a device peripheral identifier by inspecting existing backups.
	/// This is used during radio switching when the selected `Device` has not populated `num` yet.
	func resolveNodeNum(forPeripheralId peripheralId: String) async -> Int64? {
		let entries = listBackups()
		guard !entries.isEmpty else { return nil }

		do {
			return try await Task.detached(priority: .userInitiated) {
				let fileManager = FileManager.default
				let schema = Schema(versionedSchema: MeshtasticSchema.current)

				for entry in entries {
					let nodeBackupDir = self.backupBaseURL.appendingPathComponent(entry.backupPath, isDirectory: true)
					let backupStoreURL = nodeBackupDir.appendingPathComponent(Self.storeFileName)
					guard fileManager.fileExists(atPath: backupStoreURL.path) else { continue }

					let backupConfig = ModelConfiguration(url: backupStoreURL, allowsSave: false)
					let backupContainer = try ModelContainer(for: schema, configurations: backupConfig)
					let backupContext = ModelContext(backupContainer)
					backupContext.autosaveEnabled = false

					let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.peripheralId == peripheralId })
					if let myInfo = try backupContext.fetch(descriptor).first {
						return myInfo.myNodeNum
					}
				}

				return nil
			}.value
		} catch {
			Logger.backup.error("💾 Failed to resolve node for peripheral \(peripheralId, privacy: .public): \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	@discardableResult
	func deleteBackup(forNode nodeNum: Int64) -> Bool {
		guard let entry = backupIndex.entries[nodeNum] else {
			return false
		}

		let nodeBackupDir = backupBaseURL.appendingPathComponent(entry.backupPath, isDirectory: true)
		try? fileManager.removeItem(at: nodeBackupDir)
		backupIndex.entries.removeValue(forKey: nodeNum)
		saveIndex()

		Logger.backup.info("Deleted backup for node \(nodeNum)")
		return true
	}

	var totalBackupSize: Int64 {
		backupIndex.entries.values.reduce(0) { $0 + $1.fileSize }
	}

	// MARK: - Helpers

	/// Returns the URL to the active SQLite database file.
	private func activeDatabaseURL() -> URL {
		let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		return appSupport.appendingPathComponent("Meshtastic.store")
	}

	// MARK: - Full Database Restore via Import

	/// Restores a full backup by importing all entities from the backup SQLite into the live container.
	///
	/// Call this AFTER `clearDatabase()` has emptied the live database. Opens the backup as a
	/// read-only ModelContainer and copies all entities (nodes, users, messages, positions,
	/// telemetry, waypoints, channels, etc.) into the live context with relationships intact.
	///
	/// This avoids SQLite file swaps and container recreation entirely — the live container
	/// stays open and valid throughout.
	///
	/// - Parameters:
	///   - nodeNum: The node number whose backup to restore
	///   - container: The live ModelContainer to import into
	/// - Returns: Result indicating success, skip, or no backup found
	func restoreFromBackup(forNode nodeNum: Int64, into container: ModelContainer) async -> NodeBackupResult {
		Logger.backup.info("💾 Restoring full backup for node \(nodeNum)")

		guard let entry = backupIndex.entries[nodeNum] else {
			Logger.backup.debug("💾 No backup found for node \(nodeNum)")
			return .noBackupFound
		}

		let nodeBackupDir = backupBaseURL.appendingPathComponent(entry.backupPath, isDirectory: true)
		let backupStoreURL = nodeBackupDir.appendingPathComponent(Self.storeFileName)

		guard fileManager.fileExists(atPath: backupStoreURL.path) else {
			Logger.backup.error("💾 Backup store file missing for node \(nodeNum)")
			return .skipped(reason: "Backup file not found")
		}

		do {
			try await validateBackupIntegrity(entry: entry, backupStoreURL: backupStoreURL)
		} catch {
			Logger.backup.error("💾 Backup integrity check failed for node \(nodeNum): \(error.localizedDescription, privacy: .public)")
			return .skipped(reason: "Restore failed: \(error.localizedDescription)")
		}

		do {
			try await Task.detached(priority: .userInitiated) {
				let schema = Schema(versionedSchema: MeshtasticSchema.current)
				let backupConfig = ModelConfiguration(url: backupStoreURL, allowsSave: false)
				let backupContainer = try ModelContainer(for: schema, configurations: backupConfig)
				let backupContext = ModelContext(backupContainer)
				backupContext.autosaveEnabled = false

				let liveContext = ModelContext(container)
				liveContext.autosaveEnabled = false

				// Import in dependency order
				let nodesByNum = try Self.importNodes(from: backupContext, into: liveContext)
				let usersByNum = try Self.importUsers(from: backupContext, into: liveContext, nodesByNum: nodesByNum)
				let myInfosByNodeNum = try Self.importMyInfo(from: backupContext, into: liveContext, nodesByNum: nodesByNum)
				try Self.importChannels(from: backupContext, into: liveContext, myInfosByNodeNum: myInfosByNodeNum)
				try Self.importMetadata(from: backupContext, into: liveContext, nodesByNum: nodesByNum)
				try Self.importPositions(from: backupContext, into: liveContext, nodesByNum: nodesByNum)
				try Self.importTelemetry(from: backupContext, into: liveContext, nodesByNum: nodesByNum)
				try Self.importMessages(from: backupContext, into: liveContext, usersByNum: usersByNum)
				try Self.importWaypoints(from: backupContext, into: liveContext)
				try Self.importTraceRoutes(from: backupContext, into: liveContext, nodesByNum: nodesByNum)
				try Self.importPaxCounters(from: backupContext, into: liveContext, nodesByNum: nodesByNum)

				try liveContext.save()
				Logger.backup.info("💾 Full restore complete for node \(nodeNum)")
			}.value

			return .success(entry)
		} catch {
			Logger.backup.error("💾 Full restore failed for node \(nodeNum): \(error.localizedDescription, privacy: .public)")
			return .skipped(reason: "Restore failed: \(error.localizedDescription)")
		}
	}

	private func validateBackupIntegrity(entry: BackupEntry, backupStoreURL: URL) async throws {
		let currentChecksum = try await computeChecksum(for: backupStoreURL)
		guard currentChecksum == entry.checksum else {
			Logger.backup.error("Checksum mismatch for node \(entry.nodeNum) — backup is corrupt, deleting")
			deleteBackup(forNode: entry.nodeNum)
			throw BackupError.checksumMismatch
		}
	}
}

// MARK: - Errors

enum BackupError: Error, LocalizedError {
	case checksumMismatch
	case fileNotFound
	case insufficientStorage

	var errorDescription: String? {
		switch self {
		case .checksumMismatch:
			return "Backup file integrity check failed"
		case .fileNotFound:
			return "Backup file not found"
		case .insufficientStorage:
			return "Insufficient storage for backup"
		}
	}
}
