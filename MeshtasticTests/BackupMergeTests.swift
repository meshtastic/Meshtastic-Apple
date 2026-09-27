//
//  BackupMergeTests.swift
//  MeshtasticTests
//
//  Feature 021 (T030, D-09): merging one radio's backup into the shared store.
//

import Foundation
import CryptoKit
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Backup merge into the shared store")
struct BackupMergeTests {

	private let radioA: Int64 = 0x0A0A_0A0A
	private let radioB: Int64 = 0x0B0B_0B0B
	private let shared: Int64 = 0x5555_5555
	private let onlyInBackup: Int64 = 0x6666_6666

	private func makeContext() throws -> ModelContext {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("BackupMergeTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		let context = ModelContext(try ModelContainer(for: schema, configurations: config))
		context.autosaveEnabled = false
		return context
	}

	@discardableResult
	private func makeNode(_ num: Int64, name: String, lastHeard: Date, in context: ModelContext) -> UserEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		node.lastHeard = lastHeard
		node.firstHeard = lastHeard
		context.insert(node)
		let user = UserEntity()
		user.num = num
		user.longName = name
		user.shortName = String(name.prefix(4))
		user.userNode = node
		context.insert(user)
		return user
	}

	/// A radio on LongFast with a default primary channel.
	private func makeRadio(_ num: Int64, in context: ModelContext) {
		var descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		descriptor.fetchLimit = 1
		let node = (try? context.fetch(descriptor).first) ?? NodeInfoEntity()
		let lora = LoRaConfigEntity()
		lora.usePreset = true
		lora.modemPreset = Int32(Config.LoRaConfig.ModemPreset.longFast.rawValue)
		context.insert(lora)
		node.loRaConfig = lora
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = num
		myInfo.myInfoNode = node
		context.insert(myInfo)
		let primary = ChannelEntity()
		primary.index = 0
		primary.psk = Data([1])
		primary.role = Int32(Channel.Role.primary.rawValue)
		primary.myInfoChannel = myInfo
		context.insert(primary)
	}

	private func message(_ id: Int64, from: UserEntity, to: UserEntity?, at time: Int32, in context: ModelContext) -> MessageEntity {
		let row = MessageEntity()
		row.messageId = id
		row.messageTimestamp = time
		row.fromUser = from
		row.toUser = to
		row.messagePayload = "Message \(id)"
		row.read = true
		context.insert(row)
		return row
	}

	/// The shared store: radio A, a node both radios know, and one channel message heard by A.
	private func makeLive() throws -> ModelContext {
		let live = try makeContext()
		try populateLive(live)
		return live
	}

	private func populateLive(_ live: ModelContext) throws {
		makeNode(radioA, name: "Radio A", lastHeard: Date(timeIntervalSince1970: 2_000_000), in: live)
		let peer = makeNode(shared, name: "Shared peer", lastHeard: Date(timeIntervalSince1970: 2_000_000), in: live)
		makeRadio(radioA, in: live)
		_ = message(1, from: peer, to: nil, at: 1_500_000, in: live)
		try live.save()
		try drainBackfill(live, ownRadio: radioA)
	}

	/// Radio B's backup as an older build wrote it: no multi-radio columns yet.
	private func makeBackup() throws -> ModelContext {
		let backup = try makeContext()
		try populateBackup(backup)
		return backup
	}

	private func populateBackup(_ backup: ModelContext) throws {
		let radio = makeNode(radioB, name: "Radio B", lastHeard: Date(timeIntervalSince1970: 1_000_000), in: backup)
		let peer = makeNode(shared, name: "Shared peer (old name)", lastHeard: Date(timeIntervalSince1970: 900_000), in: backup)
		let stranger = makeNode(onlyInBackup, name: "Only in backup", lastHeard: Date(timeIntervalSince1970: 1_000_000), in: backup)
		stranger.publicKey = Data(repeating: 9, count: 32)
		makeRadio(radioB, in: backup)
		// The same broadcast A heard, a DM to B, and B's reply.
		_ = message(1, from: peer, to: nil, at: 1_500_000, in: backup)
		_ = message(2, from: stranger, to: radio, at: 1_600_000, in: backup)
		_ = message(3, from: radio, to: stranger, at: 1_600_100, in: backup)
		let position = PositionEntity()
		position.latitudeI = 450_000_000
		position.longitudeI = -730_000_000
		position.time = Date(timeIntervalSince1970: 1_000_000)
		position.latest = true
		position.nodePosition = stranger.userNode
		backup.insert(position)
		let telemetry = TelemetryEntity()
		telemetry.metricsType = 0
		telemetry.batteryLevel = 77
		telemetry.time = Date(timeIntervalSince1970: 1_000_000)
		telemetry.nodeTelemetry = stranger.userNode
		backup.insert(telemetry)
		try backup.save()
	}

	private func drainBackfill(_ context: ModelContext, ownRadio: Int64) throws {
		var chunks = 0
		while try MultiRadioBackfill.runChunk(in: context, ownRadio: ownRadio).total > 0 {
			chunks += 1
			guard chunks < 100 else { Issue.record("Backfill did not finish"); break }
		}
	}

	@Test("A backup adds its radio, its missing nodes and its own messages; shared rows stay once")
	func mergesMissingRows() throws {
		let live = try makeLive()
		let backup = try makeBackup()

		let result = try BackupMerge.merge(from: backup, radioNum: radioB, into: live)

		#expect(result.radios == 1)
		#expect(result.nodes == 2) // radio B and the node only B knew
		#expect(result.messages == 2) // the DM and the reply; the broadcast was already there
		#expect(result.positions == 1)
		#expect(result.telemetry == 1)

		let messages = try live.fetch(FetchDescriptor<MessageEntity>())
		#expect(messages.count == 3)
		let dm = try #require(messages.first { $0.messageId == 2 })
		#expect(dm.localNodeNum == radioB)
		#expect(dm.toUser?.num == radioB)
		#expect(dm.fromUser?.longName == "Only in backup")
		#expect(dm.messageKey == MessageEntity.key(fromNum: onlyInBackup, messageId: 2))

		// Radio B is now a known radio, with its channel keyed like A's.
		let radios = Set(try live.fetch(FetchDescriptor<MyInfoEntity>()).map(\.myNodeNum))
		#expect(radios == [radioA, radioB])
		let channelKeys = try live.fetch(FetchDescriptor<ChannelEntity>()).compactMap(\.channelKey)
		#expect(channelKeys.count == 2)
		#expect(Set(channelKeys).count == 1)

		// Each radio observes the node both know.
		let observers = try live.fetch(FetchDescriptor<NodeObservationEntity>()).filter { $0.nodeNum == shared }.map(\.radioNum)
		#expect(Set(observers) == [radioA, radioB])
	}

	@Test("What the shared store has wins; times widen and gaps fill")
	func liveWins() throws {
		let live = try makeLive()
		let backup = try makeBackup()

		try BackupMerge.merge(from: backup, radioNum: radioB, into: live)

		let peerNum = shared
		let peer = try #require(try live.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == peerNum })).first)
		#expect(peer.longName == "Shared peer")
		#expect(peer.userNode?.lastHeard == Date(timeIntervalSince1970: 2_000_000))
		#expect(peer.userNode?.firstHeard == Date(timeIntervalSince1970: 900_000))
		let strangerNum = onlyInBackup
		let stranger = try #require(try live.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == strangerNum })).first)
		#expect(stranger.publicKey == Data(repeating: 9, count: 32))
		#expect(stranger.userNode?.latestPositionCache?.latitudeI == 450_000_000)
	}

	@Test("Merging twice adds nothing the second time")
	func idempotent() throws {
		let live = try makeLive()
		try BackupMerge.merge(from: try makeBackup(), radioNum: radioB, into: live)

		let again = try BackupMerge.merge(from: try makeBackup(), radioNum: radioB, into: live)

		#expect(again.total == 0)
		#expect(try live.fetchCount(FetchDescriptor<MessageEntity>()) == 3)
		#expect(try live.fetchCount(FetchDescriptor<PositionEntity>()) == 1)
	}
}

// MARK: - Through the backup manager and the ingest actor

extension BackupMergeTests {

	/// A backup folder the way `createBackup` writes one, holding radio B's store.
	private struct BackupFolder {
		let base: URL
		let entry: BackupEntry
	}

	private func makeBackupFolder(radioNum: Int64, populate: (ModelContext) throws -> Void) throws -> BackupFolder {
		let base = FileManager.default.temporaryDirectory.appendingPathComponent("BackupMergeTests-\(UUID().uuidString)", isDirectory: true)
		let dirName = BackupKey.forNode(radioNum)
		let dir = base.appendingPathComponent(dirName, isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		let storeURL = dir.appendingPathComponent("Meshtastic.store")
		try {
			let schema = Schema(versionedSchema: MeshtasticSchema.current)
			let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: storeURL, allowsSave: true))
			let context = ModelContext(container)
			context.autosaveEnabled = false
			try populate(context)
		}()
		let checksum = SHA256.hash(data: try Data(contentsOf: storeURL)).map { String(format: "%02x", $0) }.joined()
		let entry = BackupEntry(nodeNum: radioNum, deviceId: nil, nodeName: "Radio", createdAt: .now, fileSize: 0, checksum: checksum, backupPath: dirName)
		var index = BackupIndex()
		index.entries[entry.key] = entry
		try JSONEncoder().encode(index).write(to: base.appendingPathComponent("backup-index.json"))
		return BackupFolder(base: base, entry: entry)
	}

	private func makeLiveContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("BackupMergeTests-live-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		let container = try ModelContainer(for: schema, configurations: config)
		let context = ModelContext(container)
		context.autosaveEnabled = false
		try populateLive(context)
		return container
	}

	@Test("A pending backup is merged once, and recorded in the index")
	@MainActor
	func managerMergesOnce() async throws {
		let folder = try makeBackupFolder(radioNum: radioB) { try populateBackup($0) }
		defer { try? FileManager.default.removeItem(at: folder.base) }
		let liveContainer = try makeLiveContainer()
		let packets = MeshPackets(modelContainer: liveContainer)
		let manager = NodeBackupManager(baseURL: folder.base)
		#expect(manager.unmergedBackups.count == 1)

		let merged = await manager.mergePendingBackups(using: packets, ownRadio: radioA)

		#expect(merged == 1)
		#expect(manager.unmergedBackups.isEmpty)
		let context = ModelContext(liveContainer)
		#expect(try context.fetchCount(FetchDescriptor<MessageEntity>()) == 3)
		#expect(Set(try context.fetch(FetchDescriptor<MyInfoEntity>()).map(\.myNodeNum)) == [radioA, radioB])
		// The backup file is untouched and still listed.
		#expect(manager.listBackups().count == 1)
		// Survives a relaunch: a new manager reads the recorded merge from the index.
		#expect(NodeBackupManager(baseURL: folder.base).unmergedBackups.isEmpty)
		#expect(await manager.mergePendingBackups(using: packets, ownRadio: radioA) == 0)
	}

	@Test("A backup of a radio the store already holds is not merged, only marked")
	@MainActor
	func managerSkipsKnownRadio() async throws {
		// A's own backup, holding a message the store deleted since.
		let folder = try makeBackupFolder(radioNum: radioA) { context in
			let radio = makeNode(radioA, name: "Radio A", lastHeard: Date(timeIntervalSince1970: 1_000_000), in: context)
			makeRadio(radioA, in: context)
			_ = message(99, from: radio, to: nil, at: 1_000_000, in: context)
			try context.save()
		}
		defer { try? FileManager.default.removeItem(at: folder.base) }
		let liveContainer = try makeLiveContainer()
		let manager = NodeBackupManager(baseURL: folder.base)

		let merged = await manager.mergePendingBackups(using: MeshPackets(modelContainer: liveContainer), ownRadio: radioA)

		#expect(merged == 0)
		#expect(manager.unmergedBackups.isEmpty)
		#expect(try ModelContext(liveContainer).fetchCount(FetchDescriptor<MessageEntity>()) == 1)
	}

	@Test("A stray radio row from an old store doesn't stop that radio's backup from merging")
	@MainActor
	func strayRadioRowDoesNotBlockMerge() async throws {
		let folder = try makeBackupFolder(radioNum: radioB) { try populateBackup($0) }
		defer { try? FileManager.default.removeItem(at: folder.base) }
		let liveContainer = try makeLiveContainer()
		let live = ModelContext(liveContainer)
		let stray = MyInfoEntity()
		stray.myNodeNum = radioB
		live.insert(stray)
		try live.save()
		let manager = NodeBackupManager(baseURL: folder.base)

		let merged = await manager.mergePendingBackups(using: MeshPackets(modelContainer: liveContainer), ownRadio: radioA)

		#expect(merged == 1)
		#expect(try ModelContext(liveContainer).fetchCount(FetchDescriptor<MessageEntity>()) == 3)
	}

	@Test("A backup this build takes is a copy of the shared store, so it isn't pending")
	@MainActor
	func newBackupIsNotPending() async throws {
		let base = FileManager.default.temporaryDirectory.appendingPathComponent("BackupMergeTests-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: base) }
		let activeDir = base.appendingPathComponent("Active", isDirectory: true)
		try FileManager.default.createDirectory(at: activeDir, withIntermediateDirectories: true)
		let activeStore = activeDir.appendingPathComponent("Meshtastic.store")
		try Data("store".utf8).write(to: activeStore)
		let manager = NodeBackupManager(baseURL: base.appendingPathComponent("Backups", isDirectory: true), activeStoreURL: activeStore)

		_ = await manager.createBackup(forNode: radioA, deviceId: nil, nodeName: "Radio A")

		#expect(manager.listBackups().count == 1)
		#expect(manager.unmergedBackups.isEmpty)
	}

	@Test("A backup whose checksum doesn't match is left alone and stays pending")
	@MainActor
	func managerSkipsBadChecksum() async throws {
		let folder = try makeBackupFolder(radioNum: radioB) { try populateBackup($0) }
		defer { try? FileManager.default.removeItem(at: folder.base) }
		var index = BackupIndex()
		var entry = folder.entry
		entry.checksum = String(repeating: "0", count: 64)
		index.entries[entry.key] = entry
		try JSONEncoder().encode(index).write(to: folder.base.appendingPathComponent("backup-index.json"))
		let liveContainer = try makeLiveContainer()
		let manager = NodeBackupManager(baseURL: folder.base)

		let merged = await manager.mergePendingBackups(using: MeshPackets(modelContainer: liveContainer), ownRadio: radioA)

		#expect(merged == 0)
		#expect(manager.unmergedBackups.count == 1)
		#expect(manager.listBackups().count == 1) // not deleted, unlike a failed restore
		#expect(try ModelContext(liveContainer).fetchCount(FetchDescriptor<MessageEntity>()) == 1)
	}

	@Test("A merged backup is marked, with its one attempt counted")
	@MainActor
	func attemptCountedPerBackup() async throws {
		let folder = try makeBackupFolder(radioNum: radioB) { try populateBackup($0) }
		defer { try? FileManager.default.removeItem(at: folder.base) }
		let liveContainer = try makeLiveContainer()
		let manager = NodeBackupManager(baseURL: folder.base)

		#expect(await manager.mergePendingBackups(using: MeshPackets(modelContainer: liveContainer), ownRadio: radioA) == 1)

		let entry = try #require(NodeBackupManager(baseURL: folder.base).listBackups().first)
		#expect(entry.mergeAttempts == 1)
		#expect(entry.isMerged)
	}

	@Test("A backup that never merges is tried on a few launches, then left for a restore")
	@MainActor
	func managerGivesUpAfterAttempts() async throws {
		let folder = try makeBackupFolder(radioNum: radioB) { try populateBackup($0) }
		defer { try? FileManager.default.removeItem(at: folder.base) }
		var index = BackupIndex()
		var entry = folder.entry
		entry.checksum = String(repeating: "0", count: 64)
		index.entries[entry.key] = entry
		try JSONEncoder().encode(index).write(to: folder.base.appendingPathComponent("backup-index.json"))
		let liveContainer = try makeLiveContainer()

		for launch in 1...NodeBackupManager.maxMergeAttempts {
			// A new manager each time, as a relaunch reads the index from disk.
			let manager = NodeBackupManager(baseURL: folder.base)
			_ = await manager.mergePendingBackups(using: MeshPackets(modelContainer: liveContainer), ownRadio: radioA)
			#expect(NodeBackupManager(baseURL: folder.base).unmergedBackups.first?.mergeAttempts == launch)
		}
		let manager = NodeBackupManager(baseURL: folder.base)
		_ = await manager.mergePendingBackups(using: MeshPackets(modelContainer: liveContainer), ownRadio: radioA)
		#expect(manager.unmergedBackups.first?.mergeAttempts == NodeBackupManager.maxMergeAttempts, "not tried again")
		#expect(manager.listBackups().count == 1, "the backup stays")
	}
}
