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
	///   - deviceId: The radio's `MyNodeInfo.device_id`, which keys the backup. Node numbers change
	///     when a radio upgrades to 2.8; a device id does not. Nil keeps the node-number key.
	///   - nodeName: Optional display name for the node (for UI purposes)
	/// - Returns: Result indicating success or skip reason
	/// - Note: Retries once automatically on failure before returning `.skipped`
	func createBackup(forNode nodeNum: Int64, deviceId: Data?, nodeName: String?) async -> NodeBackupResult

	/// Moves this radio's backup from a node-number key onto its device id, collapsing any duplicates
	/// left behind by earlier renumbers. Call on connect; it is cheap once a radio has been adopted.
	///
	/// - Parameters:
	///   - deviceId: The connected radio's `MyNodeInfo.device_id`. Nil does nothing.
	///   - nodeNum: The node number the radio reports now
	///   - peripheralId: The connection's identifier, which is how backups filed under *earlier* node
	///     numbers are found
	func adoptLegacyBackups(deviceId: Data?, nodeNum: Int64, peripheralId: String?) async

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

	/// Deletes a backup, freeing storage.
	///
	/// - Parameter key: The entry's `BackupEntry.key`. Treat it as opaque — it is a device id for a
	///   radio we have connected to since this change, and a node number otherwise.
	/// - Returns: `true` if backup was found and deleted, `false` if no backup existed
	@discardableResult
	func deleteBackup(forKey key: String) -> Bool

	/// Returns the total disk space consumed by all backups in bytes.
	var totalBackupSize: Int64 { get }
}
