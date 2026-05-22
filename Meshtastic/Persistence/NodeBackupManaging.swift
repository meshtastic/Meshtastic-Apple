//
//  NodeBackupManaging.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation

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

	/// Restores a previously backed-up database for the specified node.
	///
	/// - Parameter nodeNum: The unique node number to restore backup for
	/// - Returns: Result indicating success, skip, or no backup found
	/// - Note: Validates checksum before restoring. Returns `.skipped` if corrupt.
	func restoreBackup(forNode nodeNum: Int64) async -> NodeBackupResult

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
