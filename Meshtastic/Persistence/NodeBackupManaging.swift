//
//  NodeBackupManaging.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import SwiftData

/// Public contract for the node database backup/restore service.
/// All methods are async and safe to call from any actor context.
@MainActor
protocol NodeBackupManaging: Sendable {

	/// Creates a backup of the current database state for the specified node.
	///
	/// - Parameters:
	///   - nodeNum: The unique node number (`NodeInfoEntity.num`) to associate with the backup
	///   - nodeName: Optional display name for the node (for UI purposes)
	/// - Returns: Result indicating success or skip reason
	/// - Note: Retries once automatically on failure before returning `.skipped`
	func createBackup(forNode nodeNum: Int64, nodeName: String?) async -> NodeBackupResult

	/// Restores a full backup by importing all entities from the backup SQLite into the live container.
	/// Call after `clearDatabase()` has emptied the live database.
	///
	/// - Parameters:
	///   - nodeNum: The node number whose backup to restore
	///   - container: The live ModelContainer to import into
	/// - Returns: Result indicating success, skip, or no backup found
	func restoreFromBackup(forNode nodeNum: Int64, into container: ModelContainer) async -> NodeBackupResult

	/// Checks whether a backup exists for the specified node.
	///
	/// - Parameter nodeNum: The node number to check
	/// - Returns: `true` if a valid backup entry exists in the index
	func hasBackup(forNode nodeNum: Int64) -> Bool

	/// Returns metadata for all existing backups.
	///
	/// - Returns: Array of backup entries sorted by most recent first
	func listBackups() -> [BackupEntry]

	/// Deletes the backup for the specified node, freeing storage.
	///
	/// - Parameter nodeNum: The node number whose backup should be deleted
	/// - Returns: `true` if backup was found and deleted, `false` if no backup existed
	@discardableResult
	func deleteBackup(forNode nodeNum: Int64) -> Bool

	/// Returns the total disk space consumed by all backups in bytes.
	var totalBackupSize: Int64 { get }
}
