//
//  LegacyStoreRecoveryTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/3/26.
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Legacy store recovery")
@MainActor
struct LegacyStoreRecoveryTests {

	private let schema = Schema(versionedSchema: MeshtasticSchema.current)

	private func makeTempDir() throws -> URL {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("LegacyStoreRecoveryTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private func makeStore(at url: URL) throws -> ModelContainer {
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		return try ModelContainer(
			for: schema,
			migrationPlan: MeshtasticMigrationPlan.self,
			configurations: ModelConfiguration(url: url, allowsSave: true)
		)
	}

	private func freshDefaults() -> UserDefaults {
		UserDefaults(suiteName: "LegacyStoreRecoveryTests-\(UUID().uuidString)")!
	}

	@discardableResult
	private func insertNode(_ num: Int64, name: String, into context: ModelContext) -> UserEntity {
		let node = NodeInfoEntity()
		node.num = num
		context.insert(node)
		let user = UserEntity()
		user.num = num
		user.longName = name
		user.userNode = node
		context.insert(user)
		return user
	}

	private func insertMessage(_ messageId: Int64, payload: String, from user: UserEntity, into context: ModelContext) {
		let message = MessageEntity()
		message.messageId = messageId
		message.messagePayload = payload
		message.fromUser = user
		context.insert(message)
	}

	private func insertMyInfo(_ num: Int64, deviceId: Data? = nil, into context: ModelContext) {
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = num
		myInfo.deviceId = deviceId
		context.insert(myInfo)
	}

	/// The old store, written and closed before the recovery opens it.
	private func writeLegacyStore(at url: URL, radio: Int64) throws {
		let container = try makeStore(at: url)
		let context = ModelContext(container)
		insertMyInfo(radio, deviceId: Data([0xAB, 0xCD]), into: context)
		_ = insertNode(radio, name: "Old Name", into: context)
		let other = insertNode(200, name: "Only Old", into: context)
		insertMessage(1, payload: "old only", from: other, into: context)
		insertMessage(2, payload: "old copy", from: other, into: context)
		try context.save()
	}

	@Test("the old store merges into the live one for the same radio")
	func testMergeSameRadio() throws {
		let dir = try makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let legacyURL = dir.appendingPathComponent("AppSupport/Meshtastic.store")
		let liveURL = dir.appendingPathComponent("Group/Meshtastic.store")
		try writeLegacyStore(at: legacyURL, radio: 100)

		let live = try makeStore(at: liveURL)
		let liveContext = live.mainContext
		insertMyInfo(100, into: liveContext)
		let liveUser = insertNode(100, name: "New Name", into: liveContext)
		insertMessage(2, payload: "live copy", from: liveUser, into: liveContext)
		insertMessage(3, payload: "live only", from: liveUser, into: liveContext)
		try liveContext.save()

		let defaults = freshDefaults()
		let outcome = LegacyStoreRecovery.recoverIfNeeded(
			into: live,
			liveStoreURL: liveURL,
			legacyStoreURL: legacyURL,
			backups: NodeBackupManager(baseURL: dir.appendingPathComponent("Backups")),
			defaults: defaults
		)
		#expect(outcome == .merged)

		let check = ModelContext(live)
		let messages = try check.fetch(FetchDescriptor<MessageEntity>())
		#expect(Set(messages.map(\.messageId)) == [1, 2, 3])
		// The live copy wins where both have the row.
		#expect(messages.first { $0.messageId == 2 }?.messagePayload == "live copy")
		#expect(messages.first { $0.messageId == 1 }?.fromUser?.num == 200)

		let users = try check.fetch(FetchDescriptor<UserEntity>())
		#expect(users.filter { $0.num == 100 }.map(\.longName) == ["New Name"])
		#expect(users.contains { $0.num == 200 })
		#expect(try check.fetch(FetchDescriptor<MyInfoEntity>()).count == 1)

		// Renamed, not deleted, and not run a second time.
		#expect(!FileManager.default.fileExists(atPath: legacyURL.path))
		#expect(FileManager.default.fileExists(atPath: legacyURL.path + LegacyStoreRecovery.recoveredSuffix))
		#expect(LegacyStoreRecovery.recoverIfNeeded(into: live, liveStoreURL: liveURL, legacyStoreURL: legacyURL, defaults: defaults) == .nothingToDo)
	}

	@Test("for another radio the old store becomes its backup, and copies under other radios go")
	func testDifferentRadioFilesBackup() async throws {
		let dir = try makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let legacyURL = dir.appendingPathComponent("AppSupport/Meshtastic.store")
		let liveURL = dir.appendingPathComponent("Group/Meshtastic.store")
		try writeLegacyStore(at: legacyURL, radio: 100)

		let live = try makeStore(at: liveURL)
		insertMyInfo(300, into: live.mainContext)
		try live.mainContext.save()

		// One backup made from the frozen store under another radio, one made long before.
		let backupDir = dir.appendingPathComponent("Backups", isDirectory: true)
		var index = BackupIndex()
		for (num, created) in [(Int64(300), Date().addingTimeInterval(3600)), (Int64(400), Date.distantPast)] {
			let path = BackupKey.forNode(num)
			let folder = backupDir.appendingPathComponent(path, isDirectory: true)
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			try Data("x".utf8).write(to: folder.appendingPathComponent("Meshtastic.store"))
			let entry = BackupEntry(nodeNum: num, deviceId: nil, nodeName: nil, createdAt: created, fileSize: 1, checksum: "unused", backupPath: path)
			index.entries[entry.key] = entry
		}
		try JSONEncoder().encode(index).write(to: backupDir.appendingPathComponent("backup-index.json"))
		let backups = NodeBackupManager(baseURL: backupDir)

		let outcome = LegacyStoreRecovery.recoverIfNeeded(
			into: live,
			liveStoreURL: liveURL,
			legacyStoreURL: legacyURL,
			backups: backups,
			defaults: freshDefaults()
		)
		#expect(outcome == .filedAsBackup(nodeNum: 100))

		// The backup is copied in a task, and the copies are removed only after it lands.
		for _ in 0..<100 where !backups.hasBackup(forNode: 100) || backups.hasBackup(forNode: 300) {
			try await Task.sleep(for: .milliseconds(20))
		}
		#expect(backups.hasBackup(forNode: 100))
		#expect(!backups.hasBackup(forNode: 300))
		#expect(backups.hasBackup(forNode: 400))
		#expect(try ModelContext(live).fetch(FetchDescriptor<MessageEntity>()).isEmpty)
	}

	@Test("a failed attempt is retried on later launches, a limited number of times")
	func testFailureRetries() throws {
		let dir = try makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let legacyURL = dir.appendingPathComponent("AppSupport/Meshtastic.store")
		try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data("not a store".utf8).write(to: legacyURL)
		let liveURL = dir.appendingPathComponent("Group/Meshtastic.store")
		let live = try makeStore(at: liveURL)

		let defaults = freshDefaults()
		func attempt() -> LegacyStoreRecovery.Outcome {
			LegacyStoreRecovery.recoverIfNeeded(into: live, liveStoreURL: liveURL, legacyStoreURL: legacyURL, defaults: defaults)
		}
		for _ in 0..<LegacyStoreRecovery.maxAttempts {
			#expect(attempt() == .failed)
		}
		#expect(attempt() == .nothingToDo)
		#expect(FileManager.default.fileExists(atPath: legacyURL.path))
	}

	@Test("nothing happens when the store never moved")
	func testSameLocationDoesNothing() throws {
		let dir = try makeTempDir()
		defer { try? FileManager.default.removeItem(at: dir) }
		let url = dir.appendingPathComponent("Meshtastic.store")
		let live = try makeStore(at: url)
		#expect(LegacyStoreRecovery.recoverIfNeeded(into: live, liveStoreURL: url, legacyStoreURL: url, defaults: freshDefaults()) == .nothingToDo)
	}
}
