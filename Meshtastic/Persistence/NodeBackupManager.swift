//
//  NodeBackupManager.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import CryptoKit
import OSLog
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
		let sqliteBackup = nodeBackupDir.appendingPathComponent(Self.storeFileName)

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
			let sqliteDst = destinationDir.appendingPathComponent(Self.storeFileName)
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

	/// Swaps the active database files with a backup for the given node.
	/// If no backup exists, deletes the active files so a fresh database is created.
	/// Call this BEFORE recreating the ModelContainer.
	func swapDatabaseFiles(forNode nodeNum: Int64?) {
		let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		let activeStore = appSupport.appendingPathComponent(Self.storeFileName)
		let activeWal = appSupport.appendingPathComponent(Self.walFileName)
		let activeShm = appSupport.appendingPathComponent(Self.shmFileName)

		// Remove current database files
		try? fileManager.removeItem(at: activeStore)
		try? fileManager.removeItem(at: activeWal)
		try? fileManager.removeItem(at: activeShm)
		Logger.backup.info("Removed active database files for swap")

		// If target has a backup, copy it in
		guard let nodeNum,
			  let entry = backupIndex.entries[nodeNum] else {
			Logger.backup.info("No backup for target — fresh database will be created")
			return
		}

		let nodeBackupDir = backupBaseURL.appendingPathComponent(entry.backupPath, isDirectory: true)
		let backupStore = nodeBackupDir.appendingPathComponent(Self.storeFileName)

		guard fileManager.fileExists(atPath: backupStore.path) else {
			Logger.backup.warning("Backup store file missing for node \(nodeNum)")
			return
		}

		do {
			try fileManager.copyItem(at: backupStore, to: activeStore)

			let walBackup = nodeBackupDir.appendingPathComponent(Self.walFileName)
			if fileManager.fileExists(atPath: walBackup.path) {
				try fileManager.copyItem(at: walBackup, to: activeWal)
			}

			let shmBackup = nodeBackupDir.appendingPathComponent(Self.shmFileName)
			if fileManager.fileExists(atPath: shmBackup.path) {
				try fileManager.copyItem(at: shmBackup, to: activeShm)
			}

			Logger.backup.info("Database files swapped to backup for node \(nodeNum)")
		} catch {
			Logger.backup.error("Failed to swap database files for node \(nodeNum): \(error.localizedDescription, privacy: .public)")
		}
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

	// MARK: - Import Helpers

	nonisolated private static func importNodes(from backupContext: ModelContext, into liveContext: ModelContext) throws -> [Int64: NodeInfoEntity] {
		let backupNodes = try backupContext.fetch(FetchDescriptor<NodeInfoEntity>())
		var nodesByNum: [Int64: NodeInfoEntity] = [:]
		for src in backupNodes {
			let dst = NodeInfoEntity()
			dst.bleName = src.bleName
			dst.channel = src.channel
			dst.favorite = src.favorite
			dst.firstHeard = src.firstHeard
			dst.hopsAway = src.hopsAway
			dst.ignored = src.ignored
			dst.lastHeard = src.lastHeard
			dst.num = src.num
			dst.peripheralId = src.peripheralId
			dst.rssi = src.rssi
			dst.sessionExpiration = src.sessionExpiration
			dst.sessionPasskey = src.sessionPasskey
			dst.snr = src.snr
			dst.viaMqtt = src.viaMqtt
			liveContext.insert(dst)
			nodesByNum[dst.num] = dst
		}
		return nodesByNum
	}

	nonisolated private static func importUsers(from backupContext: ModelContext, into liveContext: ModelContext, nodesByNum: [Int64: NodeInfoEntity]) throws -> [Int64: UserEntity] {
		let backupUsers = try backupContext.fetch(FetchDescriptor<UserEntity>())
		var usersByNum: [Int64: UserEntity] = [:]
		for src in backupUsers {
			let dst = UserEntity()
			dst.hwDisplayName = src.hwDisplayName
			dst.hwModel = src.hwModel
			dst.hwModelId = src.hwModelId
			dst.isLicensed = src.isLicensed
			dst.keyMatch = src.keyMatch
			dst.lastMessage = src.lastMessage
			dst.longName = src.longName
			dst.mute = src.mute
			dst.newPublicKey = src.newPublicKey
			dst.num = src.num
			dst.numString = src.numString
			dst.pkiEncrypted = src.pkiEncrypted
			dst.publicKey = src.publicKey
			dst.role = src.role
			dst.shortName = src.shortName
			dst.unmessagable = src.unmessagable
			dst.userId = src.userId
			if let srcNode = src.userNode, let liveNode = nodesByNum[srcNode.num] {
				dst.userNode = liveNode
			}
			liveContext.insert(dst)
			usersByNum[dst.num] = dst
		}
		return usersByNum
	}

	nonisolated private static func importMyInfo(from backupContext: ModelContext, into liveContext: ModelContext, nodesByNum: [Int64: NodeInfoEntity]) throws -> [Int64: MyInfoEntity] {
		let backupMyInfos = try backupContext.fetch(FetchDescriptor<MyInfoEntity>())
		var myInfosByNodeNum: [Int64: MyInfoEntity] = [:]
		for src in backupMyInfos {
			let dst = MyInfoEntity()
			dst.bleName = src.bleName
			dst.deviceId = src.deviceId
			dst.minAppVersion = src.minAppVersion
			dst.myNodeNum = src.myNodeNum
			dst.peripheralId = src.peripheralId
			dst.pioEnv = src.pioEnv
			dst.rebootCount = src.rebootCount
			dst.registered = src.registered
			if let srcNode = src.myInfoNode, let liveNode = nodesByNum[srcNode.num] {
				dst.myInfoNode = liveNode
				myInfosByNodeNum[srcNode.num] = dst
			}
			liveContext.insert(dst)
		}
		return myInfosByNodeNum
	}

	nonisolated private static func importChannels(from backupContext: ModelContext, into liveContext: ModelContext, myInfosByNodeNum: [Int64: MyInfoEntity]) throws {
		let backupChannels = try backupContext.fetch(FetchDescriptor<ChannelEntity>())
		for src in backupChannels {
			let dst = ChannelEntity()
			dst.downlinkEnabled = src.downlinkEnabled
			dst.id = src.id
			dst.index = src.index
			dst.mute = src.mute
			dst.name = src.name
			dst.positionPrecision = src.positionPrecision
			dst.psk = src.psk
			dst.role = src.role
			dst.uplinkEnabled = src.uplinkEnabled
			if let srcMyInfo = src.myInfoChannel,
			   let srcNode = srcMyInfo.myInfoNode,
			   let liveMyInfo = myInfosByNodeNum[srcNode.num] {
				dst.myInfoChannel = liveMyInfo
			}
			liveContext.insert(dst)
		}
	}

	nonisolated private static func importMetadata(from backupContext: ModelContext, into liveContext: ModelContext, nodesByNum: [Int64: NodeInfoEntity]) throws {
		let backupMetadata = try backupContext.fetch(FetchDescriptor<DeviceMetadataEntity>())
		for src in backupMetadata {
			let dst = DeviceMetadataEntity()
			dst.canShutdown = src.canShutdown
			dst.deviceStateVersion = src.deviceStateVersion
			dst.excludedModules = src.excludedModules
			dst.firmwareVersion = src.firmwareVersion
			dst.hasBluetooth = src.hasBluetooth
			dst.hasEthernet = src.hasEthernet
			dst.hasWifi = src.hasWifi
			dst.hwModel = src.hwModel
			dst.positionFlags = src.positionFlags
			dst.role = src.role
			dst.time = src.time
			if let srcNode = src.metadataNode, let liveNode = nodesByNum[srcNode.num] {
				dst.metadataNode = liveNode
			}
			liveContext.insert(dst)
		}
	}

	nonisolated private static func importPositions(from backupContext: ModelContext, into liveContext: ModelContext, nodesByNum: [Int64: NodeInfoEntity]) throws {
		let backupPositions = try backupContext.fetch(FetchDescriptor<PositionEntity>())
		for src in backupPositions {
			let dst = PositionEntity()
			dst.altitude = src.altitude
			dst.heading = src.heading
			dst.latest = src.latest
			dst.latitudeI = src.latitudeI
			dst.longitudeI = src.longitudeI
			dst.precisionBits = src.precisionBits
			dst.rssi = src.rssi
			dst.satsInView = src.satsInView
			dst.seqNo = src.seqNo
			dst.snr = src.snr
			dst.speed = src.speed
			dst.time = src.time
			if let srcNode = src.nodePosition, let liveNode = nodesByNum[srcNode.num] {
				dst.nodePosition = liveNode
			}
			liveContext.insert(dst)
		}
	}

	nonisolated private static func importTelemetry(from backupContext: ModelContext, into liveContext: ModelContext, nodesByNum: [Int64: NodeInfoEntity]) throws {
		let backupTelemetry = try backupContext.fetch(FetchDescriptor<TelemetryEntity>())
		for src in backupTelemetry {
			let dst = TelemetryEntity()
			dst.metricsType = src.metricsType
			dst.time = src.time
			dst.airUtilTx = src.airUtilTx
			dst.barometricPressure = src.barometricPressure
			dst.batteryLevel = src.batteryLevel
			dst.channelUtilization = src.channelUtilization
			dst.current = src.current
			dst.distance = src.distance
			dst.gasResistance = src.gasResistance
			dst.iaq = src.iaq
			dst.irLux = src.irLux
			dst.lux = src.lux
			dst.numOnlineNodes = src.numOnlineNodes
			dst.numPacketsRx = src.numPacketsRx
			dst.numPacketsRxBad = src.numPacketsRxBad
			dst.numPacketsTx = src.numPacketsTx
			dst.numRxDupe = src.numRxDupe
			dst.numTotalNodes = src.numTotalNodes
			dst.numTxRelay = src.numTxRelay
			dst.numTxRelayCanceled = src.numTxRelayCanceled
			dst.powerCh1Current = src.powerCh1Current
			dst.powerCh1Voltage = src.powerCh1Voltage
			dst.powerCh2Current = src.powerCh2Current
			dst.powerCh2Voltage = src.powerCh2Voltage
			dst.powerCh3Current = src.powerCh3Current
			dst.powerCh3Voltage = src.powerCh3Voltage
			dst.radiation = src.radiation
			dst.rainfall1H = src.rainfall1H
			dst.rainfall24H = src.rainfall24H
			dst.relativeHumidity = src.relativeHumidity
			dst.rssi = src.rssi
			dst.snr = src.snr
			dst.soilMoisture = src.soilMoisture
			dst.soilTemperature = src.soilTemperature
			dst.temperature = src.temperature
			dst.uptimeSeconds = src.uptimeSeconds
			dst.uvLux = src.uvLux
			dst.voltage = src.voltage
			dst.weight = src.weight
			dst.whiteLux = src.whiteLux
			dst.windDirection = src.windDirection
			dst.windGust = src.windGust
			dst.windLull = src.windLull
			dst.windSpeed = src.windSpeed
			if let srcNode = src.nodeTelemetry, let liveNode = nodesByNum[srcNode.num] {
				dst.nodeTelemetry = liveNode
			}
			liveContext.insert(dst)
		}
	}

	nonisolated private static func importMessages(from backupContext: ModelContext, into liveContext: ModelContext, usersByNum: [Int64: UserEntity]) throws {
		let backupMessages = try backupContext.fetch(FetchDescriptor<MessageEntity>())
		for src in backupMessages {
			let dst = MessageEntity()
			dst.ackError = src.ackError
			dst.ackSNR = src.ackSNR
			dst.ackTimestamp = src.ackTimestamp
			dst.admin = src.admin
			dst.adminDescription = src.adminDescription
			dst.channel = src.channel
			dst.isEmoji = src.isEmoji
			dst.messageId = src.messageId
			dst.messagePayload = src.messagePayload
			dst.messagePayloadMarkdown = src.messagePayloadMarkdown
			dst.messagePayloadTranslated = src.messagePayloadTranslated
			dst.messagePayloadTranslatedMarkdown = src.messagePayloadTranslatedMarkdown
			dst.messageTimestamp = src.messageTimestamp
			dst.pkiEncrypted = src.pkiEncrypted
			dst.portNum = src.portNum
			dst.publicKey = src.publicKey
			dst.read = src.read
			dst.realACK = src.realACK
			dst.receivedACK = src.receivedACK
			dst.relayNode = src.relayNode
			dst.relays = src.relays
			dst.replyID = src.replyID
			dst.rssi = src.rssi
			dst.showTranslatedMessage = src.showTranslatedMessage
			dst.snr = src.snr
			if let fromNum = src.fromUser?.num, let liveUser = usersByNum[fromNum] {
				dst.fromUser = liveUser
			}
			if let toNum = src.toUser?.num, let liveUser = usersByNum[toNum] {
				dst.toUser = liveUser
			}
			liveContext.insert(dst)
		}
	}

	nonisolated private static func importWaypoints(from backupContext: ModelContext, into liveContext: ModelContext) throws {
		let backupWaypoints = try backupContext.fetch(FetchDescriptor<WaypointEntity>())
		for src in backupWaypoints {
			let dst = WaypointEntity()
			dst.created = src.created
			dst.createdBy = src.createdBy
			dst.expire = src.expire
			dst.icon = src.icon
			dst.id = src.id
			dst.lastUpdated = src.lastUpdated
			dst.lastUpdatedBy = src.lastUpdatedBy
			dst.latitudeI = src.latitudeI
			dst.locked = src.locked
			dst.longDescription = src.longDescription
			dst.longitudeI = src.longitudeI
			dst.name = src.name
			liveContext.insert(dst)
		}
	}

	nonisolated private static func importTraceRoutes(from backupContext: ModelContext, into liveContext: ModelContext, nodesByNum: [Int64: NodeInfoEntity]) throws {
		let backupTraceRoutes = try backupContext.fetch(FetchDescriptor<TraceRouteEntity>())
		for src in backupTraceRoutes {
			let dst = TraceRouteEntity()
			dst.id = src.id
			dst.hasPositions = src.hasPositions
			dst.hopsBack = src.hopsBack
			dst.hopsTowards = src.hopsTowards
			dst.response = src.response
			dst.routeBackText = src.routeBackText
			dst.routeText = src.routeText
			dst.sent = src.sent
			dst.snr = src.snr
			dst.time = src.time
			if let srcNode = src.node, let liveNode = nodesByNum[srcNode.num] {
				dst.node = liveNode
			}
			liveContext.insert(dst)
			for srcHop in src.hops {
				let dstHop = TraceRouteHopEntity()
				dstHop.altitude = srcHop.altitude
				dstHop.back = srcHop.back
				dstHop.latitudeI = srcHop.latitudeI
				dstHop.longitudeI = srcHop.longitudeI
				dstHop.name = srcHop.name
				dstHop.num = srcHop.num
				dstHop.snr = srcHop.snr
				dstHop.time = srcHop.time
				dstHop.traceRoute = dst
				liveContext.insert(dstHop)
			}
		}
	}

	nonisolated private static func importPaxCounters(from backupContext: ModelContext, into liveContext: ModelContext, nodesByNum: [Int64: NodeInfoEntity]) throws {
		let backupPax = try backupContext.fetch(FetchDescriptor<PaxCounterEntity>())
		for src in backupPax {
			let dst = PaxCounterEntity()
			dst.ble = src.ble
			dst.time = src.time
			dst.uptime = src.uptime
			dst.wifi = src.wifi
			if let srcNode = src.paxNode, let liveNode = nodesByNum[srcNode.num] {
				dst.paxNode = liveNode
			}
			liveContext.insert(dst)
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
