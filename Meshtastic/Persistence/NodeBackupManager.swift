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
	private static let maximumBackupCount = 100
	/// Minimum free disk space required for backup (50 MB)
	private static let minimumFreeDiskSpace: Int64 = 50 * 1024 * 1024

	// MARK: - Properties

	private var backupIndex: BackupIndex
	private let backupBaseURL: URL
	private let fileManager = FileManager.default

	// MARK: - Initialization

	private init() {
		backupBaseURL = Self.resolveBackupBaseURL()

		// Ensure backup directory exists
		try? FileManager.default.createDirectory(at: backupBaseURL, withIntermediateDirectories: true)

		// Load or create index
		backupIndex = Self.loadIndex(from: backupBaseURL)

		// Validate index consistency on launch (T029)
		validateIndexConsistency()
	}

	/// Backups live in Documents — the user-visible "Meshtastic" folder in the Files app —
	/// alongside OfflineMaps, downloaded firmware, and imported GeoJSON, so users can copy a
	/// backup off the phone (or drop one in) without any in-app export flow. Earlier releases
	/// kept them in Application Support; the first launch after updating moves that folder here
	/// wholesale (the backup index stores paths relative to the folder, so the move preserves
	/// every entry). If the move fails (e.g. a partial earlier attempt left both folders), the
	/// legacy location keeps working so existing backups are never orphaned.
	private nonisolated static func resolveBackupBaseURL() -> URL {
		let fm = FileManager.default
		return resolveBackupBaseURL(
			documents: fm.urls(for: .documentDirectory, in: .userDomainMask).first!,
			appSupport: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		)
	}

	/// Testable core of the location resolution/migration — see `resolveBackupBaseURL()`.
	nonisolated static func resolveBackupBaseURL(documents: URL, appSupport: URL) -> URL {
		let fm = FileManager.default
		let newURL = documents.appendingPathComponent("NodeBackups", isDirectory: true)
		let legacyURL = appSupport.appendingPathComponent("NodeBackups", isDirectory: true)

		// Documents is user-writable through the Files app, so "something exists at the path"
		// is not "our folder exists": a stray *file* named NodeBackups would make a bare
		// fileExists check return true, the initializer's directory creation silently fail,
		// and every subsequent backup write fail. Distinguish directories from files and
		// never overwrite anything the user put there.
		var newIsDir: ObjCBool = false
		let newExists = fm.fileExists(atPath: newURL.path, isDirectory: &newIsDir)
		var legacyIsDir: ObjCBool = false
		let legacyExists = fm.fileExists(atPath: legacyURL.path, isDirectory: &legacyIsDir) && legacyIsDir.boolValue

		if newExists && !newIsDir.boolValue {
			// A user-created file is squatting on the folder name. Leave it untouched and keep
			// backups working in the app-controlled legacy location until the user removes it.
			Logger.data.error("💾 [Backup] A file named NodeBackups is blocking the Files-visible backup folder in Documents; keeping backups in Application Support until it is removed")
			return legacyURL
		}

		if legacyExists && !newExists {
			do {
				try fm.moveItem(at: legacyURL, to: newURL)
				Logger.data.info("💾 [Backup] Migrated node backups from Application Support to the Files-visible Documents folder")
			} catch {
				Logger.data.error("💾 [Backup] Failed to migrate node backups to Documents, continuing with the legacy location: \(error.localizedDescription, privacy: .public)")
				return legacyURL
			}
		} else if legacyExists && newExists {
			// Both exist (an interrupted earlier migration). Prefer the new location, but keep
			// the legacy folder on disk untouched for manual recovery rather than merging blindly.
			Logger.data.warning("💾 [Backup] Both legacy and Documents backup folders exist; using Documents. Legacy folder left in place at Application Support/NodeBackups")
		}
		return newURL
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
		for (key, entry) in backupIndex.entries {
			guard let nodeDir = backupDirectory(for: entry) else { continue }
			let sqliteFile = nodeDir.appendingPathComponent(Self.storeFileName)
			if !fileManager.fileExists(atPath: sqliteFile.path) {
				Logger.backup.warning("Orphaned index entry for \(key, privacy: .public) — backup file missing, removing entry")
				backupIndex.entries.removeValue(forKey: key)
				modified = true
			}
		}

		// Check for orphaned directories without index entries. Match on the paths the index actually
		// references rather than on the directory name: names are node numbers on older installs and
		// device ids once a radio has been reconnected, and parsing them would delete every re-keyed
		// directory the first time this ran.
		let referencedPaths = Set(backupIndex.entries.values.map(\.backupPath))
		if let contents = try? fileManager.contentsOfDirectory(at: backupBaseURL, includingPropertiesForKeys: nil) {
			for item in contents {
				let name = item.lastPathComponent
				// Skip index file
				if name == Self.indexFileName { continue }
				if !referencedPaths.contains(name), Self.isBackupDirectoryName(name) {
					Logger.backup.warning("Orphaned backup directory \(name, privacy: .public) — removing")
					try? fileManager.removeItem(at: item)
					modified = true
				}
			}
		}

		if modified {
			saveIndex()
		}
	}

	/// Whether a directory in the backup folder is one of ours, so the orphan sweep leaves anything
	/// else alone. Covers the bare node numbers written before this change, the `node-` form, and a
	/// device id.
	private static func isBackupDirectoryName(_ name: String) -> Bool {
		if Int64(name) != nil { return true }
		if BackupKey.isNodeNumberKey(name) { return true }
		return name.count == 32 && name.allSatisfy { $0.isHexDigit && !$0.isUppercase }
	}

	// MARK: - T006: SHA-256 Checksum

	/// The directory an entry lives in, or nil when its recorded path is not a plain folder name.
	///
	/// `backup-index.json` sits in Documents and is visible in Files, so a hand-edited `backupPath`
	/// could carry `..` components or an absolute path, and every delete, move and read here would
	/// follow it out of the backup folder. Paths we write are always a single component.
	private func backupDirectory(for entry: BackupEntry) -> URL? {
		guard Self.isPlainBackupPath(entry.backupPath) else {
			Logger.backup.error("Refusing to use backup path \(entry.backupPath, privacy: .public) — not a plain folder name")
			return nil
		}
		return backupBaseURL.appendingPathComponent(entry.backupPath, isDirectory: true)
	}

	nonisolated static func isPlainBackupPath(_ path: String) -> Bool {
		!path.isEmpty
		&& path != "."
		&& path != ".."
		&& !path.contains("/")
		&& !path.contains("\\")
	}

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

	/// - Parameter deviceId: The radio's `MyNodeInfo.device_id`, which keys the backup. Node numbers
	///   change when a radio upgrades to 2.8, so a backup keyed on one is orphaned by the upgrade.
	///   Pass nil for a radio that reports none and the backup keeps the old node-number key.
	func createBackup(forNode nodeNum: Int64, deviceId: Data?, nodeName: String?) async -> NodeBackupResult {
		Logger.backup.info("Creating backup for node \(nodeNum)")

		// T026: Check disk space
		guard hasSufficientDiskSpace() else {
			Logger.backup.warning("Insufficient disk space for backup of node \(nodeNum)")
			return .skipped(reason: "Not enough storage for backup")
		}

		// Retry-once logic (FR-004)
		for attempt in 1...2 {
			do {
				let entry = try await performBackup(forNode: nodeNum, deviceId: deviceId, nodeName: nodeName)
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

	private func performBackup(forNode nodeNum: Int64, deviceId: Data?, nodeName: String?) async throws -> BackupEntry {
		// Fall back to the device id already recorded for this node. Callers resolve it from the
		// store, which can come back nil part way through a connect or a radio switch, and minting a
		// node-number key then would sit a second backup beside the device-keyed one for the same
		// radio — which is exactly what happened on my phone before this.
		let deviceKey = BackupKey.forDevice(deviceId)
			?? backupIndex.entries.values.first { $0.nodeNum == nodeNum }?.deviceId
		let nodeDirName = deviceKey ?? BackupKey.forNode(nodeNum)
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
			deviceId: deviceKey,
			nodeName: nodeName,
			createdAt: .now,
			fileSize: fileSize,
			checksum: checksum,
			backupPath: nodeDirName
		)
		backupIndex.entries[nodeDirName] = entry

		// A radio backed up under its node number before we knew its device id leaves an entry behind
		// once it is keyed by device. Drop it here so the same radio is not listed twice; anything
		// filed under an *earlier* node number is cleaned up by adoptLegacyBackups on connect.
		if deviceKey != nil {
			removeBackup(forKey: BackupKey.forNode(nodeNum), reason: "superseded by the device id backup")
		}

		enforceBackupLimit(keeping: nodeDirName)
		saveIndex()
		scheduleBackupCompaction(for: entry)

		return entry
	}

	private func scheduleBackupCompaction(for entry: BackupEntry) {
		Task.detached(priority: .utility) { [backupBaseURL] in
			do {
				let compactedEntry = try Self.compactBackupSnapshot(entry, backupBaseURL: backupBaseURL)
				await MainActor.run {
					guard self.backupIndex.entries[entry.key]?.createdAt == entry.createdAt else {
						return
					}
					self.backupIndex.entries[entry.key] = compactedEntry
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

	private func enforceBackupLimit(keeping key: String) {
		guard backupIndex.entries.count > Self.maximumBackupCount else { return }

		let overflow = backupIndex.entries
			.filter { $0.key != key }
			.sorted { $0.value.createdAt < $1.value.createdAt }
			.prefix(max(0, backupIndex.entries.count - Self.maximumBackupCount))

		for (overflowKey, entry) in overflow {
			if let nodeBackupDir = backupDirectory(for: entry) {
				try? fileManager.removeItem(at: nodeBackupDir)
			}
			backupIndex.entries.removeValue(forKey: overflowKey)
			Logger.backup.info("Pruned oldest backup for node \(entry.nodeNum) to enforce limit of \(Self.maximumBackupCount)")
		}
	}

	/// Deletes a backup's directory and its index entry. Returns whether there was one to remove.
	@discardableResult
	private func removeBackup(forKey key: String, reason: String) -> Bool {
		guard let entry = backupIndex.entries[key] else { return false }
		if let dir = backupDirectory(for: entry) {
			try? fileManager.removeItem(at: dir)
		}
		backupIndex.entries.removeValue(forKey: key)
		Logger.backup.info("Removed backup for node \(entry.nodeNum) (\(entry.fileSize) bytes): \(reason, privacy: .public)")
		return true
	}

	// MARK: - T009: Query Methods

	func hasBackup(forNode nodeNum: Int64) -> Bool {
		// The caller knows a node number, which may be keyed either way depending on whether we have
		// connected to that radio since it started reporting a device id.
		backupIndex.entries.values.contains { $0.nodeNum == nodeNum }
	}

	func listBackups() -> [BackupEntry] {
		Array(backupIndex.entries.values).sorted { $0.createdAt > $1.createdAt }
	}

	/// Whether a backup belongs to the given peripheral, read from the backup itself.
	///
	/// Staged copy: a pending schema migration cannot run on a read-only store, and the backup itself
	/// must never be mutated. See `stagedBackupContainer` (staging dirs are swept at launch, never
	/// removed while live).
	nonisolated private static func backupBelongs(
		to peripheralId: String,
		storeURL: URL,
		schema: Schema
	) throws -> Int64? {
		let backupContainer = try stagedBackupContainer(for: storeURL, schema: schema)
		let backupContext = ModelContext(backupContainer)
		backupContext.autosaveEnabled = false

		let descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.peripheralId == peripheralId })
		return try backupContext.fetch(descriptor).first?.myNodeNum
	}

	/// Index keys whose backup was taken from the given peripheral. Only searches entries still keyed
	/// by node number, since anything already keyed by device id has been identified.
	private func legacyKeys(forPeripheralId peripheralId: String) async -> [String] {
		let candidates = backupIndex.entries
			.filter { BackupKey.isNodeNumberKey($0.key) }
			.map { ($0.key, $0.value.backupPath) }
		guard !candidates.isEmpty else { return [] }

		let baseURL = backupBaseURL
		return await Task.detached(priority: .userInitiated) {
			let fileManager = FileManager.default
			let schema = Schema(versionedSchema: MeshtasticSchema.current)
			var matches: [String] = []

			for (key, backupPath) in candidates {
				let storeURL = baseURL
					.appendingPathComponent(backupPath, isDirectory: true)
					.appendingPathComponent(Self.storeFileName)
				guard fileManager.fileExists(atPath: storeURL.path) else { continue }
				do {
					if try Self.backupBelongs(to: peripheralId, storeURL: storeURL, schema: schema) != nil {
						matches.append(key)
					}
				} catch {
					Logger.backup.warning("Could not read backup \(key, privacy: .public) while matching a peripheral: \(error.localizedDescription, privacy: .public)")
				}
			}
			return matches
		}.value
	}

	/// Resolves a node number for a device peripheral identifier by inspecting existing backups.
	/// This is used during radio switching when the selected `Device` has not populated `num` yet.
	func resolveNodeNum(forPeripheralId peripheralId: String) async -> Int64? {
		let entries = listBackups()
		guard !entries.isEmpty else { return nil }

		let baseURL = backupBaseURL
		return await Task.detached(priority: .userInitiated) {
			let fileManager = FileManager.default
			let schema = Schema(versionedSchema: MeshtasticSchema.current)

			for entry in entries {
				let storeURL = baseURL
					.appendingPathComponent(entry.backupPath, isDirectory: true)
					.appendingPathComponent(Self.storeFileName)
				guard fileManager.fileExists(atPath: storeURL.path) else { continue }
				do {
					if let nodeNum = try Self.backupBelongs(to: peripheralId, storeURL: storeURL, schema: schema) {
						return nodeNum
					}
				} catch {
					Logger.backup.error("💾 Failed to read backup while resolving peripheral \(peripheralId, privacy: .public): \(error.localizedDescription, privacy: .public)")
				}
			}
			return nil
		}.value
	}

	// MARK: - Re-keying backups to the device id

	/// Moves this radio's backup from a node-number key onto its device id.
	///
	/// Called on connect, when the device id, node number and peripheral id are all known. Node
	/// numbers change on the 2.8 upgrade, so a backup keyed on one is orphaned by the upgrade and a
	/// fresh one starts alongside it. Re-keying happens a radio at a time rather than as one pass over
	/// every backup, so nothing expensive or destructive runs at launch and radios that are never
	/// reconnected keep working exactly as they do now.
	///
	/// Matching on the current node number is free but only finds a backup taken since the last
	/// renumber. Backups filed under *earlier* node numbers are found by peripheral id, which means
	/// reading them, so that only runs when the cheap match fails.
	func adoptLegacyBackups(deviceId: Data?, nodeNum: Int64, peripheralId: String?) async {
		guard let deviceKey = BackupKey.forDevice(deviceId) else { return }
		// Already re-keyed — the common path on every connect after the first. Still worth looking for
		// a node-number entry for the same radio: a backup taken while the device id lookup was
		// coming back nil left one sitting beside the device-keyed backup. Clearing it here means a
		// connect is enough to tidy up, rather than waiting for whatever takes the next backup.
		if backupIndex.entries[deviceKey] != nil {
			if removeBackup(forKey: BackupKey.forNode(nodeNum), reason: "duplicate of \(deviceKey)") {
				saveIndex()
			}
			return
		}

		var candidateKeys: [String] = []
		let nodeKey = BackupKey.forNode(nodeNum)
		if backupIndex.entries[nodeKey] != nil {
			candidateKeys.append(nodeKey)
		}
		if let peripheralId {
			for key in await legacyKeys(forPeripheralId: peripheralId) where !candidateKeys.contains(key) {
				candidateKeys.append(key)
			}
		}

		let candidates = candidateKeys.compactMap { key in backupIndex.entries[key].map { (key, $0) } }
		guard let (survivingKey, surviving) = candidates.max(by: { $0.1.createdAt < $1.1.createdAt }) else {
			return
		}

		guard let oldDir = backupDirectory(for: surviving) else { return }
		let newDir = backupBaseURL.appendingPathComponent(deviceKey, isDirectory: true)
		if fileManager.fileExists(atPath: newDir.path) {
			try? fileManager.removeItem(at: newDir)
		}

		// The survivor moves first. Deleting the duplicates before this meant a transient move
		// failure destroyed them and re-keyed nothing, turning a retryable hiccup into permanent
		// backup loss. Nothing is deleted until the one we are keeping is safely in place.
		do {
			try fileManager.moveItem(at: oldDir, to: newDir)
		} catch {
			Logger.backup.error("Could not move backup \(survivingKey, privacy: .public) to its device id, leaving it and its duplicates alone: \(error.localizedDescription, privacy: .public)")
			return
		}

		var adopted = surviving
		adopted.deviceId = deviceKey
		adopted.backupPath = deviceKey
		backupIndex.entries.removeValue(forKey: survivingKey)
		backupIndex.entries[deviceKey] = adopted

		for (key, _) in candidates where key != survivingKey {
			removeBackup(forKey: key, reason: "duplicate of \(deviceKey) from an earlier node number")
		}
		saveIndex()

		Logger.backup.info("Re-keyed the backup for node \(surviving.nodeNum) onto its device id, dropping \(candidates.count - 1) duplicate(s)")
	}

	@discardableResult
	func deleteBackup(forKey key: String) -> Bool {
		guard removeBackup(forKey: key, reason: "deleted by the user") else { return false }
		saveIndex()
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

		// Looked up by node number rather than by key: a backup for this radio may still be keyed by
		// node number, or already re-keyed onto its device id.
		guard let entry = backupIndex.entries.values.first(where: { $0.nodeNum == nodeNum }) else {
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
			// The import runs on the MainActor through the LIVE container's mainContext. Two
			// invariants, both learned from live lldb catches of the switch-crash cluster:
			// 1. `container` must be the same object the UI has always been bound to — a save
			//    into a replaced container is processed by the previous container's immortal
			//    observer bridge (they unregister on dealloc, never on unmount) and traps.
			// 2. The backup opens through a staged temp copy — a pending schema migration
			//    cannot run on a read-only store, and that failure used to abort the restore
			//    and bounce the switch back to the previous device.
			try await MainActor.run {
				let schema = Schema(versionedSchema: MeshtasticSchema.current)
				let backupContainer = try Self.stagedBackupContainer(for: backupStoreURL, schema: schema)
				let backupContext = ModelContext(backupContainer)
				backupContext.autosaveEnabled = false

				let liveContext = container.mainContext
				let hadAutosave = liveContext.autosaveEnabled
				liveContext.autosaveEnabled = false
				defer { liveContext.autosaveEnabled = hadAutosave }

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
			}

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
			deleteBackup(forKey: entry.key)
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

// MARK: - Staged backup opening

extension NodeBackupManager {

	/// Opens a backup store for reading through a disposable staged copy.
	///
	/// Backups must never be mutated — but SwiftData cannot open a store read-only when a
	/// schema migration is pending ("Cannot migrate store in-place: … attempt to write a
	/// readonly database"), which is exactly what aborted node-switch restores after a schema
	/// advance and bounced the switch back to the previous device. Copying the store (plus
	/// WAL/SHM sidecars) into a temp directory and opening the copy writable lets the
	/// migration run against the disposable copy while the real backup stays byte-identical.
	///
	/// The staged directory is deliberately NOT removed when the caller finishes: the
	/// `ModelContainer` object outlives the call (SwiftData keeps internal observers alive
	/// until dealloc), and unlinking a live container's store trips SQLite's vnode watch —
	/// it invalidates the open fds ("vnode unlinked while in use") and the broken container
	/// can then trap on a later notification callout. Temp staging dirs are swept at next
	/// launch (`sweepStagedBackupDirectories`), and the OS purges tmp/ anyway.
	nonisolated static func stagedBackupContainer(
		for backupStoreURL: URL,
		schema: Schema
	) throws -> ModelContainer {
		let fm = FileManager.default
		let stageDir = fm.temporaryDirectory
			.appendingPathComponent("staged-backup-\(UUID().uuidString)", isDirectory: true)
		try fm.createDirectory(at: stageDir, withIntermediateDirectories: true)
		let stagedStoreURL = stageDir.appendingPathComponent(backupStoreURL.lastPathComponent)
		for sidecar in ["", "-wal", "-shm"] {
			let from = URL(fileURLWithPath: backupStoreURL.path + sidecar)
			guard fm.fileExists(atPath: from.path) else { continue }
			try fm.copyItem(at: from, to: URL(fileURLWithPath: stagedStoreURL.path + sidecar))
		}
		do {
			// Writable so a pending lightweight migration can run — against the copy only.
			let config = ModelConfiguration(url: stagedStoreURL, allowsSave: true)
			return try ModelContainer(for: schema, configurations: config)
		} catch {
			// Nothing holds the copy open when the container failed to construct.
			try? fm.removeItem(at: stageDir)
			throw error
		}
	}

	/// Remove staging directories left by previous sessions (never removed live — see
	/// `stagedBackupContainer`). Called once at launch, when nothing can hold them open.
	nonisolated static func sweepStagedBackupDirectories() {
		let fm = FileManager.default
		let tmp = fm.temporaryDirectory
		guard let names = try? fm.contentsOfDirectory(atPath: tmp.path) else { return }
		for name in names where name.hasPrefix("staged-backup-") {
			try? fm.removeItem(at: tmp.appendingPathComponent(name))
		}
	}
}
