//
//  CoreDataMigrationService.swift
//  Meshtastic
//
//  One-time migration from the legacy Core Data store (shipped in 2.7.12 and
//  earlier) into the SwiftData store.
//
//  Migration is triggered automatically by PersistenceController when it detects
//  an existing Core Data store at the expected URL.  After a successful run the
//  old store is renamed to `Meshtastic-coredata-backup.sqlite` so the migration
//  never runs again.
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

	/// Renames the App-Store Core Data store out of the way so that SwiftData
	/// can create a fresh store at the same path without clobbering user data.
	///
	/// Must be called **before** the SwiftData `ModelContainer` is initialised.
	/// Safe to call on every launch — it is a no-op when:
	///   - The candidate file does not exist, or
	///   - The candidate file is not a Core Data store, or
	///   - The renamed legacy file already exists (rename already done).
	static func prepareForMigration() {
		let fm = FileManager.default
		// Nothing to do if the candidate is already gone or the rename is done.
		guard fm.fileExists(atPath: candidateStoreURL.path),
			  !fm.fileExists(atPath: legacyStoreURL.path) else { return }
		// Only rename if the file is actually a Core Data store.
		guard isCoreDataStore(at: candidateStoreURL) else { return }

		Logger.data.info("⬆️ CoreDataMigrationService: renaming Core Data store before SwiftData init")
		for suffix in ["", "-shm", "-wal"] {
			let src = candidateStoreURL
				.deletingPathExtension()
				.appendingPathExtension("sqlite\(suffix)")
			let dst = legacyStoreURL
				.deletingPathExtension()
				.appendingPathExtension("sqlite\(suffix)")
			try? fm.moveItem(at: src, to: dst)
		}
	}

	/// Returns `true` when a renamed legacy Core Data store exists and has not
	/// yet been migrated into SwiftData.
	static func legacyStoreExists() -> Bool {
		FileManager.default.fileExists(atPath: legacyStoreURL.path)
	}

	/// Performs the full Core Data → SwiftData migration.
	///
	/// - Parameter swiftDataContainer: The already-initialised SwiftData
	///   `ModelContainer` that data should be written into.
	/// - Throws: Any error encountered while reading Core Data or writing
	///   SwiftData.  The caller is responsible for surfacing this to the user
	///   rather than silently destroying data.
	@MainActor
	static func migrate(into swiftDataContainer: ModelContainer) throws {
		Logger.data.info("⬆️ CoreDataMigrationService: beginning legacy migration")

		let coreDataContainer = try makeCoreDataContainer()
		let cdContext = coreDataContainer.viewContext
		cdContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

		let sdContext = swiftDataContainer.mainContext

		// ── Phase 1: nodes, users, info (no inter-entity dependencies) ──────
		let nodeMap   = try migrateNodes(cdContext: cdContext, sdContext: sdContext)
		let userMap   = try migrateUsers(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		let infoMap   = try migrateMyInfos(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)

		// ── Phase 2: entities that hang off nodes ────────────────────────────
		try migrateChannels(cdContext: cdContext, sdContext: sdContext, infoMap: infoMap)
		try migratePositions(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateTelemetry(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateBluetoothConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateCannedMessageConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateDeviceConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateDisplayConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateExternalNotifConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateLoRaConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateMQTTConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateNetworkConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migratePositionConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateRangeTestConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateSerialConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)
		try migrateTelemetryConfigs(cdContext: cdContext, sdContext: sdContext, nodeMap: nodeMap)

		// ── Phase 3: messages (depend on user map) ───────────────────────────
		try migrateMessages(cdContext: cdContext, sdContext: sdContext, userMap: userMap)

		// ── Persist ──────────────────────────────────────────────────────────
		try sdContext.save()
		Logger.data.info("⬆️ CoreDataMigrationService: SwiftData save complete")

		// ── Rename old store so this migration never runs again ──────────────
		renameOldStore()
		Logger.data.info("⬆️ CoreDataMigrationService: legacy store renamed – migration complete")
	}
}

// MARK: - Store URLs

private extension CoreDataMigrationService {

	/// The original path used by the App Store (Core Data) build.
	/// SwiftData also uses this path, so we must rename before SwiftData opens.
	static var candidateStoreURL: URL {
		applicationSupportURL.appendingPathComponent("Meshtastic.sqlite")
	}

	/// The URL we rename the Core Data store to before SwiftData opens.
	/// `legacyStoreExists()` checks this file, not the candidate.
	static var legacyStoreURL: URL {
		applicationSupportURL.appendingPathComponent("Meshtastic-coredata-legacy.sqlite")
	}

	/// Where we move the legacy store after a successful migration.
	static var backupStoreURL: URL {
		applicationSupportURL.appendingPathComponent("Meshtastic-coredata-backup.sqlite")
	}

	static var applicationSupportURL: URL {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
	}

	/// Returns `true` when the SQLite file at `url` is a Core Data store.
	///
	/// Uses `NSPersistentStoreCoordinator.metadataForPersistentStore` which is
	/// read-only — it does not modify the file.
	static func isCoreDataStore(at url: URL) -> Bool {
		guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
			ofType: NSSQLiteStoreType,
			at: url
		) else { return false }
		return metadata[NSStoreModelVersionHashesKey] != nil
	}
}

// MARK: - Core Data container bootstrap

private extension CoreDataMigrationService {

	/// Creates an `NSPersistentContainer` that opens the *existing* Core Data
	/// store using the bundled `.xcdatamodeld` model.  Automatic lightweight
	/// migration is enabled so any minor schema drift across device upgrades
	/// is handled transparently.
	static func makeCoreDataContainer() throws -> NSPersistentContainer {
		guard let modelURL = Bundle.main.url(
			forResource: "Meshtastic",
			withExtension: "momd"
		) else {
			throw MigrationError.modelNotFound
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
		sdContext: ModelContext
	) throws -> [NSManagedObjectID: NodeInfoEntity] {
		let request = NSFetchRequest<NSManagedObject>(entityName: "NodeInfoEntity")
		let objects = try cdContext.fetch(request)
		var map = [NSManagedObjectID: NodeInfoEntity]()

		for obj in objects {
			let sd = NodeInfoEntity()
			sd.bleName      = obj.value(forKey: "bleName") as? String
			sd.channel      = (obj.value(forKey: "channel") as? Int32) ?? 0
			sd.id           = (obj.value(forKey: "id") as? Int64) ?? 0
			sd.lastHeard    = obj.value(forKey: "lastHeard") as? Date ?? Date()
			sd.num          = (obj.value(forKey: "num") as? Int64) ?? 0
			sd.snr          = (obj.value(forKey: "snr") as? Float) ?? 0
			sdContext.insert(sd)
			map[obj.objectID] = sd
		}
		Logger.data.info("⬆️ migrated \(objects.count) NodeInfoEntity records")
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

		for obj in objects {
			let sd = UserEntity()
			sd.hwModel   = obj.value(forKey: "hwModel") as? String
			sd.isLicensed = (obj.value(forKey: "isLicensed") as? Bool) ?? false
			sd.longName  = obj.value(forKey: "longName") as? String
			sd.num       = (obj.value(forKey: "num") as? Int64) ?? 0
			sd.shortName = obj.value(forKey: "shortName") as? String
			sd.userId    = obj.value(forKey: "userId") as? String
			// macaddr existed in Core Data but is intentionally dropped in SwiftData

			if let cdNode = obj.value(forKey: "userNode") as? NSManagedObject,
			   let sdNode = nodeMap[cdNode.objectID] {
				sd.userNode = sdNode
			}
			sdContext.insert(sd)
			map[obj.objectID] = sd
		}
		Logger.data.info("⬆️ migrated \(objects.count) UserEntity records")
		return map
	}

	// MARK: MyInfoEntity

	static func migrateMyInfos(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws -> [NSManagedObjectID: MyInfoEntity] {
		let request = NSFetchRequest<NSManagedObject>(entityName: "MyInfoEntity")
		let objects = try cdContext.fetch(request)
		var map = [NSManagedObjectID: MyInfoEntity]()

		for obj in objects {
			let sd = MyInfoEntity()
			sd.bleName         = obj.value(forKey: "bleName") as? String
			sd.minAppVersion   = (obj.value(forKey: "minAppVersion") as? Int32) ?? 0
			sd.myNodeNum       = (obj.value(forKey: "myNodeNum") as? Int64) ?? 0
			sd.peripheralId    = obj.value(forKey: "peripheralId") as? String
			sd.rebootCount     = (obj.value(forKey: "rebootCount") as? Int32) ?? 0

			if let cdNode = obj.value(forKey: "myInfoNode") as? NSManagedObject,
			   let sdNode = nodeMap[cdNode.objectID] {
				sd.myInfoNode = sdNode
			}
			sdContext.insert(sd)
			map[obj.objectID] = sd
		}
		Logger.data.info("⬆️ migrated \(objects.count) MyInfoEntity records")
		return map
	}

	// MARK: ChannelEntity

	static func migrateChannels(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		infoMap: [NSManagedObjectID: MyInfoEntity]
	) throws {
		let request = NSFetchRequest<NSManagedObject>(entityName: "ChannelEntity")
		let objects = try cdContext.fetch(request)

		for obj in objects {
			let sd = ChannelEntity()
			sd.downlinkEnabled = (obj.value(forKey: "downlinkEnabled") as? Bool) ?? false
			sd.id              = (obj.value(forKey: "id") as? Int32) ?? 0
			sd.index           = (obj.value(forKey: "index") as? Int32) ?? 0
			sd.name            = obj.value(forKey: "name") as? String
			sd.psk             = obj.value(forKey: "psk") as? Data
			sd.role            = (obj.value(forKey: "role") as? Int32) ?? 0
			sd.uplinkEnabled   = (obj.value(forKey: "uplinkEnabled") as? Bool) ?? false

			if let cdInfo = obj.value(forKey: "myInfoChannel") as? NSManagedObject,
			   let sdInfo = infoMap[cdInfo.objectID] {
				sd.myInfoChannel = sdInfo
			}
			sdContext.insert(sd)
		}
		Logger.data.info("⬆️ migrated \(objects.count) ChannelEntity records")
	}

	// MARK: MessageEntity

	static func migrateMessages(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		userMap: [NSManagedObjectID: UserEntity]
	) throws {
		let request = NSFetchRequest<NSManagedObject>(entityName: "MessageEntity")
		let objects = try cdContext.fetch(request)

		for obj in objects {
			let sd = MessageEntity()
			sd.ackError        = (obj.value(forKey: "ackError") as? Int32) ?? 0
			sd.ackSNR          = (obj.value(forKey: "ackSNR") as? Float) ?? 0
			sd.ackTimestamp    = (obj.value(forKey: "ackTimestamp") as? Int32) ?? 0
			sd.admin           = (obj.value(forKey: "admin") as? Bool) ?? false
			sd.adminDescription = obj.value(forKey: "adminDescription") as? String
			sd.channel         = (obj.value(forKey: "channel") as? Int32) ?? 0
			sd.isEmoji         = (obj.value(forKey: "isEmoji") as? Bool) ?? false
			sd.messageId       = (obj.value(forKey: "messageId") as? Int64) ?? 0
			sd.messagePayload  = obj.value(forKey: "messagePayload") as? String
			sd.messageTimestamp = (obj.value(forKey: "messageTimestamp") as? Int32) ?? 0
			sd.receivedACK     = (obj.value(forKey: "receivedACK") as? Bool) ?? false
			sd.replyID         = (obj.value(forKey: "replyID") as? Int64) ?? 0
			sd.snr             = (obj.value(forKey: "snr") as? Float) ?? 0

			if let cdFrom = obj.value(forKey: "fromUser") as? NSManagedObject,
			   let sdFrom = userMap[cdFrom.objectID] {
				sd.fromUser = sdFrom
			}
			if let cdTo = obj.value(forKey: "toUser") as? NSManagedObject,
			   let sdTo = userMap[cdTo.objectID] {
				sd.toUser = sdTo
			}
			sdContext.insert(sd)
		}
		Logger.data.info("⬆️ migrated \(objects.count) MessageEntity records")
	}

	// MARK: PositionEntity

	static func migratePositions(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		let request = NSFetchRequest<NSManagedObject>(entityName: "PositionEntity")
		let objects = try cdContext.fetch(request)

		for obj in objects {
			let sd = PositionEntity()
			sd.altitude    = (obj.value(forKey: "altitude") as? Int32) ?? 0
			sd.heading     = (obj.value(forKey: "heading") as? Int32) ?? 0
			sd.latitudeI   = (obj.value(forKey: "latitudeI") as? Int32) ?? 0
			sd.longitudeI  = (obj.value(forKey: "longitudeI") as? Int32) ?? 0
			sd.satsInView  = (obj.value(forKey: "satsInView") as? Int32) ?? 0
			sd.seqNo       = (obj.value(forKey: "seqNo") as? Int32) ?? 0
			sd.snr         = (obj.value(forKey: "snr") as? Float) ?? 0
			sd.speed       = (obj.value(forKey: "speed") as? Int32) ?? 0
			sd.time        = obj.value(forKey: "time") as? Date

			if let cdNode = obj.value(forKey: "nodePosition") as? NSManagedObject,
			   let sdNode = nodeMap[cdNode.objectID] {
				sd.nodePosition = sdNode
			}
			sdContext.insert(sd)
		}
		Logger.data.info("⬆️ migrated \(objects.count) PositionEntity records")
	}

	// MARK: TelemetryEntity

	static func migrateTelemetry(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		let request = NSFetchRequest<NSManagedObject>(entityName: "TelemetryEntity")
		let objects = try cdContext.fetch(request)

		for obj in objects {
			let sd = TelemetryEntity()
			sd.metricsType          = (obj.value(forKey: "metricsType") as? Int32) ?? 0
			sd.time                 = obj.value(forKey: "time") as? Date
			sd.airUtilTx            = obj.value(forKey: "airUtilTx") as? Float
			sd.barometricPressure   = obj.value(forKey: "barometricPressure") as? Float
			sd.batteryLevel         = obj.value(forKey: "batteryLevel") as? Int32
			sd.channelUtilization   = obj.value(forKey: "channelUtilization") as? Float
			sd.current              = obj.value(forKey: "current") as? Float
			sd.gasResistance        = obj.value(forKey: "gasResistance") as? Float
			sd.relativeHumidity     = obj.value(forKey: "relativeHumidity") as? Float
			sd.temperature          = obj.value(forKey: "temperature") as? Float
			sd.voltage              = obj.value(forKey: "voltage") as? Float

			if let cdNode = obj.value(forKey: "nodeTelemetry") as? NSManagedObject,
			   let sdNode = nodeMap[cdNode.objectID] {
				sd.nodeTelemetry = sdNode
			}
			sdContext.insert(sd)
		}
		Logger.data.info("⬆️ migrated \(objects.count) TelemetryEntity records")
	}

	// MARK: Config entities

	static func migrateBluetoothConfigs(
		cdContext: NSManagedObjectContext,
		sdContext: ModelContext,
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "BluetoothConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "bluetoothConfigNode",
			nodeMap: nodeMap
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "CannedMessageConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "cannedMessagesConfigNode",
			nodeMap: nodeMap
		) { obj -> CannedMessageConfigEntity in
			let sd = CannedMessageConfigEntity()
			sd.enabled                = (obj.value(forKey: "enabled") as? Bool) ?? false
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "DeviceConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "deviceConfigNode",
			nodeMap: nodeMap
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "DisplayConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "displayConfigNode",
			nodeMap: nodeMap
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "ExternalNotificationConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "externalNotificationConfigNode",
			nodeMap: nodeMap
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "LoRaConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "loRaConfigNode",
			nodeMap: nodeMap
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "MQTTConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "mqttConfigNode",
			nodeMap: nodeMap
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "NetworkConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "networkConfigNode",
			nodeMap: nodeMap
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "PositionConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "positionConfigNode",
			nodeMap: nodeMap
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "RangeTestConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "rangeTestConfigNode",
			nodeMap: nodeMap
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "SerialConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "serialConfigNode",
			nodeMap: nodeMap
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
		nodeMap: [NSManagedObjectID: NodeInfoEntity]
	) throws {
		try migrateConfigEntity(
			entityName: "TelemetryConfigEntity",
			cdContext: cdContext,
			sdContext: sdContext,
			nodeKey: "telemetryConfigNode",
			nodeMap: nodeMap
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
		make: (NSManagedObject) throws -> T,
		wireNode: (NodeInfoEntity, T) -> Void
	) throws {
		let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
		let objects = try cdContext.fetch(request)

		for obj in objects {
			let sd = try make(obj)
			if let cdNode = obj.value(forKey: nodeKey) as? NSManagedObject,
			   let sdNode = nodeMap[cdNode.objectID] {
				wireNode(sdNode, sd)
			}
			sdContext.insert(sd)
		}
		Logger.data.info("⬆️ migrated \(objects.count) \(entityName) records")
	}
}

// MARK: - Store rename

private extension CoreDataMigrationService {

	/// Renames the three SQLite sidecar files so the migration never runs again.
	static func renameOldStore() {
		let fm = FileManager.default
		let src = legacyStoreURL
		let dst = backupStoreURL

		// SQLite has three files: .sqlite, .sqlite-shm, .sqlite-wal
		for suffix in ["", "-shm", "-wal"] {
			let srcFile = src.deletingPathExtension().appendingPathExtension("sqlite\(suffix)")
			let dstFile = dst.deletingPathExtension().appendingPathExtension("sqlite\(suffix)")
			try? fm.moveItem(at: srcFile, to: dstFile)
		}
	}
}

// MARK: - Errors

enum MigrationError: LocalizedError {
	case modelNotFound
	case modelLoadFailed

	var errorDescription: String? {
		switch self {
		case .modelNotFound:  return "Legacy Core Data model file not found in bundle."
		case .modelLoadFailed: return "Failed to load legacy Core Data model from bundle."
		}
	}
}
