//
//  NodeBackupManager.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import CryptoKit
import OSLog

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
	private static let sqliteFileName = "Meshtastic.sqlite"
	private static let walFileName = "Meshtastic.sqlite-wal"
	private static let shmFileName = "Meshtastic.sqlite-shm"
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
			let sqliteFile = nodeDir.appendingPathComponent(Self.sqliteFileName)
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

			// Copy .sqlite
			let sqliteSrc = sourceURL
			let sqliteDst = nodeBackupDir.appendingPathComponent(Self.sqliteFileName)
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
		let sqliteDst = nodeBackupDir.appendingPathComponent(Self.sqliteFileName)
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
		saveIndex()

		return entry
	}

	// MARK: - T008: Restore Backup

	func restoreBackup(forNode nodeNum: Int64) async -> NodeBackupResult {
		Logger.backup.info("Attempting restore for node \(nodeNum)")

		guard let entry = backupIndex.entries[nodeNum] else {
			Logger.backup.debug("No backup found for node \(nodeNum)")
			return .noBackupFound
		}

		// Retry-once logic (FR-004)
		for attempt in 1...2 {
			do {
				let restoredEntry = try await performRestore(entry: entry)
				Logger.backup.info("Restore completed for node \(nodeNum)")
				return .success(restoredEntry)
			} catch {
				if attempt == 1 {
					Logger.backup.warning("Restore attempt 1 failed for node \(nodeNum), retrying: \(error.localizedDescription, privacy: .public)")
				} else {
					Logger.backup.error("Restore failed after retry for node \(nodeNum): \(error.localizedDescription, privacy: .public)")
					return .skipped(reason: "Restore failed: \(error.localizedDescription)")
				}
			}
		}

		return .skipped(reason: "Restore failed unexpectedly")
	}

	private func performRestore(entry: BackupEntry) async throws -> BackupEntry {
		let nodeBackupDir = backupBaseURL.appendingPathComponent(entry.backupPath, isDirectory: true)
		let sqliteBackup = nodeBackupDir.appendingPathComponent(Self.sqliteFileName)

		// Validate checksum (FR-007)
		let currentChecksum = try await computeChecksum(for: sqliteBackup)
		guard currentChecksum == entry.checksum else {
			// T028: Delete corrupt backup
			Logger.backup.error("Checksum mismatch for node \(entry.nodeNum) — backup is corrupt, deleting")
			deleteBackup(forNode: entry.nodeNum)
			throw BackupError.checksumMismatch
		}

		// Get destination database path
		let destinationURL = self.activeDatabaseURL()
		let destinationDir = destinationURL.deletingLastPathComponent()

		// Replace files on background thread
		try await Task.detached(priority: .userInitiated) { [fileManager] in
			// Remove existing database files
			let sqliteDst = destinationDir.appendingPathComponent(Self.sqliteFileName)
			let walDst = destinationDir.appendingPathComponent(Self.walFileName)
			let shmDst = destinationDir.appendingPathComponent(Self.shmFileName)

			try? fileManager.removeItem(at: sqliteDst)
			try? fileManager.removeItem(at: walDst)
			try? fileManager.removeItem(at: shmDst)

			// Copy backup to active location
			try fileManager.copyItem(at: sqliteBackup, to: sqliteDst)

			// Copy WAL if present
			let walBackup = nodeBackupDir.appendingPathComponent(Self.walFileName)
			if fileManager.fileExists(atPath: walBackup.path) {
				try fileManager.copyItem(at: walBackup, to: walDst)
			}

			// Copy SHM if present
			let shmBackup = nodeBackupDir.appendingPathComponent(Self.shmFileName)
			if fileManager.fileExists(atPath: shmBackup.path) {
				try fileManager.copyItem(at: shmBackup, to: shmDst)
			}
		}.value

		return entry
	}

	// MARK: - T009: Query Methods

	func hasBackup(forNode nodeNum: Int64) -> Bool {
		backupIndex.entries[nodeNum] != nil
	}

	func listBackups() -> [BackupEntry] {
		Array(backupIndex.entries.values).sorted { $0.createdAt > $1.createdAt }
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
		return appSupport.appendingPathComponent("default.store")
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
