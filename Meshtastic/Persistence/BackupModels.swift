//
//  BackupModels.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation

/// Identifies a backup, both as its index key and as its directory name.
///
/// Node numbers change when a radio upgrades to 2.8, so they cannot key a backup that has to survive
/// the upgrade — each renumber orphans the previous backup and starts a new one. `MyNodeInfo.device_id`
/// is the radio's hardware identifier and does not change, so it is the key wherever we have one. A
/// radio that reports no device id keeps the old node-number key and behaves as it always has.
enum BackupKey {
	/// Marks a key that is still a node number, so the two forms can be told apart on sight and in
	/// the backup folder listing.
	static let nodeNumberPrefix = "node-"

	/// The key for a radio that reported a device id. Nil for an empty id, which is what firmware
	/// sends when it has none, so callers fall through to `forNode`.
	static func forDevice(_ deviceId: Data?) -> String? {
		guard let deviceId, !deviceId.isEmpty else { return nil }
		return deviceId.map { String(format: "%02x", $0) }.joined()
	}

	static func forNode(_ nodeNum: Int64) -> String {
		"\(nodeNumberPrefix)\(nodeNum)"
	}

	/// Whether this key is still waiting to be re-keyed to a device id.
	///
	/// The suffix has to parse as a node number. The backup folder is visible in Files, so anything
	/// the user drops in there could otherwise look like one of ours and be swept as an orphan.
	static func isNodeNumberKey(_ key: String) -> Bool {
		guard key.hasPrefix(nodeNumberPrefix) else { return false }
		return Int64(key.dropFirst(nodeNumberPrefix.count)) != nil
	}
}

/// Represents a single node's backup snapshot metadata.
struct BackupEntry: Codable, Sendable {
	/// Unique node identifier (from `NodeInfoEntity.num`)
	let nodeNum: Int64
	/// Lowercase hex of the radio's `MyNodeInfo.device_id`, once we have connected to it and learned
	/// one. Nil for backups taken before this was recorded, and for radios that report no device id.
	var deviceId: String?
	/// Human-readable node display name at time of backup
	var nodeName: String?
	/// Timestamp when backup was created
	var createdAt: Date
	/// Total size of backup files in bytes
	var fileSize: Int64
	/// SHA-256 hex digest of the `.sqlite` file
	var checksum: String
	/// Relative path from `NodeBackups/` to backup directory
	var backupPath: String

	/// Where this entry belongs in the index.
	var key: String {
		deviceId ?? BackupKey.forNode(nodeNum)
	}
}

/// Top-level container for all backup metadata, stored as JSON.
struct BackupIndex: Codable, Sendable {
	/// Version 1 keyed entries by node number. Version 2 keys them by device id where one is known,
	/// and by node number otherwise, so the two forms coexist for as long as it takes to reconnect to
	/// every radio.
	static let currentVersion = 2

	/// Schema version of the index format
	var version: Int = currentVersion
	/// Map of backup key to metadata. Treat the key as opaque; use `BackupKey` to build one.
	var entries: [String: BackupEntry] = [:]
	/// Timestamp of last index modification
	var lastModified: Date = .now

	init() {}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? .now

		if let keyed = try? container.decode([String: BackupEntry].self, forKey: .entries) {
			entries = keyed
		} else {
			// Version 1. A dictionary with a non-String key encodes as a flat [key, value, key, value]
			// array rather than an object, so it has to be decoded in that shape before re-keying.
			// This is the whole of the format migration: no files are opened, renamed or deleted.
			// Entries move to their device id later, one radio at a time, as each is reconnected.
			let legacy = try container.decode([Int64: BackupEntry].self, forKey: .entries)
			entries = Dictionary(
				uniqueKeysWithValues: legacy.map { (BackupKey.forNode($0.key), $0.value) }
			)
		}

		version = Self.currentVersion
	}
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
