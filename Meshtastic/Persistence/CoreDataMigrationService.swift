//
//  CoreDataMigrationService.swift
//  Meshtastic
//
//  One-time migration from the legacy Core Data store (shipped in 2.7.12 and
//  earlier) into the SwiftData store.
//
//  PersistenceBootstrap prepares the store paths, creates the SwiftData container,
//  and runs this migration before publishing normal app content. After a successful
//  run the old store is renamed to `Meshtastic-coredata-backup.sqlite` so the
//  migration never runs again.
//
//  Entities migrated (every entity that existed in the Core Data model):
//    NodeInfoEntity, UserEntity, MyInfoEntity, ChannelEntity, MessageEntity,
//    PositionEntity, TelemetryEntity, BluetoothConfigEntity,
//    CannedMessageConfigEntity, DeviceConfigEntity, DisplayConfigEntity,
//    ExternalNotificationConfigEntity, LoRaConfigEntity, MQTTConfigEntity,
//    NetworkConfigEntity, PositionConfigEntity, RangeTestConfigEntity,
//    SerialConfigEntity, TelemetryConfigEntity
//

import CoreData
import SwiftData
import OSLog

// MARK: - Public API

enum CoreDataMigrationService {

	struct StoreLocations: Sendable {
		let applicationSupportURL: URL

		var candidateStoreURL: URL {
			applicationSupportURL.appendingPathComponent("Meshtastic.sqlite")
		}

		var legacyStoreURL: URL {
			applicationSupportURL.appendingPathComponent("Meshtastic-coredata-legacy.sqlite")
		}

		var backupStoreURL: URL {
			applicationSupportURL.appendingPathComponent("Meshtastic-coredata-backup.sqlite")
		}

		var destinationStoreURL: URL {
			applicationSupportURL.appendingPathComponent("Meshtastic.store")
		}

		var retirementMarkerURL: URL {
			applicationSupportURL.appendingPathComponent("Meshtastic-coredata-retirement-in-progress")
		}

		static var applicationSupport: StoreLocations {
			StoreLocations(
				applicationSupportURL: FileManager.default.urls(
					for: .applicationSupportDirectory,
					in: .userDomainMask
				)[0]
			)
		}
	}

	enum StoreMember: Sendable, Equatable {
		case wal
		case shm
		case main
	}

	enum HistoryKind: Sendable, Equatable {
		case messages
		case positions
		case telemetry
	}

	enum MigrationCheckpoint: Sendable, Equatable {
		case afterPrepareMove(StoreMember)
		case afterParentSave
		case afterHistoryBatch(HistoryKind, index: Int)
		case afterMessageScalarPersistence
		case afterMessageUserLink(nodeNum: Int64)
		case beforeRetirement
		case afterRetirementMove(StoreMember)
	}

	struct MigrationOptions: Sendable {
		var batchSize = 500
		var checkpoint: @Sendable (MigrationCheckpoint) throws -> Void = { _ in }
	}

	final class MergeState {
		var preexistingNodeNums = Set<Int64>()
		var preexistingMyInfoNums = Set<Int64>()
	}

	/// Renames the App-Store Core Data store out of the way so that SwiftData
	/// can create a fresh store at the same path without clobbering user data.
	///
	/// Must be called **before** the SwiftData `ModelContainer` is initialised.
	/// Safe to call on every launch — it is a no-op when:
	///   - The candidate file does not exist, or
	///   - The candidate file is not a Core Data store, or
	///   - The renamed legacy file already exists (rename already done).
	static func prepareForMigration(
		locations: StoreLocations = .applicationSupport,
		options: MigrationOptions = MigrationOptions()
	) throws {
		let fm = FileManager.default
		if fm.fileExists(atPath: locations.retirementMarkerURL.path),
		   fm.fileExists(atPath: locations.backupStoreURL.path),
		   !fm.fileExists(atPath: locations.legacyStoreURL.path) {
			try fm.removeItem(at: locations.retirementMarkerURL)
		}
		let candidateExists = fm.fileExists(atPath: locations.candidateStoreURL.path)
		let legacyExists = fm.fileExists(atPath: locations.legacyStoreURL.path)
		let transitionStarted = ["-wal", "-shm"].contains { suffix in
			fm.fileExists(atPath: sidecar(of: locations.legacyStoreURL, suffix: suffix).path)
		}
		guard candidateExists || legacyExists || transitionStarted else { return }

		if candidateExists, !legacyExists, !transitionStarted,
		   !isCoreDataStore(at: locations.candidateStoreURL) {
			return
		}

		Logger.data.info("⬆️ CoreDataMigrationService: preserving Core Data store before SwiftData init")
		// Move the main file last. Until that succeeds, legacyStoreExists remains
		// false and startup cannot mistake an incomplete family for a migration source.
		let storeMembers: [(suffix: String, member: StoreMember)] = [
			("-wal", .wal),
			("-shm", .shm),
			("", .main)
		]
		for storeMember in storeMembers {
			let src = sidecar(of: locations.candidateStoreURL, suffix: storeMember.suffix)
			let dst = sidecar(of: locations.legacyStoreURL, suffix: storeMember.suffix)
			guard fm.fileExists(atPath: src.path) else { continue }
			if fm.fileExists(atPath: dst.path) {
				guard fm.contentsEqual(atPath: src.path, andPath: dst.path) else {
					throw MigrationError.storeFamilyConflict(dst.lastPathComponent)
				}
				try fm.removeItem(at: src)
			} else {
				try fm.moveItem(at: src, to: dst)
			}
			try options.checkpoint(.afterPrepareMove(storeMember.member))
		}
	}

	/// Returns `true` when a renamed legacy Core Data store exists and has not
	/// yet been migrated into SwiftData.
	static func legacyStoreExists(at locations: StoreLocations = .applicationSupport) -> Bool {
		FileManager.default.fileExists(atPath: locations.legacyStoreURL.path)
	}

	/// Performs the full Core Data → SwiftData migration.
	///
	/// - Parameter swiftDataContainer: The already-initialised SwiftData
	///   `ModelContainer` that data should be written into.
	/// - Throws: Any error encountered while reading Core Data or writing
	///   SwiftData.  The caller is responsible for surfacing this to the user
	///   rather than silently destroying data.
	static func migrateOffMain(
		into swiftDataContainer: ModelContainer,
		locations: StoreLocations = .applicationSupport,
		options: MigrationOptions = MigrationOptions()
	) async throws {
		try await Task.detached(priority: .userInitiated) {
			try migrate(into: swiftDataContainer, locations: locations, options: options)
		}.value
	}

	static func migrate(
		into swiftDataContainer: ModelContainer,
		locations: StoreLocations = .applicationSupport,
		options: MigrationOptions = MigrationOptions()
	) throws {
		precondition(options.batchSize > 0)
		let migrationStartedAt = ContinuousClock.now
		Logger.data.notice("⬆️ [MIGRATION] migration begin")

		let state = MergeState()
		try withCoreDataContext(at: locations.legacyStoreURL) { cdContext in
			Logger.data.notice("⬆️ [MIGRATION] legacy store open: \(elapsedSeconds(since: migrationStartedAt), privacy: .public) seconds")
			let parentContext = ModelContext(swiftDataContainer)
			parentContext.autosaveEnabled = false

			// Commit parents, channels, and configs together. This keeps the rescue
			// decision stable if a later history batch is interrupted and retried.
			let nodeMap = try migrateNodes(cdContext: cdContext, sdContext: parentContext, state: state)
			_ = try migrateUsers(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap)
			let infoMap = try migrateMyInfos(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateChannels(cdContext: cdContext, sdContext: parentContext, infoMap: infoMap, state: state)
			try migrateBluetoothConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateCannedMessageConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateDeviceConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateDisplayConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateExternalNotifConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateLoRaConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateMQTTConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateNetworkConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migratePositionConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateRangeTestConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateSerialConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try migrateTelemetryConfigs(cdContext: cdContext, sdContext: parentContext, nodeMap: nodeMap, state: state)
			try parentContext.save()
			try options.checkpoint(.afterParentSave)
			Logger.data.notice("⬆️ [MIGRATION] parents saved: \(elapsedSeconds(since: migrationStartedAt), privacy: .public) seconds")
		}

		try autoreleasepool {
			try withCoreDataContext(at: locations.legacyStoreURL) { cdContext in
				try migrateMessages(cdContext: cdContext, container: swiftDataContainer, options: options)
			}
		}
		try autoreleasepool {
			try withCoreDataContext(at: locations.legacyStoreURL) { cdContext in
				try migratePositions(cdContext: cdContext, container: swiftDataContainer, options: options)
			}
		}
		try autoreleasepool {
			try withCoreDataContext(at: locations.legacyStoreURL) { cdContext in
				try migrateTelemetry(cdContext: cdContext, container: swiftDataContainer, options: options)
			}
		}
		Logger.data.notice("⬆️ [MIGRATION] source store closed: \(elapsedSeconds(since: migrationStartedAt), privacy: .public) seconds")

		try options.checkpoint(.beforeRetirement)
		try retireLegacyStore(at: locations, options: options)
		Logger.data.notice("⬆️ [MIGRATION] migration complete: \(elapsedSeconds(since: migrationStartedAt), privacy: .public) seconds")
	}
}

// MARK: - Store inspection

private extension CoreDataMigrationService {

	static func elapsedSeconds(since start: ContinuousClock.Instant) -> Double {
		let components = start.duration(to: .now).components
		return Double(components.seconds) + Double(components.attoseconds) / 1e18
	}

	static func withCoreDataContext<T>(
		at storeURL: URL,
		body: (NSManagedObjectContext) throws -> T
	) throws -> T {
		let container = try makeCoreDataContainer(at: storeURL)
		let context = container.newBackgroundContext()
		context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
		do {
			let result = try context.performAndWait {
				try body(context)
			}
			for store in container.persistentStoreCoordinator.persistentStores {
				try container.persistentStoreCoordinator.remove(store)
			}
			return result
		} catch {
			for store in container.persistentStoreCoordinator.persistentStores {
				try? container.persistentStoreCoordinator.remove(store)
			}
			throw error
		}
	}

	static func sidecar(of storeURL: URL, suffix: String) -> URL {
		storeURL.deletingPathExtension().appendingPathExtension("sqlite\(suffix)")
	}

	/// Returns `true` when the SQLite file at `url` is a Core Data store.
	///
	/// Uses `NSPersistentStoreCoordinator.metadataForPersistentStore` which is
	/// read-only — it does not modify the file.
	static func isCoreDataStore(at url: URL) -> Bool {
		guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
			ofType: NSSQLiteStoreType,
			at: url
		) else {
			// metadataForPersistentStore threw — the file exists but is not a
			// recognized SQLite/Core Data store (e.g. it is a SwiftData store
			// or a corrupt file).  Do not rename it.
			return false
		}
		// NSStoreModelVersionHashesKey is present in every Core Data store that
		// has been opened at least once with a versioned model.  Older stores
		// that predate model versioning may lack it, so fall back to checking
		// NSStoreTypeKey as a secondary signal.
		if metadata[NSStoreModelVersionHashesKey] != nil { return true }
		if let type = metadata[NSStoreTypeKey] as? String, type == NSSQLiteStoreType { return true }
		return false
	}
}

// MARK: - Core Data container bootstrap

private extension CoreDataMigrationService {

	/// Creates an `NSPersistentContainer` that opens the *existing* Core Data
	/// store using the bundled `.xcdatamodeld` model.  Automatic lightweight
	/// migration is enabled so any minor schema drift across device upgrades
	/// is handled transparently.
	static func makeCoreDataContainer(at legacyStoreURL: URL) throws -> NSPersistentContainer {
		guard let momdURL = Bundle.main.url(
			forResource: "Meshtastic",
			withExtension: "momd"
		) else {
			throw MigrationError.modelNotFound
		}

		// Load the V58 model directly by path inside the .momd bundle so this
		// is immune to Xcode resetting .xccurrentversion.  The 2.7.12 App Store
		// wrote stores with MeshtasticDataModelV 58.xcdatamodel — loading it by
		// explicit URL means migration always uses the correct schema regardless
		// of which version .xccurrentversion points to.
		let v58URL = momdURL.appendingPathComponent("MeshtasticDataModelV 58.mom")
		let modelURL: URL
		if FileManager.default.fileExists(atPath: v58URL.path) {
			modelURL = v58URL
		} else {
			// Fallback: let Core Data use whatever .xccurrentversion says.
			modelURL = momdURL
		}

		guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
			throw MigrationError.modelLoadFailed
		}

		let container = NSPersistentContainer(name: "Meshtastic", managedObjectModel: model)

		let storeDescription = NSPersistentStoreDescription(url: legacyStoreURL)
		storeDescription.shouldMigrateStoreAutomatically = true
		storeDescription.shouldInferMappingModelAutomatically = true
		container.persistentStoreDescriptions = [storeDescription]

		var loadError: Error?
		container.loadPersistentStores { _, error in
			loadError = error
		}
		if let loadError {
			throw loadError
		}
		return container
	}
}

// MARK: - Per-entity migration helpers

// Each function returns a dictionary mapping NSManagedObjectID → SwiftData
// entity so that relationships can be wired up in later phases.

private extension CoreDataMigrationService {

	// MARK: NodeInfoEntity

	static func migrateNodes(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		state: MergeState
	) throws -> [NSManagedObjectID: NodeInfoEntity] {
		let request = NSFetchRequest<NSManagedObject>(entityName: "NodeInfoEntity")
		let objects = try cdContext.fetch(request)
		var map = [NSManagedObjectID: NodeInfoEntity]()

		let existingByNum = Dictionary(
			(try sdContext.fetch(FetchDescriptor<NodeInfoEntity>())).map { ($0.num, $0) },
			uniquingKeysWith: { first, _ in first }
		)

		var migrated = 0
		for obj in objects {
			let num = (obj.value(forKey: "num") as? Int64) ?? 0
			if let existing = existingByNum[num] {
				// Rescue merge: the mesh re-taught the app this node after the failed
				// migration. Keep the live row; legacy history will attach to it.
				state.preexistingNodeNums.insert(num)
				map[obj.objectID] = existing
				continue
			}
			let sd = NodeInfoEntity()
			sd.bleName      = obj.value(forKey: "bleName") as? String
			sd.channel      = (obj.value(forKey: "channel") as? Int32) ?? 0
			sd.id           = (obj.value(forKey: "id") as? Int64) ?? 0
			sd.lastHeard    = obj.value(forKey: "lastHeard") as? Date ?? Date()
			sd.num          = num
			sd.snr          = (obj.value(forKey: "snr") as? Float) ?? 0
			sdContext.insert(sd)
			map[obj.objectID] = sd
			migrated += 1
		}
		Logger.data.info("⬆️ migrated \(migrated) of \(objects.count) NodeInfoEntity records (\(state.preexistingNodeNums.count) already present)")
		return map
	}

	// MARK: UserEntity

	static func migrateUsers(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws -> [NSManagedObjectID: UserEntity] {
		let request = NSFetchRequest<NSManagedObject>(entityName: "UserEntity")
		let objects = try cdContext.fetch(request)
		var map = [NSManagedObjectID: UserEntity]()

		let existingByNum = Dictionary(
			(try sdContext.fetch(FetchDescriptor<UserEntity>())).map { ($0.num, $0) },
			uniquingKeysWith: { first, _ in first }
		)

		var migrated = 0
		for obj in objects {
			let num = (obj.value(forKey: "num") as? Int64) ?? 0
			if let existing = existingByNum[num] {
				map[obj.objectID] = existing
				continue
			}
			let sd = UserEntity()
			sd.hwModel   = obj.value(forKey: "hwModel") as? String
			sd.isLicensed = (obj.value(forKey: "isLicensed") as? Bool) ?? false
			sd.longName  = obj.value(forKey: "longName") as? String
			sd.num       = num
			sd.shortName = obj.value(forKey: "shortName") as? String
			sd.userId    = obj.value(forKey: "userId") as? String
			// macaddr existed in Core Data but is intentionally dropped in SwiftData

			if let cdNode = obj.value(forKey: "userNode") as? NSManagedObject,
			   let sdNode = nodeMap[cdNode.objectID],
			   sdNode.user == nil {
				// Only claim the node when it has no live user; a preexisting node keeps its
				// (fresher) user rather than being reparented onto the legacy row.
				sd.userNode = sdNode
			}
			sdContext.insert(sd)
			map[obj.objectID] = sd
			migrated += 1
		}
		Logger.data.info("⬆️ migrated \(migrated) of \(objects.count) UserEntity records")
		return map
	}

	// MARK: MyInfoEntity

	static func migrateMyInfos(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws -> [NSManagedObjectID: MyInfoEntity] {
		let request = NSFetchRequest<NSManagedObject>(entityName: "MyInfoEntity")
		let objects = try cdContext.fetch(request)
		var map = [NSManagedObjectID: MyInfoEntity]()

		let existingByNum = Dictionary(
			(try sdContext.fetch(FetchDescriptor<MyInfoEntity>())).map { ($0.myNodeNum, $0) },
			uniquingKeysWith: { first, _ in first }
		)

		var migrated = 0
		for obj in objects {
			let myNodeNum = (obj.value(forKey: "myNodeNum") as? Int64) ?? 0
			if let existing = existingByNum[myNodeNum] {
				state.preexistingMyInfoNums.insert(myNodeNum)
				map[obj.objectID] = existing
				continue
			}
			let sd = MyInfoEntity()
			sd.bleName         = obj.value(forKey: "bleName") as? String
			sd.minAppVersion   = (obj.value(forKey: "minAppVersion") as? Int32) ?? 0
			sd.myNodeNum       = myNodeNum
			sd.peripheralId    = obj.value(forKey: "peripheralId") as? String
			sd.rebootCount     = (obj.value(forKey: "rebootCount") as? Int32) ?? 0

			if let cdNode = obj.value(forKey: "myInfoNode") as? NSManagedObject,
			   let sdNode = nodeMap[cdNode.objectID] {
				sd.myInfoNode = sdNode
			}
			sdContext.insert(sd)
			map[obj.objectID] = sd
			migrated += 1
		}
		Logger.data.info("⬆️ migrated \(migrated) of \(objects.count) MyInfoEntity records")
		return map
	}

	// MARK: ChannelEntity

	static func migrateChannels(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		infoMap: [NSManagedObjectID: MyInfoEntity],
		state: MergeState
	) throws {
		let request = NSFetchRequest<NSManagedObject>(entityName: "ChannelEntity")
		let objects = try cdContext.fetch(request)

		var migrated = 0
		for obj in objects {
			let cdInfo = obj.value(forKey: "myInfoChannel") as? NSManagedObject
			guard let sdInfo = cdInfo.flatMap({ infoMap[$0.objectID] }) else {
				continue
			}
			if state.preexistingMyInfoNums.contains(sdInfo.myNodeNum) {
				// Rescue merge: this radio's MyInfo survived the failed migration and its
				// current channel set is fresher than the legacy one — don't duplicate it.
				continue
			}
			let sd = ChannelEntity()
			sd.downlinkEnabled = (obj.value(forKey: "downlinkEnabled") as? Bool) ?? false
			sd.id              = (obj.value(forKey: "id") as? Int32) ?? 0
			sd.index           = (obj.value(forKey: "index") as? Int32) ?? 0
			sd.name            = obj.value(forKey: "name") as? String
			sd.psk             = obj.value(forKey: "psk") as? Data
			sd.role            = (obj.value(forKey: "role") as? Int32) ?? 0
			sd.uplinkEnabled   = (obj.value(forKey: "uplinkEnabled") as? Bool) ?? false

			sd.myInfoChannel = sdInfo
			sdContext.insert(sd)
			migrated += 1
		}
		Logger.data.info("⬆️ migrated \(migrated) of \(objects.count) ChannelEntity records")
	}

	// MARK: MessageEntity

	static func migrateMessages(
		cdContext: NSManagedObjectContext,
		container: ModelContainer,
		options: MigrationOptions
	) throws {
		let phaseStartedAt = ContinuousClock.now
		let batchSize = options.batchSize
		var existingMessageIds = try existingMessageIds(in: container, batchSize: batchSize)
		Logger.data.notice("⬆️ [MIGRATION] existing message scan: \(elapsedSeconds(since: phaseStartedAt), privacy: .public) seconds")
		var messageUserLinks: [Int64: MessageUserLink] = [:]
		var migrated = 0
		var processed = 0

		try forEachCoreDataBatch(
			entityName: "MessageEntity",
			context: cdContext,
			batchSize: batchSize,
			relationshipKeyPathsForPrefetching: ["fromUser", "toUser"]
		) { batchIndex, objects in
			let sdContext = ModelContext(container)
			sdContext.autosaveEnabled = false

			for obj in objects {
				processed += 1
				let messageId = (obj.value(forKey: "messageId") as? Int64) ?? 0
				messageUserLinks[messageId] = MessageUserLink(
					fromNum: relatedInt64(obj, relationship: "fromUser", key: "num"),
					toNum: relatedInt64(obj, relationship: "toUser", key: "num")
				)
				guard existingMessageIds.insert(messageId).inserted else { continue }

				let sd = MessageEntity()
				sd.ackError = (obj.value(forKey: "ackError") as? Int32) ?? 0
				sd.ackSNR = (obj.value(forKey: "ackSNR") as? Float) ?? 0
				sd.ackTimestamp = (obj.value(forKey: "ackTimestamp") as? Int32) ?? 0
				sd.admin = (obj.value(forKey: "admin") as? Bool) ?? false
				sd.adminDescription = obj.value(forKey: "adminDescription") as? String
				sd.channel = (obj.value(forKey: "channel") as? Int32) ?? 0
				sd.isEmoji = (obj.value(forKey: "isEmoji") as? Bool) ?? false
				sd.messageId = messageId
				sd.messagePayload = obj.value(forKey: "messagePayload") as? String
				sd.messagePayloadMarkdown = obj.value(forKey: "messagePayloadMarkdown") as? String
				sd.messagePayloadTranslated = obj.value(forKey: "messagePayloadTranslated") as? String
				sd.messagePayloadTranslatedMarkdown = obj.value(forKey: "messagePayloadTranslatedMarkdown") as? String
				sd.messageTimestamp = (obj.value(forKey: "messageTimestamp") as? Int32) ?? 0
				sd.pkiEncrypted = (obj.value(forKey: "pkiEncrypted") as? Bool) ?? false
				sd.portNum = (obj.value(forKey: "portNum") as? Int32) ?? 0
				sd.publicKey = obj.value(forKey: "publicKey") as? Data
				sd.read = (obj.value(forKey: "read") as? Bool) ?? false
				sd.realACK = (obj.value(forKey: "realACK") as? Bool) ?? false
				sd.receivedACK = (obj.value(forKey: "receivedACK") as? Bool) ?? false
				sd.relayNode = (obj.value(forKey: "relayNode") as? Int64) ?? 0
				sd.relays = (obj.value(forKey: "relays") as? Int16) ?? 0
				sd.replyID = (obj.value(forKey: "replyID") as? Int64) ?? 0
				sd.rssi = (obj.value(forKey: "rssi") as? Int32) ?? 0
				sd.showTranslatedMessage = (obj.value(forKey: "showTranslatedMessage") as? Bool) ?? false
				sd.snr = (obj.value(forKey: "snr") as? Float) ?? 0

				sdContext.insert(sd)
				migrated += 1
			}
			if sdContext.hasChanges {
				try sdContext.save()
			}
			try options.checkpoint(.afterHistoryBatch(.messages, index: batchIndex))
		}

		try options.checkpoint(.afterMessageScalarPersistence)
		Logger.data.notice("⬆️ [MIGRATION] message scalars saved: \(elapsedSeconds(since: phaseStartedAt), privacy: .public) seconds")
		try linkMessageUsers(
			messageUserLinks: messageUserLinks,
			container: container,
			options: options
		)
		Logger.data.notice("⬆️ [MIGRATION] messages complete: \(elapsedSeconds(since: phaseStartedAt), privacy: .public) seconds; migrated \(migrated, privacy: .public) of \(processed, privacy: .public)")
	}

	static func linkMessageUsers(
		messageUserLinks: [Int64: MessageUserLink],
		container: ModelContainer,
		options: MigrationOptions
	) throws {
		var sentMessageIds: [Int64: [Int64]] = [:]
		var receivedMessageIds: [Int64: [Int64]] = [:]
		for (messageId, link) in messageUserLinks {
			if let fromNum = link.fromNum {
				sentMessageIds[fromNum, default: []].append(messageId)
			}
			if let toNum = link.toNum {
				receivedMessageIds[toNum, default: []].append(messageId)
			}
		}

		let userNums = Set(sentMessageIds.keys).union(receivedMessageIds.keys).sorted()
		let userGroupSize = max(1, options.batchSize / 5)
		for userStart in stride(from: 0, to: userNums.count, by: userGroupSize) {
			let userEnd = min(userStart + userGroupSize, userNums.count)
			let userNumBatch = Array(userNums[userStart..<userEnd])
			let messageIds = Set(userNumBatch.flatMap {
				(sentMessageIds[$0] ?? []) + (receivedMessageIds[$0] ?? [])
			}).sorted()
			for messageStart in stride(from: 0, to: messageIds.count, by: options.batchSize) {
				let messageEnd = min(messageStart + options.batchSize, messageIds.count)
				let messageIdBatch = Array(messageIds[messageStart..<messageEnd])
				let context = ModelContext(container)
				context.autosaveEnabled = false
				let userDescriptor = FetchDescriptor<UserEntity>(
					predicate: #Predicate { userNumBatch.contains($0.num) }
				)
				let usersByNum = Dictionary(
					uniqueKeysWithValues: try context.fetch(userDescriptor).map { ($0.num, $0) }
				)
				let descriptor = FetchDescriptor<MessageEntity>(
					predicate: #Predicate { messageIdBatch.contains($0.messageId) }
				)
				for message in try context.fetch(descriptor) {
					guard let link = messageUserLinks[message.messageId] else { continue }
					if message.fromUser == nil,
					   let fromNum = link.fromNum,
					   let user = usersByNum[fromNum] {
						message.fromUser = user
					}
					if message.toUser == nil,
					   let toNum = link.toNum,
					   let user = usersByNum[toNum] {
						message.toUser = user
					}
				}
				if context.hasChanges {
					try context.save()
				}
			}
			for num in userNumBatch {
				try options.checkpoint(.afterMessageUserLink(nodeNum: num))
			}
		}
	}

	// MARK: PositionEntity

	static func migratePositions(
		cdContext: NSManagedObjectContext,
		container: ModelContainer,
		options: MigrationOptions
	) throws {
		let phaseStartedAt = ContinuousClock.now
		let batchSize = options.batchSize
		let destinationCounts = try existingPositionCounts(in: container, batchSize: batchSize)
		Logger.data.notice("⬆️ [MIGRATION] existing position scan: \(elapsedSeconds(since: phaseStartedAt), privacy: .public) seconds")
		var sourceCounts: [PositionFingerprint: Int] = [:]
		var migrated = 0
		var processed = 0

		try forEachCoreDataBatch(
			entityName: "PositionEntity",
			context: cdContext,
			batchSize: batchSize,
			relationshipKeyPathsForPrefetching: ["nodePosition"]
		) { batchIndex, objects in
			let sdContext = ModelContext(container)
			sdContext.autosaveEnabled = false
			var nodes: [Int64: NodeInfoEntity] = [:]

			for obj in objects {
				processed += 1
				let nodeNum = relatedInt64(obj, relationship: "nodePosition", key: "num")
				let fingerprint = PositionFingerprint(coreDataObject: obj, nodeNum: nodeNum)
				sourceCounts[fingerprint, default: 0] += 1
				guard sourceCounts[fingerprint, default: 0] > destinationCounts[fingerprint, default: 0] else {
					continue
				}

				let sd = PositionEntity()
				sd.altitude = (obj.value(forKey: "altitude") as? Int32) ?? 0
				sd.heading = (obj.value(forKey: "heading") as? Int32) ?? 0
				sd.latest = (obj.value(forKey: "latest") as? Bool) ?? false
				sd.latitudeI = (obj.value(forKey: "latitudeI") as? Int32) ?? 0
				sd.longitudeI = (obj.value(forKey: "longitudeI") as? Int32) ?? 0
				sd.precisionBits = (obj.value(forKey: "precisionBits") as? Int32) ?? 32
				sd.rssi = (obj.value(forKey: "rssi") as? Int32) ?? 0
				sd.satsInView = (obj.value(forKey: "satsInView") as? Int32) ?? 0
				sd.seqNo = (obj.value(forKey: "seqNo") as? Int32) ?? 0
				sd.snr = (obj.value(forKey: "snr") as? Float) ?? 0
				sd.speed = (obj.value(forKey: "speed") as? Int32) ?? 0
				sd.time = obj.value(forKey: "time") as? Date
				if let nodeNum {
					sd.nodePosition = try destinationNode(num: nodeNum, context: sdContext, cache: &nodes)
				}
				sdContext.insert(sd)
				migrated += 1
			}
			if sdContext.hasChanges {
				try sdContext.save()
			}
			try options.checkpoint(.afterHistoryBatch(.positions, index: batchIndex))
		}
		Logger.data.notice("⬆️ [MIGRATION] positions complete: \(elapsedSeconds(since: phaseStartedAt), privacy: .public) seconds; migrated \(migrated, privacy: .public) of \(processed, privacy: .public)")
	}

	// MARK: TelemetryEntity

	static func migrateTelemetry(
		cdContext: NSManagedObjectContext,
		container: ModelContainer,
		options: MigrationOptions
	) throws {
		let phaseStartedAt = ContinuousClock.now
		let batchSize = options.batchSize
		let destinationCounts = try existingTelemetryCounts(in: container, batchSize: batchSize)
		Logger.data.notice("⬆️ [MIGRATION] existing telemetry scan: \(elapsedSeconds(since: phaseStartedAt), privacy: .public) seconds")
		var sourceCounts: [TelemetryFingerprint: Int] = [:]
		var migrated = 0
		var processed = 0

		try forEachCoreDataBatch(
			entityName: "TelemetryEntity",
			context: cdContext,
			batchSize: batchSize,
			relationshipKeyPathsForPrefetching: ["nodeTelemetry"]
		) { batchIndex, objects in
			let sdContext = ModelContext(container)
			sdContext.autosaveEnabled = false
			var nodes: [Int64: NodeInfoEntity] = [:]

			for obj in objects {
				processed += 1
				let nodeNum = relatedInt64(obj, relationship: "nodeTelemetry", key: "num")
				let fingerprint = TelemetryFingerprint(coreDataObject: obj, nodeNum: nodeNum)
				sourceCounts[fingerprint, default: 0] += 1
				guard sourceCounts[fingerprint, default: 0] > destinationCounts[fingerprint, default: 0] else {
					continue
				}

				let sd = TelemetryEntity()
				sd.metricsType = (obj.value(forKey: "metricsType") as? Int32) ?? 0
				sd.numOnlineNodes = (obj.value(forKey: "numOnlineNodes") as? Int32) ?? 0
				sd.numPacketsRx = (obj.value(forKey: "numPacketsRx") as? Int32) ?? 0
				sd.numPacketsRxBad = (obj.value(forKey: "numPacketsRxBad") as? Int32) ?? 0
				sd.numPacketsTx = (obj.value(forKey: "numPacketsTx") as? Int32) ?? 0
				sd.numRxDupe = (obj.value(forKey: "numRxDupe") as? Int32) ?? 0
				sd.numTotalNodes = (obj.value(forKey: "numTotalNodes") as? Int32) ?? 0
				sd.numTxRelay = (obj.value(forKey: "numTxRelay") as? Int32) ?? 0
				sd.numTxRelayCanceled = (obj.value(forKey: "numTxRelayCanceled") as? Int32) ?? 0
				sd.time = obj.value(forKey: "time") as? Date
				sd.airUtilTx = obj.value(forKey: "airUtilTx") as? Float
				sd.barometricPressure = obj.value(forKey: "barometricPressure") as? Float
				sd.batteryLevel = obj.value(forKey: "batteryLevel") as? Int32
				sd.channelUtilization = obj.value(forKey: "channelUtilization") as? Float
				sd.current = obj.value(forKey: "current") as? Float
				sd.gasResistance = obj.value(forKey: "gasResistance") as? Float
				sd.iaq = obj.value(forKey: "iaq") as? Int32
				sd.irLux = obj.value(forKey: "irLux") as? Float
				sd.lux = obj.value(forKey: "lux") as? Float
				sd.powerCh1Current = obj.value(forKey: "powerCh1Current") as? Float
				sd.powerCh1Voltage = obj.value(forKey: "powerCh1Voltage") as? Float
				sd.powerCh2Current = obj.value(forKey: "powerCh2Current") as? Float
				sd.powerCh2Voltage = obj.value(forKey: "powerCh2Voltage") as? Float
				sd.powerCh3Current = obj.value(forKey: "powerCh3Current") as? Float
				sd.powerCh3Voltage = obj.value(forKey: "powerCh3Voltage") as? Float
				sd.radiation = obj.value(forKey: "radiation") as? Float
				sd.rainfall1H = obj.value(forKey: "rainfall1H") as? Float
				sd.rainfall24H = obj.value(forKey: "rainfall24H") as? Float
				sd.relativeHumidity = obj.value(forKey: "relativeHumidity") as? Float
				sd.rssi = obj.value(forKey: "rssi") as? Int32
				sd.snr = obj.value(forKey: "snr") as? Float
				if let soilMoisture = obj.value(forKey: "soilMoisture") as? Int32 {
					sd.soilMoisture = UInt32(bitPattern: soilMoisture)
				}
				sd.soilTemperature = obj.value(forKey: "soilTemperature") as? Float
				sd.temperature = obj.value(forKey: "temperature") as? Float
				sd.uptimeSeconds = obj.value(forKey: "uptimeSeconds") as? Int32
				sd.uvLux = obj.value(forKey: "uvLux") as? Float
				sd.voltage = obj.value(forKey: "voltage") as? Float
				sd.weight = obj.value(forKey: "weight") as? Float
				sd.whiteLux = obj.value(forKey: "whiteLux") as? Float
				sd.windDirection = obj.value(forKey: "windDirection") as? Int32
				sd.windGust = obj.value(forKey: "windGust") as? Float
				sd.windLull = obj.value(forKey: "windLull") as? Float
				sd.windSpeed = obj.value(forKey: "windSpeed") as? Float
				if let nodeNum {
					sd.nodeTelemetry = try destinationNode(num: nodeNum, context: sdContext, cache: &nodes)
				}
				sdContext.insert(sd)
				migrated += 1
			}
			if sdContext.hasChanges {
				try sdContext.save()
			}
			try options.checkpoint(.afterHistoryBatch(.telemetry, index: batchIndex))
		}
		Logger.data.notice("⬆️ [MIGRATION] telemetry complete: \(elapsedSeconds(since: phaseStartedAt), privacy: .public) seconds; migrated \(migrated, privacy: .public) of \(processed, privacy: .public)")
	}

	// MARK: Batching helpers

	static func forEachCoreDataBatch(
		entityName: String,
		context: NSManagedObjectContext,
		batchSize: Int,
		relationshipKeyPathsForPrefetching: [String] = [],
		body: (Int, [NSManagedObject]) throws -> Void
	) throws {
		let idRequest = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
		idRequest.resultType = .managedObjectIDResultType
		idRequest.includesPendingChanges = false
		let objectIDs = try context.fetch(idRequest)

		for (batchIndex, start) in stride(from: 0, to: objectIDs.count, by: batchSize).enumerated() {
			let end = min(start + batchSize, objectIDs.count)
			let batchObjectIDs = Array(objectIDs[start..<end])
			try autoreleasepool {
				let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
				request.predicate = NSPredicate(format: "SELF IN %@", batchObjectIDs)
				request.includesPendingChanges = false
				request.returnsObjectsAsFaults = false
				request.relationshipKeyPathsForPrefetching = relationshipKeyPathsForPrefetching
				let objects = try context.fetch(request)
				try body(batchIndex, objects)
				context.reset()
			}
		}
	}

	static func existingPositionCounts(
		in container: ModelContainer,
		batchSize: Int
	) throws -> [PositionFingerprint: Int] {
		var counts: [PositionFingerprint: Int] = [:]
		var offset = 0
		while true {
			let context = ModelContext(container)
			var descriptor = FetchDescriptor<PositionEntity>()
			descriptor.fetchLimit = batchSize
			descriptor.fetchOffset = offset
			let positions = try context.fetch(descriptor)
			guard !positions.isEmpty else { return counts }
			for position in positions {
				counts[PositionFingerprint(position), default: 0] += 1
			}
			offset += positions.count
		}
	}

	static func existingTelemetryCounts(
		in container: ModelContainer,
		batchSize: Int
	) throws -> [TelemetryFingerprint: Int] {
		var counts: [TelemetryFingerprint: Int] = [:]
		var offset = 0
		while true {
			let context = ModelContext(container)
			var descriptor = FetchDescriptor<TelemetryEntity>()
			descriptor.fetchLimit = batchSize
			descriptor.fetchOffset = offset
			let telemetry = try context.fetch(descriptor)
			guard !telemetry.isEmpty else { return counts }
			for sample in telemetry {
				counts[TelemetryFingerprint(sample), default: 0] += 1
			}
			offset += telemetry.count
		}
	}

	static func existingMessageIds(
		in container: ModelContainer,
		batchSize: Int
	) throws -> Set<Int64> {
		var ids = Set<Int64>()
		var offset = 0
		while true {
			let context = ModelContext(container)
			var descriptor = FetchDescriptor<MessageEntity>()
			descriptor.fetchLimit = batchSize
			descriptor.fetchOffset = offset
			let messages = try context.fetch(descriptor)
			guard !messages.isEmpty else { return ids }
			ids.formUnion(messages.map(\.messageId))
			offset += messages.count
		}
	}

	static func relatedInt64(
		_ object: NSManagedObject,
		relationship: String,
		key: String
	) -> Int64? {
		(object.value(forKey: relationship) as? NSManagedObject)?.value(forKey: key) as? Int64
	}

	static func destinationNode(
		num: Int64,
		context: ModelContext,
		cache: inout [Int64: NodeInfoEntity]
	) throws -> NodeInfoEntity? {
		if let cached = cache[num] { return cached }
		let targetNum = num
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == targetNum }
		)
		descriptor.fetchLimit = 1
		let node = try context.fetch(descriptor).first
		if let node { cache[num] = node }
		return node
	}

	// MARK: Config entities

	static func migrateBluetoothConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "BluetoothConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "bluetoothConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> BluetoothConfigEntity in
			let sd = BluetoothConfigEntity()
			sd.enabled  = (obj.value(forKey: "enabled") as? Bool) ?? false
			sd.fixedPin = (obj.value(forKey: "fixedPin") as? Int32) ?? 0
			sd.mode     = (obj.value(forKey: "mode") as? Int32) ?? 0
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? BluetoothConfigEntity).map { sdNode.bluetoothConfig = $0 }
		}
	}

	static func migrateCannedMessageConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "CannedMessageConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "cannedMessagesConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> CannedMessageConfigEntity in
			let sd = CannedMessageConfigEntity()
			// enabled is deprecated (no successor) and no longer written — not migrated; the
			// stored property keeps its default. (#2021)
			sd.inputbrokerEventCcw    = (obj.value(forKey: "inputbrokerEventCcw") as? Int32) ?? 0
			sd.inputbrokerEventCw     = (obj.value(forKey: "inputbrokerEventCw") as? Int32) ?? 0
			sd.inputbrokerEventPress  = (obj.value(forKey: "inputbrokerEventPress") as? Int32) ?? 0
			sd.inputbrokerPinA        = (obj.value(forKey: "inputbrokerPinA") as? Int32) ?? 0
			sd.inputbrokerPinB        = (obj.value(forKey: "inputbrokerPinB") as? Int32) ?? 0
			sd.inputbrokerPinPress    = (obj.value(forKey: "inputbrokerPinPress") as? Int32) ?? 0
			sd.rotary1Enabled         = (obj.value(forKey: "rotary1Enabled") as? Bool) ?? false
			sd.sendBell               = (obj.value(forKey: "sendBell") as? Bool) ?? false
			sd.updown1Enabled         = (obj.value(forKey: "updown1Enabled") as? Bool) ?? false
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? CannedMessageConfigEntity).map { sdNode.cannedMessageConfig = $0 }
		}
	}

	static func migrateDeviceConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "DeviceConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "deviceConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> DeviceConfigEntity in
			let sd = DeviceConfigEntity()
			sd.debugLogEnabled = (obj.value(forKey: "debugLogEnabled") as? Bool) ?? false
			sd.role            = (obj.value(forKey: "role") as? Int32) ?? 0
			sd.serialEnabled   = (obj.value(forKey: "serialEnabled") as? Bool) ?? false
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? DeviceConfigEntity).map { sdNode.deviceConfig = $0 }
		}
	}

	static func migrateDisplayConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "DisplayConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "displayConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> DisplayConfigEntity in
			let sd = DisplayConfigEntity()
			sd.compassNorthTop        = (obj.value(forKey: "compassNorthTop") as? Bool) ?? false
			sd.flipScreen             = (obj.value(forKey: "flipScreen") as? Bool) ?? false
			// gpsFormat was removed from the SwiftData model; skip it
			sd.screenCarouselInterval = (obj.value(forKey: "screenCarouselInterval") as? Int32) ?? 0
			sd.screenOnSeconds        = (obj.value(forKey: "screenOnSeconds") as? Int32) ?? 0
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? DisplayConfigEntity).map { sdNode.displayConfig = $0 }
		}
	}

	static func migrateExternalNotifConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "ExternalNotificationConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "externalNotificationConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> ExternalNotificationConfigEntity in
			let sd = ExternalNotificationConfigEntity()
			sd.active             = (obj.value(forKey: "active") as? Bool) ?? false
			sd.alertBell          = (obj.value(forKey: "alertBell") as? Bool) ?? false
			sd.alertMessage       = (obj.value(forKey: "alertMessage") as? Bool) ?? false
			sd.enabled            = (obj.value(forKey: "enabled") as? Bool) ?? false
			sd.output             = (obj.value(forKey: "output") as? Int32) ?? 0
			sd.outputMilliseconds = (obj.value(forKey: "outputMilliseconds") as? Int32) ?? 0
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? ExternalNotificationConfigEntity).map { sdNode.externalNotificationConfig = $0 }
		}
	}

	static func migrateLoRaConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "LoRaConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "loRaConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> LoRaConfigEntity in
			let sd = LoRaConfigEntity()
			sd.bandwidth       = (obj.value(forKey: "bandwidth") as? Int32) ?? 0
			sd.channelNum      = (obj.value(forKey: "channelNum") as? Int32) ?? 0
			sd.codingRate      = (obj.value(forKey: "codingRate") as? Int32) ?? 0
			sd.frequencyOffset = (obj.value(forKey: "frequencyOffset") as? Float) ?? 0
			sd.hopLimit        = (obj.value(forKey: "hopLimit") as? Int32) ?? 3
			sd.modemPreset     = (obj.value(forKey: "modemPreset") as? Int32) ?? 0
			sd.regionCode      = (obj.value(forKey: "regionCode") as? Int32) ?? 0
			sd.spreadFactor    = (obj.value(forKey: "spreadFactor") as? Int32) ?? 0
			sd.txEnabled       = (obj.value(forKey: "txEnabled") as? Bool) ?? true
			sd.txPower         = (obj.value(forKey: "txPower") as? Int32) ?? 0
			sd.usePreset       = (obj.value(forKey: "usePreset") as? Bool) ?? true
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? LoRaConfigEntity).map { sdNode.loRaConfig = $0 }
		}
	}

	static func migrateMQTTConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "MQTTConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "mqttConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> MQTTConfigEntity in
			let sd = MQTTConfigEntity()
			sd.address           = obj.value(forKey: "address") as? String
			sd.enabled           = (obj.value(forKey: "enabled") as? Bool) ?? false
			sd.encryptionEnabled = (obj.value(forKey: "encryptionEnabled") as? Bool) ?? false
			sd.jsonEnabled       = (obj.value(forKey: "jsonEnabled") as? Bool) ?? false
			sd.password          = obj.value(forKey: "password") as? String
			sd.username          = obj.value(forKey: "username") as? String
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? MQTTConfigEntity).map { sdNode.mqttConfig = $0 }
		}
	}

	static func migrateNetworkConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "NetworkConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "networkConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> NetworkConfigEntity in
			let sd = NetworkConfigEntity()
			sd.ntpServer   = obj.value(forKey: "ntpServer") as? String
			sd.wifiEnabled = (obj.value(forKey: "wifiEnabled") as? Bool) ?? false
			sd.wifiPsk     = obj.value(forKey: "wifiPsk") as? String
			sd.wifiSsid    = obj.value(forKey: "wifiSsid") as? String
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? NetworkConfigEntity).map { sdNode.networkConfig = $0 }
		}
	}

	static func migratePositionConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "PositionConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "positionConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> PositionConfigEntity in
			let sd = PositionConfigEntity()
			sd.deviceGpsEnabled           = (obj.value(forKey: "deviceGpsEnabled") as? Bool) ?? false
			sd.fixedPosition              = (obj.value(forKey: "fixedPosition") as? Bool) ?? false
			sd.gpsAttemptTime             = (obj.value(forKey: "gpsAttemptTime") as? Int32) ?? 0
			sd.gpsUpdateInterval          = (obj.value(forKey: "gpsUpdateInterval") as? Int32) ?? 0
			sd.positionBroadcastSeconds   = (obj.value(forKey: "positionBroadcastSeconds") as? Int32) ?? 0
			sd.positionFlags              = (obj.value(forKey: "positionFlags") as? Int32) ?? 0
			sd.smartPositionEnabled       = (obj.value(forKey: "smartPositionEnabled") as? Bool) ?? false
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? PositionConfigEntity).map { sdNode.positionConfig = $0 }
		}
	}

	static func migrateRangeTestConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "RangeTestConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "rangeTestConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> RangeTestConfigEntity in
			let sd = RangeTestConfigEntity()
			sd.enabled = (obj.value(forKey: "enabled") as? Bool) ?? false
			sd.save    = (obj.value(forKey: "save") as? Bool) ?? false
			sd.sender  = (obj.value(forKey: "sender") as? Int32) ?? 0
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? RangeTestConfigEntity).map { sdNode.rangeTestConfig = $0 }
		}
	}

	static func migrateSerialConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "SerialConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "serialConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> SerialConfigEntity in
			let sd = SerialConfigEntity()
			sd.baudRate = (obj.value(forKey: "baudRate") as? Int32) ?? 0
			sd.echo     = (obj.value(forKey: "echo") as? Bool) ?? false
			sd.enabled  = (obj.value(forKey: "enabled") as? Bool) ?? false
			sd.mode     = (obj.value(forKey: "mode") as? Int32) ?? 0
			sd.rxd      = (obj.value(forKey: "rxd") as? Int32) ?? 0
			sd.timeout  = (obj.value(forKey: "timeout") as? Int32) ?? 0
			sd.txd      = (obj.value(forKey: "txd") as? Int32) ?? 0
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? SerialConfigEntity).map { sdNode.serialConfig = $0 }
		}
	}

	static func migrateTelemetryConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState
	) throws {
		try migrateConfigEntity(
			entityName: "TelemetryConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "telemetryConfigNode",
			nodeMap: nodeMap,
			state: state
		) { obj -> TelemetryConfigEntity in
			let sd = TelemetryConfigEntity()
			sd.deviceUpdateInterval           = (obj.value(forKey: "deviceUpdateInterval") as? Int32) ?? 0
			sd.environmentDisplayFahrenheit   = (obj.value(forKey: "environmentDisplayFahrenheit") as? Bool) ?? false
			sd.environmentMeasurementEnabled  = (obj.value(forKey: "environmentMeasurementEnabled") as? Bool) ?? false
			return sd
		} wireNode: { sdNode, sdConfig in
			(sdConfig as? TelemetryConfigEntity).map { sdNode.telemetryConfig = $0 }
		}
	}

	// MARK: Generic config helper

	/// Generic helper that fetches a config entity, creates the SwiftData
	/// counterpart via `make`, inserts it, and links it to its parent node via
	/// `wireNode`.
	static func migrateConfigEntity<T: PersistentModel>(
		entityName: String,
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeKey: String,
		nodeMap: [NSManagedObjectID: NodeInfoEntity],
		state: MergeState,
		make: (NSManagedObject) throws -> T,
		wireNode: (NodeInfoEntity, T) -> Void
	) throws {
		let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
		let objects = try cdContext.fetch(request)

		var migrated = 0
		for obj in objects {
			let cdNode = obj.value(forKey: nodeKey) as? NSManagedObject
			guard let sdNode = cdNode.flatMap({ nodeMap[$0.objectID] }) else {
				continue
			}
			if state.preexistingNodeNums.contains(sdNode.num) {
				// Rescue merge: this node survived the failed migration; its current config
				// reflects the radio's live state and must not be replaced by the legacy one.
				continue
			}
			let sd = try make(obj)
			wireNode(sdNode, sd)
			sdContext.insert(sd)
			migrated += 1
		}
		Logger.data.info("⬆️ migrated \(migrated) of \(objects.count) \(entityName) records")
	}
}

// MARK: - Retry fingerprints

private struct MessageUserLink {
	let fromNum: Int64?
	let toNum: Int64?
}

private struct PositionFingerprint: Hashable {
	let nodeNum: Int64?
	let altitude: Int32
	let heading: Int32
	let latest: Bool
	let latitudeI: Int32
	let longitudeI: Int32
	let precisionBits: Int32
	let rssi: Int32
	let satsInView: Int32
	let seqNo: Int32
	let snr: UInt32
	let speed: Int32
	let time: Date?

	init(_ position: PositionEntity) {
		nodeNum = position.nodePosition?.num
		altitude = position.altitude
		heading = position.heading
		latest = position.latest
		latitudeI = position.latitudeI
		longitudeI = position.longitudeI
		precisionBits = position.precisionBits
		rssi = position.rssi
		satsInView = position.satsInView
		seqNo = position.seqNo
		snr = position.snr.bitPattern
		speed = position.speed
		time = position.time
	}

	init(coreDataObject object: NSManagedObject, nodeNum: Int64?) {
		self.nodeNum = nodeNum
		altitude = (object.value(forKey: "altitude") as? Int32) ?? 0
		heading = (object.value(forKey: "heading") as? Int32) ?? 0
		latest = (object.value(forKey: "latest") as? Bool) ?? false
		latitudeI = (object.value(forKey: "latitudeI") as? Int32) ?? 0
		longitudeI = (object.value(forKey: "longitudeI") as? Int32) ?? 0
		precisionBits = (object.value(forKey: "precisionBits") as? Int32) ?? 32
		rssi = (object.value(forKey: "rssi") as? Int32) ?? 0
		satsInView = (object.value(forKey: "satsInView") as? Int32) ?? 0
		seqNo = (object.value(forKey: "seqNo") as? Int32) ?? 0
		snr = ((object.value(forKey: "snr") as? Float) ?? 0).bitPattern
		speed = (object.value(forKey: "speed") as? Int32) ?? 0
		time = object.value(forKey: "time") as? Date
	}
}

private struct TelemetryFingerprint: Hashable {
	let nodeNum: Int64?
	let metricsType: Int32
	let numOnlineNodes: Int32
	let numPacketsRx: Int32
	let numPacketsRxBad: Int32
	let numPacketsTx: Int32
	let numRxDupe: Int32
	let numTotalNodes: Int32
	let numTxRelay: Int32
	let numTxRelayCanceled: Int32
	let time: Date?
	let airUtilTx: UInt32?
	let barometricPressure: UInt32?
	let batteryLevel: Int32?
	let channelUtilization: UInt32?
	let current: UInt32?
	let gasResistance: UInt32?
	let iaq: Int32?
	let irLux: UInt32?
	let lux: UInt32?
	let powerCh1Current: UInt32?
	let powerCh1Voltage: UInt32?
	let powerCh2Current: UInt32?
	let powerCh2Voltage: UInt32?
	let powerCh3Current: UInt32?
	let powerCh3Voltage: UInt32?
	let radiation: UInt32?
	let rainfall1H: UInt32?
	let rainfall24H: UInt32?
	let relativeHumidity: UInt32?
	let rssi: Int32?
	let snr: UInt32?
	let soilMoisture: UInt32?
	let soilTemperature: UInt32?
	let temperature: UInt32?
	let uptimeSeconds: Int32?
	let uvLux: UInt32?
	let voltage: UInt32?
	let weight: UInt32?
	let whiteLux: UInt32?
	let windDirection: Int32?
	let windGust: UInt32?
	let windLull: UInt32?
	let windSpeed: UInt32?

	init(_ telemetry: TelemetryEntity) {
		nodeNum = telemetry.nodeTelemetry?.num
		metricsType = telemetry.metricsType
		numOnlineNodes = telemetry.numOnlineNodes
		numPacketsRx = telemetry.numPacketsRx
		numPacketsRxBad = telemetry.numPacketsRxBad
		numPacketsTx = telemetry.numPacketsTx
		numRxDupe = telemetry.numRxDupe
		numTotalNodes = telemetry.numTotalNodes
		numTxRelay = telemetry.numTxRelay
		numTxRelayCanceled = telemetry.numTxRelayCanceled
		time = telemetry.time
		airUtilTx = telemetry.airUtilTx?.bitPattern
		barometricPressure = telemetry.barometricPressure?.bitPattern
		batteryLevel = telemetry.batteryLevel
		channelUtilization = telemetry.channelUtilization?.bitPattern
		current = telemetry.current?.bitPattern
		gasResistance = telemetry.gasResistance?.bitPattern
		iaq = telemetry.iaq
		irLux = telemetry.irLux?.bitPattern
		lux = telemetry.lux?.bitPattern
		powerCh1Current = telemetry.powerCh1Current?.bitPattern
		powerCh1Voltage = telemetry.powerCh1Voltage?.bitPattern
		powerCh2Current = telemetry.powerCh2Current?.bitPattern
		powerCh2Voltage = telemetry.powerCh2Voltage?.bitPattern
		powerCh3Current = telemetry.powerCh3Current?.bitPattern
		powerCh3Voltage = telemetry.powerCh3Voltage?.bitPattern
		radiation = telemetry.radiation?.bitPattern
		rainfall1H = telemetry.rainfall1H?.bitPattern
		rainfall24H = telemetry.rainfall24H?.bitPattern
		relativeHumidity = telemetry.relativeHumidity?.bitPattern
		rssi = telemetry.rssi
		snr = telemetry.snr?.bitPattern
		soilMoisture = telemetry.soilMoisture
		soilTemperature = telemetry.soilTemperature?.bitPattern
		temperature = telemetry.temperature?.bitPattern
		uptimeSeconds = telemetry.uptimeSeconds
		uvLux = telemetry.uvLux?.bitPattern
		voltage = telemetry.voltage?.bitPattern
		weight = telemetry.weight?.bitPattern
		whiteLux = telemetry.whiteLux?.bitPattern
		windDirection = telemetry.windDirection
		windGust = telemetry.windGust?.bitPattern
		windLull = telemetry.windLull?.bitPattern
		windSpeed = telemetry.windSpeed?.bitPattern
	}

	init(coreDataObject object: NSManagedObject, nodeNum: Int64?) {
		self.nodeNum = nodeNum
		metricsType = (object.value(forKey: "metricsType") as? Int32) ?? 0
		numOnlineNodes = (object.value(forKey: "numOnlineNodes") as? Int32) ?? 0
		numPacketsRx = (object.value(forKey: "numPacketsRx") as? Int32) ?? 0
		numPacketsRxBad = (object.value(forKey: "numPacketsRxBad") as? Int32) ?? 0
		numPacketsTx = (object.value(forKey: "numPacketsTx") as? Int32) ?? 0
		numRxDupe = (object.value(forKey: "numRxDupe") as? Int32) ?? 0
		numTotalNodes = (object.value(forKey: "numTotalNodes") as? Int32) ?? 0
		numTxRelay = (object.value(forKey: "numTxRelay") as? Int32) ?? 0
		numTxRelayCanceled = (object.value(forKey: "numTxRelayCanceled") as? Int32) ?? 0
		time = object.value(forKey: "time") as? Date
		airUtilTx = (object.value(forKey: "airUtilTx") as? Float)?.bitPattern
		barometricPressure = (object.value(forKey: "barometricPressure") as? Float)?.bitPattern
		batteryLevel = object.value(forKey: "batteryLevel") as? Int32
		channelUtilization = (object.value(forKey: "channelUtilization") as? Float)?.bitPattern
		current = (object.value(forKey: "current") as? Float)?.bitPattern
		gasResistance = (object.value(forKey: "gasResistance") as? Float)?.bitPattern
		iaq = object.value(forKey: "iaq") as? Int32
		irLux = (object.value(forKey: "irLux") as? Float)?.bitPattern
		lux = (object.value(forKey: "lux") as? Float)?.bitPattern
		powerCh1Current = (object.value(forKey: "powerCh1Current") as? Float)?.bitPattern
		powerCh1Voltage = (object.value(forKey: "powerCh1Voltage") as? Float)?.bitPattern
		powerCh2Current = (object.value(forKey: "powerCh2Current") as? Float)?.bitPattern
		powerCh2Voltage = (object.value(forKey: "powerCh2Voltage") as? Float)?.bitPattern
		powerCh3Current = (object.value(forKey: "powerCh3Current") as? Float)?.bitPattern
		powerCh3Voltage = (object.value(forKey: "powerCh3Voltage") as? Float)?.bitPattern
		radiation = (object.value(forKey: "radiation") as? Float)?.bitPattern
		rainfall1H = (object.value(forKey: "rainfall1H") as? Float)?.bitPattern
		rainfall24H = (object.value(forKey: "rainfall24H") as? Float)?.bitPattern
		relativeHumidity = (object.value(forKey: "relativeHumidity") as? Float)?.bitPattern
		rssi = object.value(forKey: "rssi") as? Int32
		snr = (object.value(forKey: "snr") as? Float)?.bitPattern
		soilMoisture = (object.value(forKey: "soilMoisture") as? Int32).map(UInt32.init(bitPattern:))
		soilTemperature = (object.value(forKey: "soilTemperature") as? Float)?.bitPattern
		temperature = (object.value(forKey: "temperature") as? Float)?.bitPattern
		uptimeSeconds = object.value(forKey: "uptimeSeconds") as? Int32
		uvLux = (object.value(forKey: "uvLux") as? Float)?.bitPattern
		voltage = (object.value(forKey: "voltage") as? Float)?.bitPattern
		weight = (object.value(forKey: "weight") as? Float)?.bitPattern
		whiteLux = (object.value(forKey: "whiteLux") as? Float)?.bitPattern
		windDirection = object.value(forKey: "windDirection") as? Int32
		windGust = (object.value(forKey: "windGust") as? Float)?.bitPattern
		windLull = (object.value(forKey: "windLull") as? Float)?.bitPattern
		windSpeed = (object.value(forKey: "windSpeed") as? Float)?.bitPattern
	}
}

// MARK: - Store retirement

private extension CoreDataMigrationService {

	/// Renames the SQLite store family so the migration never runs again.
	/// Existing destination files make retry safe after an interrupted partial move.
	static func retireLegacyStore(
		at locations: StoreLocations,
		options: MigrationOptions
	) throws {
		let fm = FileManager.default
		// The source store can recreate WAL/SHM files when a retry opens it.
		// Persist a marker before the first move so those regenerated sidecars can
		// be distinguished from an unrelated backup-file collision.
		let storeMembers: [(suffix: String, member: StoreMember)] = [
			("-wal", .wal),
			("-shm", .shm),
			("", .main)
		]
		if !fm.fileExists(atPath: locations.retirementMarkerURL.path) {
			for storeMember in storeMembers {
				let backupFile = sidecar(of: locations.backupStoreURL, suffix: storeMember.suffix)
				if fm.fileExists(atPath: backupFile.path) {
					throw MigrationError.backupAlreadyExists(backupFile.lastPathComponent)
				}
			}
			try Data().write(to: locations.retirementMarkerURL, options: .atomic)
		}

		// Keep the legacy main file in place until both sidecars are safe. Retry
		// therefore continues to see an unfinished migration after any sidecar move.
		for storeMember in storeMembers {
			let srcFile = sidecar(of: locations.legacyStoreURL, suffix: storeMember.suffix)
			let dstFile = sidecar(of: locations.backupStoreURL, suffix: storeMember.suffix)
			guard fm.fileExists(atPath: srcFile.path) else { continue }
			if fm.fileExists(atPath: dstFile.path) {
				try fm.removeItem(at: srcFile)
			} else {
				try fm.moveItem(at: srcFile, to: dstFile)
			}
			try options.checkpoint(.afterRetirementMove(storeMember.member))
		}
		try fm.removeItem(at: locations.retirementMarkerURL)
	}
}

// MARK: - Errors

enum MigrationError: LocalizedError {
	case modelNotFound
	case modelLoadFailed
	case backupAlreadyExists(String)
	case storeFamilyConflict(String)

	var errorDescription: String? {
		switch self {
		case .modelNotFound:
			return "Legacy Core Data model file not found in bundle."
		case .modelLoadFailed:
			return "Failed to load legacy Core Data model from bundle."
		case let .backupAlreadyExists(fileName):
			return "Cannot retire the legacy store because \(fileName) already exists."
		case let .storeFamilyConflict(fileName):
			return "Cannot move the legacy store because \(fileName) already exists."
		}
	}
}
