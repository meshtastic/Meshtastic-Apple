//
//  CoreDataMigrationServiceTests.swift
//  MeshtasticTests
//
//  Regression tests for #2152: the Core Data → SwiftData migration silently never ran in
//  2.7.13–2.7.16 because Meshtastic.momd was dropped from the app target's Resources build
//  phase by a hand-resolved project.pbxproj conflict (#1898). These tests guard the bundled
//  model itself and exercise the full migration — including the "rescue" merge into a store
//  the user has already been writing to since the failed upgrade.
//

import XCTest
import CoreData
import SwiftData
@testable import Meshtastic

final class CoreDataMigrationServiceTests: XCTestCase {

	// Mirrors of the service's private store URLs.
	private var applicationSupportURL: URL {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
	}
	private var legacyStoreURL: URL {
		applicationSupportURL.appendingPathComponent("Meshtastic-coredata-legacy.sqlite")
	}
	private var backupStoreURL: URL {
		applicationSupportURL.appendingPathComponent("Meshtastic-coredata-backup.sqlite")
	}

	override func setUpWithError() throws {
		try super.setUpWithError()
		removeLegacyAndBackupStores()
	}

	override func tearDownWithError() throws {
		removeLegacyAndBackupStores()
		try super.tearDownWithError()
	}

	private func removeLegacyAndBackupStores() {
		let fm = FileManager.default
		for base in [legacyStoreURL, backupStoreURL] {
			for suffix in ["", "-shm", "-wal"] {
				let url = base.deletingPathExtension().appendingPathExtension("sqlite\(suffix)")
				try? fm.removeItem(at: url)
			}
		}
	}

	// MARK: - Bundle regression guard

	/// The direct #2152 regression: the compiled legacy model must ship in the app bundle,
	/// including the exact versioned model the migration loads by name. If this fails, the
	/// one-time migration throws `modelNotFound` on every launch and upgraders from ≤2.7.12
	/// see an empty database.
	func testLegacyCoreDataModelIsInAppBundle() throws {
		let momdURL = Bundle.main.url(forResource: "Meshtastic", withExtension: "momd")
		XCTAssertNotNil(
			momdURL,
			"Meshtastic.momd is missing from the app bundle — Meshtastic.xcdatamodeld must stay in the app target's Resources build phase (#2152)"
		)
		guard let momdURL else { return }

		let v58URL = momdURL.appendingPathComponent("MeshtasticDataModelV 58.mom")
		XCTAssertTrue(
			FileManager.default.fileExists(atPath: v58URL.path),
			"MeshtasticDataModelV 58.mom (the version CoreDataMigrationService loads) is missing from Meshtastic.momd"
		)
		XCTAssertNotNil(NSManagedObjectModel(contentsOf: v58URL), "The bundled V58 model failed to load")
	}

	// MARK: - End-to-end migration

	/// Full migration into a POPULATED SwiftData store — the #2152 rescue scenario. Users on
	/// 2.7.13–2.7.16 upgraded, the migration threw, and they kept using the app; their legacy
	/// store still sits on disk. When the migration finally runs it must fill the gaps
	/// (old nodes, users, messages, configs) without duplicating rows the mesh has since
	/// re-taught the app, and without replacing their fresher configs/channels. A fresh
	/// install is the degenerate case (nothing preexisting), so this covers both paths:
	/// node 111 exists only in the legacy store, node 222 exists in both.
	@MainActor
	func testMigrationFillsGapsWithoutDuplicatingLiveData() throws {
		try buildLegacyStore()
		XCTAssertTrue(CoreDataMigrationService.legacyStoreExists())

		// Destination store, as the rescued user's app would have it: node 222 re-taught by
		// the mesh (with a fresher bleName and a live device config), message 1002 re-received.
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("MigrationTest", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		let container = try ModelContainer(for: schema, configurations: config)
		let context = container.mainContext

		let liveNode = NodeInfoEntity()
		liveNode.num = 222
		liveNode.bleName = "live-222"
		context.insert(liveNode)
		let liveUser = UserEntity()
		liveUser.num = 222
		liveUser.longName = "Live User 222"
		liveUser.userNode = liveNode
		context.insert(liveUser)
		let liveConfig = DeviceConfigEntity()
		liveConfig.role = 1
		context.insert(liveConfig)
		liveNode.deviceConfig = liveConfig
		let liveMessage = MessageEntity()
		liveMessage.messageId = 1002
		liveMessage.messagePayload = "live copy"
		context.insert(liveMessage)
		try context.save()

		try CoreDataMigrationService.migrate(into: container)

		// Node 111 migrated with its user and config; node 222 kept, not duplicated.
		let nodes = try context.fetch(FetchDescriptor<NodeInfoEntity>())
		XCTAssertEqual(nodes.count, 2, "expected legacy node 111 + live node 222, no duplicates")
		let node111 = try XCTUnwrap(nodes.first(where: { $0.num == 111 }))
		XCTAssertEqual(node111.bleName, "legacy-111")
		XCTAssertEqual(node111.user?.longName, "Legacy User 111")
		XCTAssertEqual(node111.deviceConfig?.role, 5, "legacy config should migrate for a legacy-only node")
		let node222 = try XCTUnwrap(nodes.first(where: { $0.num == 222 }))
		XCTAssertEqual(node222.bleName, "live-222", "live node must not be overwritten by the legacy row")
		XCTAssertEqual(node222.user?.longName, "Live User 222", "live node must keep its fresher user")
		XCTAssertEqual(node222.deviceConfig?.role, 1, "live node must keep its fresher config")

		// Users deduped by num.
		let users = try context.fetch(FetchDescriptor<UserEntity>())
		XCTAssertEqual(users.filter { $0.num == 222 }.count, 1, "user 222 must not be duplicated")

		// Message 1001 fills the gap; 1002 is not duplicated and keeps the live payload.
		let messages = try context.fetch(FetchDescriptor<MessageEntity>())
		XCTAssertEqual(messages.count, 2)
		XCTAssertEqual(messages.first(where: { $0.messageId == 1001 })?.messagePayload, "legacy hello")
		let dupes = messages.filter { $0.messageId == 1002 }
		XCTAssertEqual(dupes.count, 1)
		XCTAssertEqual(dupes.first?.messagePayload, "live copy")

		// MyInfo + its channel migrate (they only existed in the legacy store).
		let infos = try context.fetch(FetchDescriptor<MyInfoEntity>())
		XCTAssertEqual(infos.count, 1)
		XCTAssertEqual(infos.first?.myNodeNum, 111)
		let channels = try context.fetch(FetchDescriptor<ChannelEntity>())
		XCTAssertEqual(channels.count, 1)
		XCTAssertEqual(channels.first?.name, "LegacyChan")

		// The legacy store is retired so the migration never runs again.
		XCTAssertFalse(CoreDataMigrationService.legacyStoreExists(), "legacy store should be renamed after a successful migration")
		XCTAssertTrue(FileManager.default.fileExists(atPath: backupStoreURL.path), "renamed backup store should exist")
	}

	// MARK: - Legacy store construction

	/// Builds a real V58 Core Data store at the service's legacy URL using the bundled model,
	/// exactly as a 2.7.12 install would have left it (after `prepareForMigration()` renamed it).
	private func buildLegacyStore() throws {
		let momdURL = try XCTUnwrap(Bundle.main.url(forResource: "Meshtastic", withExtension: "momd"))
		let modelURL = momdURL.appendingPathComponent("MeshtasticDataModelV 58.mom")
		let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))

		let container = NSPersistentContainer(name: "Meshtastic", managedObjectModel: model)
		let description = NSPersistentStoreDescription(url: legacyStoreURL)
		description.shouldAddStoreAsynchronously = false
		container.persistentStoreDescriptions = [description]
		var loadError: Error?
		container.loadPersistentStores { _, error in loadError = error }
		if let loadError { throw loadError }

		let ctx = container.viewContext

		func insert(_ entity: String, _ values: [String: Any]) -> NSManagedObject {
			let obj = NSEntityDescription.insertNewObject(forEntityName: entity, into: ctx)
			for (key, value) in values { obj.setValue(value, forKey: key) }
			return obj
		}

		let node111 = insert("NodeInfoEntity", ["num": Int64(111), "bleName": "legacy-111", "lastHeard": Date()])
		let node222 = insert("NodeInfoEntity", ["num": Int64(222), "bleName": "legacy-222", "lastHeard": Date()])

		let user111 = insert("UserEntity", [
			"num": Int64(111), "longName": "Legacy User 111", "shortName": "L111",
			"hwModel": "TBEAM", "userId": "!0000006f"
		])
		user111.setValue(node111, forKey: "userNode")
		let user222 = insert("UserEntity", [
			"num": Int64(222), "longName": "Legacy User 222", "shortName": "L222",
			"hwModel": "TBEAM", "userId": "!000000de"
		])
		user222.setValue(node222, forKey: "userNode")

		let myInfo = insert("MyInfoEntity", ["myNodeNum": Int64(111)])
		myInfo.setValue(node111, forKey: "myInfoNode")

		let channel = insert("ChannelEntity", ["index": Int32(0), "name": "LegacyChan", "role": Int32(1)])
		channel.setValue(myInfo, forKey: "myInfoChannel")

		let message1001 = insert("MessageEntity", [
			"messageId": Int64(1001), "messagePayload": "legacy hello",
			"messageTimestamp": Int32(Date().timeIntervalSince1970), "receivedACK": false
		])
		message1001.setValue(user111, forKey: "fromUser")
		let message1002 = insert("MessageEntity", [
			"messageId": Int64(1002), "messagePayload": "legacy copy of 1002",
			"messageTimestamp": Int32(Date().timeIntervalSince1970), "receivedACK": false
		])
		message1002.setValue(user222, forKey: "fromUser")

		// Configs: one on the legacy-only node (should migrate) and one on the node the
		// live store also has (must be skipped in favor of the live config).
		let config111 = insert("DeviceConfigEntity", ["role": Int32(5)])
		config111.setValue(node111, forKey: "deviceConfigNode")
		let config222 = insert("DeviceConfigEntity", ["role": Int32(9)])
		config222.setValue(node222, forKey: "deviceConfigNode")

		try ctx.save()

		// Detach so the migration's own container gets exclusive access.
		for store in container.persistentStoreCoordinator.persistentStores {
			try container.persistentStoreCoordinator.remove(store)
		}
	}
}
