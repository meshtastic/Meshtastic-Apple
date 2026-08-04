//
//  BackupModels.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation

/// Represents a single node's backup snapshot metadata.
struct BackupEntry: Codable, Sendable {
	/// Unique node identifier (from `NodeInfoEntity.num`)
	let nodeNum: Int64
	/// Human-readable node display name at time of backup
	var nodeName: String?
	/// Canonical firmware identity observed when the backup was created.
	var deviceID: String?
	/// Timestamp when backup was created
	var createdAt: Date
	/// Total size of backup files in bytes
	var fileSize: Int64
	/// SHA-256 hex digest of the `.sqlite` file
	var checksum: String
	/// Relative path from `NodeBackups/` to backup directory
	var backupPath: String

	init(
		nodeNum: Int64,
		nodeName: String?,
		deviceID: String? = nil,
		createdAt: Date,
		fileSize: Int64,
		checksum: String,
		backupPath: String
	) {
		self.nodeNum = nodeNum
		self.nodeName = nodeName
		self.deviceID = deviceID
		self.createdAt = createdAt
		self.fileSize = fileSize
		self.checksum = checksum
		self.backupPath = backupPath
	}
}

/// Top-level container for all backup metadata, stored as JSON.
struct BackupIndex: Codable, Sendable {
	static let currentVersion = 2

	/// Schema version of the index format
	var version: Int = currentVersion
	/// Map of node number to backup metadata
	var entries: [Int64: BackupEntry] = [:]
	/// Timestamp of last index modification
	var lastModified: Date = .now
}

/// Represents the outcome of a backup or restore operation.
enum NodeBackupResult: Sendable {
	/// Operation completed successfully
	case success(BackupEntry)
	/// Operation was skipped (no data, failed after retry, insufficient storage)
	case skipped(reason: String)
	/// No existing backup for the target node
	case noBackupFound
}
