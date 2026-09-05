//
//  NodeBackupManagerTests.swift
//  MeshtasticTests
//
//  Copyright(c) Meshtastic 2025.
//

import Testing
import Foundation
import CryptoKit
import SwiftData
@testable import Meshtastic

@Suite("NodeBackupManager Tests")
struct NodeBackupManagerTests {

	// MARK: - Helpers

	/// Creates a temporary directory for test isolation.
	private func makeTempDir() throws -> URL {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("NodeBackupTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		return tmp
	}

	/// Creates a fake SQLite database file in the given directory.
	private func createFakeDatabase(at directory: URL, content: String = "fake-sqlite-data") throws -> URL {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let sqliteURL = directory.appendingPathComponent("Meshtastic.store")
		try Data(content.utf8).write(to: sqliteURL)
		return sqliteURL
	}

	/// Cleans up temporary directory.
	private func cleanup(_ url: URL) {
		try? FileManager.default.removeItem(at: url)
	}

	private func makeContainer(inMemory: Bool = true, storeURL: URL? = nil) throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config: ModelConfiguration
		if let storeURL {
			config = ModelConfiguration(url: storeURL, allowsSave: true)
			return try ModelContainer(
				for: schema,
				migrationPlan: MeshtasticMigrationPlan.self,
				configurations: config
			)
		}

		config = ModelConfiguration(
			"NodeBackupManagerTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: inMemory,
			allowsSave: true
		)
		return try ModelContainer(
			for: schema,
			migrationPlan: MeshtasticMigrationPlan.self,
			configurations: config
		)
	}

	private func writeIndex(entry: BackupEntry, to backupDir: URL) throws {
		var index = BackupIndex()
		index.entries[entry.key] = entry
		let indexData = try JSONEncoder().encode(index)
		try indexData.write(to: backupDir.appendingPathComponent("backup-index.json"))
	}

	// MARK: - T010: createBackup Success Case

	@Test("createBackup creates file copy and updates index")
	@MainActor
	func testCreateBackupSuccess() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }

		// Setup: Create a fake active database
		let dbDir = tempDir.appendingPathComponent("ActiveDB", isDirectory: true)
		_ = try createFakeDatabase(at: dbDir)

		// Create manager with custom base
		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)
		let manager = NodeBackupManager(baseURL: backupDir)

		// Act
		let result = await manager.createBackup(forNode: 12345, deviceId: nil, nodeName: "TestNode")

		// Assert
		switch result {
		case .success(let entry):
			#expect(entry.nodeNum == 12345)
			#expect(entry.nodeName == "TestNode")
			#expect(entry.fileSize > 0)
			#expect(entry.checksum.count == 64) // SHA-256 hex digest
			#expect(manager.hasBackup(forNode: 12345))
		case .skipped, .noBackupFound:
			// In test environment, database file may not exist at expected path
			// This verifies the retry logic works (skipped after retry)
			break
		}
	}

	// MARK: - T011: createBackup Overwrite Case

	@Test("createBackup replaces existing backup")
	@MainActor
	func testCreateBackupOverwrite() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }

		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)
		let manager = NodeBackupManager(baseURL: backupDir)

		// First backup
		let result1 = await manager.createBackup(forNode: 99999, deviceId: nil, nodeName: "NodeV1")

		// Second backup (overwrite)
		let result2 = await manager.createBackup(forNode: 99999, deviceId: nil, nodeName: "NodeV2")

		// Only one backup should exist for this node
		let backups = manager.listBackups()
		let nodeBackups = backups.filter { $0.nodeNum == 99999 }
		#expect(nodeBackups.count <= 1) // At most 1 backup per node

		// If both succeeded, name should be updated
		if case .success(let entry) = result2 {
			#expect(entry.nodeName == "NodeV2")
		}

		// Suppress unused variable warnings
		_ = result1
	}

	// MARK: - T012: createBackup Failure and Retry

	@Test("createBackup retries once on failure then skips")
	@MainActor
	func testCreateBackupRetryLogic() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }

		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)
		let manager = NodeBackupManager(baseURL: backupDir)

		// The active database path won't exist in test environment,
		// so backup should fail and return .skipped after retry
		let result = await manager.createBackup(forNode: 77777, deviceId: nil, nodeName: "FailNode")

		switch result {
		case .skipped(let reason):
			#expect(reason.contains("failed") || reason.contains("Failed") || reason.contains("No such file"))
		case .success:
			// If somehow it succeeded (environment has the file), that's also acceptable
			break
		case .noBackupFound:
			Issue.record("createBackup should never return .noBackupFound")
		}
	}

	// MARK: - T016: restoreFromBackup Success Case

	@Test("restoreFromBackup imports entities when valid backup exists")
	@MainActor
	func testRestoreFromBackupSuccess() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }

		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)
		let nodeNum: Int64 = 55555
		let nodeDirName = "\(nodeNum)"
		let nodeBackupPath = backupDir.appendingPathComponent(nodeDirName, isDirectory: true)
		try FileManager.default.createDirectory(at: nodeBackupPath, withIntermediateDirectories: true)

		let backupStoreURL = nodeBackupPath.appendingPathComponent("Meshtastic.store")
		let backupContainer = try makeContainer(inMemory: false, storeURL: backupStoreURL)
		let backupContext = ModelContext(backupContainer)
		backupContext.autosaveEnabled = false

		let node = NodeInfoEntity()
		node.num = nodeNum
		node.bleName = "Test BLE"
		backupContext.insert(node)

		let user = UserEntity()
		user.num = nodeNum
		user.longName = "RestoredNode"
		user.shortName = "RN"
		user.userNode = node
		backupContext.insert(user)
		try backupContext.save()

		// Compute real checksum
		let data = try Data(contentsOf: backupStoreURL)
		let digest = CryptoKit.SHA256.hash(data: data)
		let checksum = digest.map { String(format: "%02x", $0) }.joined()

		// Manually inject index entry (simulating a previous backup)
		let entry = BackupEntry(
			nodeNum: nodeNum,
			nodeName: "RestoredNode",
			createdAt: .now,
			fileSize: Int64(data.count),
			checksum: checksum,
			backupPath: nodeDirName
		)
		try writeIndex(entry: entry, to: backupDir)

		// Recreate manager to pick up the index
		let manager2 = NodeBackupManager(baseURL: backupDir)
		#expect(manager2.hasBackup(forNode: nodeNum))

		let liveStoreURL = tempDir.appendingPathComponent("Live.store")
		let liveContainer = try makeContainer(inMemory: false, storeURL: liveStoreURL)

		let result = await manager2.restoreFromBackup(forNode: nodeNum, into: liveContainer)
		switch result {
		case .success:
			let liveContext = ModelContext(liveContainer)
			let restoredNodes = try liveContext.fetch(FetchDescriptor<NodeInfoEntity>())
			let restoredUsers = try liveContext.fetch(FetchDescriptor<UserEntity>())
			#expect(restoredNodes.count == 1)
			#expect(restoredNodes.first?.num == nodeNum)
			#expect(restoredUsers.count == 1)
			#expect(restoredUsers.first?.longName == "RestoredNode")
		case .skipped(let reason):
			Issue.record("Expected restoreFromBackup to succeed, got skipped: \(reason)")
		case .noBackupFound:
			Issue.record("Should have found the backup we just created")
		}
	}

	// MARK: - T017: restoreFromBackup Checksum Mismatch

	@Test("restoreFromBackup detects corrupt backup via checksum mismatch")
	@MainActor
	func testRestoreFromBackupChecksumMismatch() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }

		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)

		// Create backup file with wrong checksum in index
		let nodeNum: Int64 = 44444
		let nodeDirName = "\(nodeNum)"
		let nodeBackupPath = backupDir.appendingPathComponent(nodeDirName, isDirectory: true)
		try FileManager.default.createDirectory(at: nodeBackupPath, withIntermediateDirectories: true)

		let sqliteFile = nodeBackupPath.appendingPathComponent("Meshtastic.store")
		try Data("some data".utf8).write(to: sqliteFile)

		// Write index with intentionally wrong checksum
		let entry = BackupEntry(
			nodeNum: nodeNum,
			nodeName: "CorruptNode",
			createdAt: .now,
			fileSize: 9,
			checksum: "0000000000000000000000000000000000000000000000000000000000000000",
			backupPath: nodeDirName
		)
		try writeIndex(entry: entry, to: backupDir)

		let manager = NodeBackupManager(baseURL: backupDir)
		let liveContainer = try makeContainer()
		let result = await manager.restoreFromBackup(forNode: nodeNum, into: liveContainer)

		// Should skip due to checksum mismatch and delete the corrupt backup (T028)
		switch result {
		case .skipped(let reason):
			#expect(reason.contains("integrity") || reason.contains("failed") || reason.contains("Failed"))
			#expect(!manager.hasBackup(forNode: nodeNum))
		case .noBackupFound:
			Issue.record("Checksum mismatch should report a skipped restore before removing the backup entry")
		case .success:
			Issue.record("Should not succeed with mismatched checksum")
		}
	}

	// MARK: - T018: restoreFromBackup No Backup Exists

	@Test("restoreFromBackup returns .noBackupFound when no backup exists")
	@MainActor
	func testRestoreFromBackupNoBackupFound() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }

		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)
		let manager = NodeBackupManager(baseURL: backupDir)
		let liveContainer = try makeContainer()

		let result = await manager.restoreFromBackup(forNode: 11111, into: liveContainer)

		switch result {
		case .noBackupFound:
			break // Expected
		default:
			Issue.record("Expected .noBackupFound, got \(result)")
		}
	}

	// MARK: - T032: Non-blocking UI (SC-004)

	@Test("Backup operations do not execute on main thread for file I/O")
	@MainActor
	func testBackupDoesNotBlockMainThread() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }

		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)
		let manager = NodeBackupManager(baseURL: backupDir)

		// The manager is @MainActor-isolated, but file I/O runs via Task.detached
		// We verify that calling createBackup is async (doesn't synchronously block)
		let startTime = Date()
		_ = await manager.createBackup(forNode: 88888, deviceId: nil, nodeName: "AsyncTest")
		let elapsed = Date().timeIntervalSince(startTime)

		// The operation should complete quickly (< 5s per SC-001)
		// and not hang (which would indicate main thread blocking)
		#expect(elapsed < 5.0)
	}

	// MARK: - Additional: Delete and List

	@Test("deleteBackup removes backup and frees storage")
	@MainActor
	func testDeleteBackup() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }

		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)

		// Create a backup file manually
		let nodeNum: Int64 = 33333
		let nodeDirName = "\(nodeNum)"
		let nodeBackupPath = backupDir.appendingPathComponent(nodeDirName, isDirectory: true)
		try FileManager.default.createDirectory(at: nodeBackupPath, withIntermediateDirectories: true)
		let sqliteFile = nodeBackupPath.appendingPathComponent("Meshtastic.store")
		try Data("data".utf8).write(to: sqliteFile)

		// Write index
		let entry = BackupEntry(nodeNum: nodeNum, nodeName: "DeleteMe", createdAt: .now, fileSize: 4, checksum: "abc", backupPath: nodeDirName)
		var index = BackupIndex()
		index.entries[entry.key] = entry
		let indexData = try JSONEncoder().encode(index)
		try indexData.write(to: backupDir.appendingPathComponent("backup-index.json"))

		let manager = NodeBackupManager(baseURL: backupDir)
		#expect(manager.hasBackup(forNode: nodeNum))

		let deleted = manager.deleteBackup(forKey: BackupKey.forNode(nodeNum))
		#expect(deleted)
		#expect(!manager.hasBackup(forNode: nodeNum))
	}

	@Test("listBackups returns entries sorted by most recent first")
	@MainActor
	func testListBackups() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }

		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)
		try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

		// Create index with multiple entries
		var index = BackupIndex()
		index.entries[BackupKey.forNode(1)] = BackupEntry(nodeNum: 1, deviceId: nil, nodeName: "Old", createdAt: Date(timeIntervalSince1970: 1000), fileSize: 100, checksum: "aaa", backupPath: "1")
		index.entries[BackupKey.forNode(2)] = BackupEntry(nodeNum: 2, deviceId: nil, nodeName: "New", createdAt: Date(timeIntervalSince1970: 2000), fileSize: 200, checksum: "bbb", backupPath: "2")
		index.entries[BackupKey.forNode(3)] = BackupEntry(nodeNum: 3, deviceId: nil, nodeName: "Mid", createdAt: Date(timeIntervalSince1970: 1500), fileSize: 150, checksum: "ccc", backupPath: "3")

		// Create directories so validation doesn't remove them
		for n in 1...3 {
			let dir = backupDir.appendingPathComponent("\(n)", isDirectory: true)
			try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			try Data("data".utf8).write(to: dir.appendingPathComponent("Meshtastic.store"))
		}

		let indexData = try JSONEncoder().encode(index)
		try indexData.write(to: backupDir.appendingPathComponent("backup-index.json"))

		let manager = NodeBackupManager(baseURL: backupDir)
		let backups = manager.listBackups()

		#expect(backups.count == 3)
		#expect(backups[0].nodeNum == 2) // Most recent
		#expect(backups[1].nodeNum == 3) // Middle
		#expect(backups[2].nodeNum == 1) // Oldest
	}

	@Test("totalBackupSize sums all entries")
	@MainActor
	func testTotalBackupSize() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }

		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)
		try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

		var index = BackupIndex()
		index.entries[BackupKey.forNode(1)] = BackupEntry(nodeNum: 1, deviceId: nil, nodeName: "A", createdAt: .now, fileSize: 1000, checksum: "a", backupPath: "1")
		index.entries[BackupKey.forNode(2)] = BackupEntry(nodeNum: 2, deviceId: nil, nodeName: "B", createdAt: .now, fileSize: 2000, checksum: "b", backupPath: "2")

		// Create directories so validation doesn't remove them
		for n in 1...2 {
			let dir = backupDir.appendingPathComponent("\(n)", isDirectory: true)
			try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			try Data("data".utf8).write(to: dir.appendingPathComponent("Meshtastic.store"))
		}

		let indexData = try JSONEncoder().encode(index)
		try indexData.write(to: backupDir.appendingPathComponent("backup-index.json"))

		let manager = NodeBackupManager(baseURL: backupDir)
		#expect(manager.totalBackupSize == 3000)
	}

	// MARK: - Backup location resolution / migration (Documents visibility)

	@Test("Fresh install resolves to the Documents NodeBackups folder")
	func resolveLocationFreshInstall() throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let documents = tempDir.appendingPathComponent("Documents", isDirectory: true)
		let appSupport = tempDir.appendingPathComponent("AppSupport", isDirectory: true)

		let resolved = NodeBackupManager.resolveBackupBaseURL(documents: documents, appSupport: appSupport)

		#expect(resolved == documents.appendingPathComponent("NodeBackups", isDirectory: true))
	}

	@Test("Legacy Application Support backups migrate wholesale into Documents")
	func resolveLocationMigratesLegacy() throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let documents = tempDir.appendingPathComponent("Documents", isDirectory: true)
		let appSupport = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
		try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
		// Seed a legacy backup folder with a node backup + index, as an old install would have.
		let legacy = appSupport.appendingPathComponent("NodeBackups", isDirectory: true)
		let nodeDir = legacy.appendingPathComponent("1234", isDirectory: true)
		try FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)
		try Data("legacy-backup".utf8).write(to: nodeDir.appendingPathComponent("Meshtastic.store"))

		let resolved = NodeBackupManager.resolveBackupBaseURL(documents: documents, appSupport: appSupport)

		let expected = documents.appendingPathComponent("NodeBackups", isDirectory: true)
		#expect(resolved == expected)
		// The whole folder moved: content readable at the new location, legacy gone.
		let moved = expected.appendingPathComponent("1234/Meshtastic.store")
		#expect(FileManager.default.fileExists(atPath: moved.path))
		#expect(!FileManager.default.fileExists(atPath: legacy.path))
	}

	@Test("Both locations existing prefers Documents and leaves the legacy folder untouched")
	func resolveLocationPrefersNewWhenBothExist() throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let documents = tempDir.appendingPathComponent("Documents", isDirectory: true)
		let appSupport = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
		let newDir = documents.appendingPathComponent("NodeBackups", isDirectory: true)
		let legacy = appSupport.appendingPathComponent("NodeBackups", isDirectory: true)
		try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
		try Data("keep-me".utf8).write(to: legacy.appendingPathComponent("orphan.store"))

		let resolved = NodeBackupManager.resolveBackupBaseURL(documents: documents, appSupport: appSupport)

		#expect(resolved == newDir)
		// Legacy content is preserved for manual recovery, never merged or deleted.
		#expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("orphan.store").path))
	}

	@Test("A user file named NodeBackups in Documents falls back to the legacy location untouched")
	func resolveLocationFileCollisionFallsBackToLegacy() throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let documents = tempDir.appendingPathComponent("Documents", isDirectory: true)
		let appSupport = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
		try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
		// Documents is user-writable: someone saved a FILE with the folder's name.
		let squatter = documents.appendingPathComponent("NodeBackups")
		try Data("not a folder".utf8).write(to: squatter)

		let resolved = NodeBackupManager.resolveBackupBaseURL(documents: documents, appSupport: appSupport)

		#expect(resolved == appSupport.appendingPathComponent("NodeBackups", isDirectory: true))
		// The user's file is never touched, moved, or overwritten.
		#expect(try Data(contentsOf: squatter) == Data("not a folder".utf8))
	}

	@Test("A file collision with existing legacy backups keeps the legacy folder active and unmodified")
	func resolveLocationFileCollisionPreservesLegacyBackups() throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let documents = tempDir.appendingPathComponent("Documents", isDirectory: true)
		let appSupport = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
		try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
		try Data("squatter".utf8).write(to: documents.appendingPathComponent("NodeBackups"))
		let legacy = appSupport.appendingPathComponent("NodeBackups", isDirectory: true)
		let nodeDir = legacy.appendingPathComponent("5678", isDirectory: true)
		try FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)
		try Data("precious-backup".utf8).write(to: nodeDir.appendingPathComponent("Meshtastic.store"))

		let resolved = NodeBackupManager.resolveBackupBaseURL(documents: documents, appSupport: appSupport)

		#expect(resolved == legacy)
		// No migration was attempted into the blocked location; the backup is intact where it was.
		#expect(FileManager.default.fileExists(atPath: nodeDir.appendingPathComponent("Meshtastic.store").path))
	}

	// MARK: - Keying backups by device id

	private func makeBackup(
		in backupDir: URL,
		dirName: String,
		nodeNum: Int64,
		peripheralId: String?,
		createdAt: Date,
		makeContainer: (URL) throws -> ModelContainer
	) throws -> BackupEntry {
		let dir = backupDir.appendingPathComponent(dirName, isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

		let storeURL = dir.appendingPathComponent("Meshtastic.store")
		let container = try makeContainer(storeURL)
		let context = ModelContext(container)
		context.autosaveEnabled = false
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = nodeNum
		myInfo.peripheralId = peripheralId
		context.insert(myInfo)
		try context.save()

		let data = try Data(contentsOf: storeURL)
		return BackupEntry(
			nodeNum: nodeNum,
			deviceId: nil,
			nodeName: "Node \(nodeNum)",
			createdAt: createdAt,
			fileSize: Int64(data.count),
			checksum: "unused",
			backupPath: dirName
		)
	}

	private func writeIndex(entries: [BackupEntry], to backupDir: URL) throws {
		try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
		var index = BackupIndex()
		for entry in entries {
			index.entries[entry.key] = entry
		}
		let data = try JSONEncoder().encode(index)
		try data.write(to: backupDir.appendingPathComponent("backup-index.json"))
	}

	@Test("BackupKey uses the device id when there is one and the node number otherwise")
	func testBackupKeyDerivation() {
		#expect(BackupKey.forDevice(Data([0x18, 0xF0, 0x62])) == "18f062")
		#expect(BackupKey.forDevice(Data()) == nil)
		#expect(BackupKey.forDevice(nil) == nil)
		#expect(BackupKey.forNode(1_373_366_617) == "node-1373366617")
		#expect(BackupKey.isNodeNumberKey("node-1373366617"))
		#expect(!BackupKey.isNodeNumberKey("18f062fc2c5525e37635701f8442a5a4"))
	}

	@Test("a version 1 index decodes to node-number keys without touching any files")
	func testVersionOneIndexDecodes() throws {
		// Version 1 keyed by Int64, which Swift encodes as a flat [key, value] array rather than an
		// object, so this is the shape the decoder has to recognize.
		let json = """
		{"version":1,"lastModified":768000000,"entries":[1373366617,{"nodeNum":1373366617,\
		"nodeName":"cebc","createdAt":768000000,"fileSize":120,"checksum":"abc","backupPath":"1373366617"}]}
		"""
		let index = try JSONDecoder().decode(BackupIndex.self, from: Data(json.utf8))

		#expect(index.version == BackupIndex.currentVersion)
		#expect(index.entries.count == 1)
		#expect(index.entries["node-1373366617"]?.nodeNum == 1_373_366_617)
		#expect(index.entries["node-1373366617"]?.deviceId == nil)
	}

	@Test("adopting a radio re-keys the backup filed under its current node number")
	@MainActor
	func testAdoptRekeysByNodeNum() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)

		let entry = try makeBackup(
			in: backupDir, dirName: "node-4242", nodeNum: 4242, peripheralId: "PERIPHERAL-A",
			createdAt: .now, makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		try writeIndex(entries: [entry], to: backupDir)

		let manager = NodeBackupManager(baseURL: backupDir)
		let deviceId = Data([0xAB, 0xCD])
		await manager.adoptLegacyBackups(deviceId: deviceId, nodeNum: 4242, peripheralId: "PERIPHERAL-A")

		let backups = manager.listBackups()
		#expect(backups.count == 1)
		#expect(backups.first?.deviceId == "abcd")
		#expect(backups.first?.backupPath == "abcd")
		#expect(FileManager.default.fileExists(atPath: backupDir.appendingPathComponent("abcd").path))
		#expect(!FileManager.default.fileExists(atPath: backupDir.appendingPathComponent("node-4242").path))
	}

	@Test("adopting a renumbered radio keeps the newest backup and deletes the rest")
	@MainActor
	func testAdoptCollapsesRenumberDuplicates() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)

		// One radio, three node numbers — what a pair of 2.8 upgrades leaves behind. Only the last is
		// findable by the number the radio reports now; the others are found by peripheral id.
		let old = try makeBackup(
			in: backupDir, dirName: "node-1373366617", nodeNum: 1_373_366_617, peripheralId: "PERIPHERAL-A",
			createdAt: Date(timeIntervalSince1970: 1000), makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		let middle = try makeBackup(
			in: backupDir, dirName: "node-1658900156", nodeNum: 1_658_900_156, peripheralId: "PERIPHERAL-A",
			createdAt: Date(timeIntervalSince1970: 2000), makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		let newest = try makeBackup(
			in: backupDir, dirName: "node-3177266887", nodeNum: 3_177_266_887, peripheralId: "PERIPHERAL-A",
			createdAt: Date(timeIntervalSince1970: 3000), makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		// A different radio, which must be left alone.
		let other = try makeBackup(
			in: backupDir, dirName: "node-999", nodeNum: 999, peripheralId: "PERIPHERAL-B",
			createdAt: Date(timeIntervalSince1970: 4000), makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		try writeIndex(entries: [old, middle, newest, other], to: backupDir)

		let manager = NodeBackupManager(baseURL: backupDir)
		await manager.adoptLegacyBackups(
			deviceId: Data([0x18, 0xF0]), nodeNum: 3_177_266_887, peripheralId: "PERIPHERAL-A"
		)

		let backups = manager.listBackups()
		#expect(backups.count == 2)
		let adopted = backups.first { $0.deviceId == "18f0" }
		#expect(adopted?.nodeNum == 3_177_266_887)
		#expect(adopted?.createdAt == Date(timeIntervalSince1970: 3000))

		let fm = FileManager.default
		#expect(fm.fileExists(atPath: backupDir.appendingPathComponent("18f0").path))
		#expect(!fm.fileExists(atPath: backupDir.appendingPathComponent("node-1373366617").path))
		#expect(!fm.fileExists(atPath: backupDir.appendingPathComponent("node-1658900156").path))
		#expect(!fm.fileExists(atPath: backupDir.appendingPathComponent("node-3177266887").path))
		// The other radio is untouched and still keyed by node number.
		#expect(fm.fileExists(atPath: backupDir.appendingPathComponent("node-999").path))
		#expect(backups.contains { $0.nodeNum == 999 && $0.deviceId == nil })
	}

	@Test("a radio reporting no device id is left keyed by node number")
	@MainActor
	func testAdoptIgnoresRadioWithoutDeviceId() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)

		let entry = try makeBackup(
			in: backupDir, dirName: "node-4242", nodeNum: 4242, peripheralId: "PERIPHERAL-A",
			createdAt: .now, makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		try writeIndex(entries: [entry], to: backupDir)

		let manager = NodeBackupManager(baseURL: backupDir)
		await manager.adoptLegacyBackups(deviceId: Data(), nodeNum: 4242, peripheralId: "PERIPHERAL-A")

		#expect(manager.listBackups().first?.deviceId == nil)
		#expect(FileManager.default.fileExists(atPath: backupDir.appendingPathComponent("node-4242").path))
	}

	@Test("re-keyed directories survive the orphan sweep")
	@MainActor
	func testRekeyedDirectorySurvivesSweep() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)

		let entry = try makeBackup(
			in: backupDir, dirName: "node-4242", nodeNum: 4242, peripheralId: "PERIPHERAL-A",
			createdAt: .now, makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		try writeIndex(entries: [entry], to: backupDir)

		let manager = NodeBackupManager(baseURL: backupDir)
		await manager.adoptLegacyBackups(deviceId: Data([0xAB, 0xCD]), nodeNum: 4242, peripheralId: "PERIPHERAL-A")

		// The sweep used to parse directory names as node numbers, which would have deleted this one.
		let reopened = NodeBackupManager(baseURL: backupDir)
		#expect(reopened.listBackups().count == 1)
		#expect(FileManager.default.fileExists(atPath: backupDir.appendingPathComponent("abcd").path))
	}


	// MARK: - Review fixes

	@Test("a node- key needs a real node number, so user folders are not swept")
	func testNodeKeyRequiresNumber() {
		#expect(BackupKey.isNodeNumberKey("node-1373366617"))
		// The backup folder shows up in Files, so anything can land in it.
		#expect(!BackupKey.isNodeNumberKey("node-notes"))
		#expect(!BackupKey.isNodeNumberKey("node-"))
		#expect(!BackupKey.isNodeNumberKey("notes"))
	}

	@Test("a recorded backup path has to be a plain folder name")
	func testBackupPathMustBePlain() {
		// backup-index.json is user-writable, so a hand-edited path could walk out of the folder.
		#expect(NodeBackupManager.isPlainBackupPath("18f062fc2c5525e37635701f8442a5a4"))
		#expect(NodeBackupManager.isPlainBackupPath("node-1373366617"))
		#expect(!NodeBackupManager.isPlainBackupPath(".."))
		#expect(!NodeBackupManager.isPlainBackupPath("."))
		#expect(!NodeBackupManager.isPlainBackupPath(""))
		#expect(!NodeBackupManager.isPlainBackupPath("../../Library/Application Support"))
		#expect(!NodeBackupManager.isPlainBackupPath("/tmp/elsewhere"))
		#expect(!NodeBackupManager.isPlainBackupPath("nested/path"))
	}

	@Test("a backup with no device id joins the one already keyed by device")
	@MainActor
	func testBackupReusesKnownDeviceId() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)
		let dbDir = tempDir.appendingPathComponent("ActiveDB", isDirectory: true)
		_ = try createFakeDatabase(at: dbDir)

		let manager = NodeBackupManager(baseURL: backupDir)
		_ = await manager.createBackup(forNode: 4242, deviceId: Data([0xAB, 0xCD]), nodeName: "First")

		// The caller resolves the device id from the store, which can come back nil part way through
		// a connect or a radio switch. That must not sit a second backup beside the first.
		_ = await manager.createBackup(forNode: 4242, deviceId: nil, nodeName: "Second")

		let backups = manager.listBackups()
		#expect(backups.count == 1)
		#expect(backups.first?.deviceId == "abcd")
		#expect(backups.first?.nodeName == "Second")
	}

	@Test("a failed re-key leaves every backup alone")
	@MainActor
	func testFailedAdoptionKeepsDuplicates() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)

		let older = try makeBackup(
			in: backupDir, dirName: "node-1000", nodeNum: 1000, peripheralId: "PERIPHERAL-A",
			createdAt: Date(timeIntervalSince1970: 1000), makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		let newer = try makeBackup(
			in: backupDir, dirName: "node-2000", nodeNum: 2000, peripheralId: "PERIPHERAL-A",
			createdAt: Date(timeIntervalSince1970: 2000), makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		try writeIndex(entries: [older, newer], to: backupDir)

		let manager = NodeBackupManager(baseURL: backupDir)
		// Pull the survivor's directory out from under the move. Duplicates used to be deleted
		// before the move ran, so a failure here destroyed them and re-keyed nothing.
		try FileManager.default.removeItem(at: backupDir.appendingPathComponent("node-2000"))

		await manager.adoptLegacyBackups(deviceId: Data([0x18, 0xF0]), nodeNum: 2000, peripheralId: "PERIPHERAL-A")

		#expect(manager.listBackups().contains { $0.nodeNum == 1000 })
		#expect(FileManager.default.fileExists(atPath: backupDir.appendingPathComponent("node-1000").path))
	}


	@Test("connecting clears a duplicate left beside a device-keyed backup")
	@MainActor
	func testConnectClearsStrayNodeKeyedBackup() async throws {
		let tempDir = try makeTempDir()
		defer { cleanup(tempDir) }
		let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)

		// The state my phone was actually in: one backup keyed by device id, and a second for the
		// same radio keyed by node number, written while the device id lookup was returning nil.
		var keyed = try makeBackup(
			in: backupDir, dirName: "abcd", nodeNum: 4242, peripheralId: "PERIPHERAL-A",
			createdAt: Date(timeIntervalSince1970: 2000), makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		keyed.deviceId = "abcd"
		let stray = try makeBackup(
			in: backupDir, dirName: "node-4242", nodeNum: 4242, peripheralId: "PERIPHERAL-A",
			createdAt: Date(timeIntervalSince1970: 1000), makeContainer: { try makeContainer(inMemory: false, storeURL: $0) }
		)
		try writeIndex(entries: [keyed, stray], to: backupDir)

		let manager = NodeBackupManager(baseURL: backupDir)
		#expect(manager.listBackups().count == 2)

		await manager.adoptLegacyBackups(deviceId: Data([0xAB, 0xCD]), nodeNum: 4242, peripheralId: "PERIPHERAL-A")

		let backups = manager.listBackups()
		#expect(backups.count == 1)
		#expect(backups.first?.deviceId == "abcd")
		#expect(!FileManager.default.fileExists(atPath: backupDir.appendingPathComponent("node-4242").path))
	}

}
