//
//  Persistence.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/28/21.
//

import SwiftData
import OSLog
import Foundation

@MainActor
class PersistenceController {

	static let shared: PersistenceController = {
		let isTestEnvironment = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
		return PersistenceController(inMemory: isTestEnvironment)
	}()

	static var preview: PersistenceController = {
		let result = PersistenceController(inMemory: true, storeName: "MeshtasticPreview")
		let context = result.container.mainContext
		for _ in 0..<10 {
			let newItem = NodeInfoEntity()
			newItem.lastHeard = Date()
			context.insert(newItem)
		}
		return result
	}()

	private(set) var container: ModelContainer

	var context: ModelContext {
		container.mainContext
	}

	private static func removeStoreFiles(at storeURL: URL) {
		let fm = FileManager.default
		let storeFiles = [
			storeURL,
			URL(fileURLWithPath: storeURL.path + "-shm"),
			URL(fileURLWithPath: storeURL.path + "-wal")
		]

		for url in storeFiles where fm.fileExists(atPath: url.path) {
			do {
				try fm.removeItem(at: url)
			} catch {
				Logger.data.error("📈 [PerfSeed] Failed to remove existing store file \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	init(inMemory: Bool = false, storeName: String = "Meshtastic") {
		let isTestEnvironment = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
		let schema = Schema(versionedSchema: MeshtasticSchema.current)

		let config = ModelConfiguration(
			storeName,
			schema: schema,
			isStoredInMemoryOnly: inMemory,
			allowsSave: true
		)

#if DEBUG
		if !inMemory && !isTestEnvironment && PerformanceSeedData.configuration?.resetStore == true {
			Self.removeStoreFiles(at: config.url)
		}
#endif

		// ── Step 0: guard Core Data store from being clobbered ───────────────
		// Both the App Store (Core Data) build and this (SwiftData) build use
		// "Meshtastic.sqlite".  If we let SwiftData open the file first it will
		// corrupt the Core Data content.  Rename it out of the way so SwiftData
		// creates a fresh store; migration reads from the renamed file below.
		if !inMemory && !isTestEnvironment {
			CoreDataMigrationService.prepareForMigration()
		}

		// ── Step 1: build the SwiftData container ────────────────────────────
		do {
			if inMemory {
				container = try ModelContainer(
					for: schema,
					configurations: config
				)
			} else {
				container = try ModelContainer(
					for: schema,
					migrationPlan: MeshtasticMigrationPlan.self,
					configurations: config
				)
			}
			container.mainContext.autosaveEnabled = false
			Logger.data.info("💾 SwiftData store initialized successfully")
		} catch {
			// The store could not be opened (e.g. a Core Data file that
			// prepareForMigration() did not rename, or a corrupt store from a
			// previous build).  Log the error, rename the broken file so it is
			// preserved for diagnosis, and retry with a fresh empty store.
			// A fatalError here would leave users permanently unable to open
			// the app, so we recover instead and accept the data loss.
			Logger.data.critical("💾 SwiftData store failed to open, attempting recovery: \(error.localizedDescription, privacy: .public)")
			let fm = FileManager.default
			let base = config.url.deletingPathExtension()
			let broken = base
				.deletingLastPathComponent()
				.appendingPathComponent(base.lastPathComponent + "-broken-\(Int(Date().timeIntervalSince1970))")
			for ext in ["sqlite", "sqlite-shm", "sqlite-wal"] {
				try? fm.moveItem(
					at: base.appendingPathExtension(ext),
					to: broken.appendingPathExtension(ext)
				)
			}
			do {
				container = try ModelContainer(
					for: schema,
					migrationPlan: MeshtasticMigrationPlan.self,
					configurations: config
				)
				container.mainContext.autosaveEnabled = false
				Logger.data.warning("💾 SwiftData store recreated after recovery — local data has been reset on this device")
			} catch let recoveryError {
				fatalError("💾 SwiftData store unrecoverable even after reset: \(recoveryError.localizedDescription)")
			}
		}

		// ── Step 2: one-time Core Data → SwiftData migration ─────────────────
		// Runs only when upgrading from 2.7.12 (or earlier) which used Core Data.
		guard !inMemory, !isTestEnvironment else { return }
		if CoreDataMigrationService.legacyStoreExists() {
			do {
				try CoreDataMigrationService.migrate(into: container)
			} catch {
				// Log but do not crash — the SwiftData store is usable even if
				// migration fails; the user will simply start fresh on this device.
				Logger.data.error("⬆️ CoreDataMigrationService failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	@MainActor
	public func clearDatabase(includeRoutes: Bool = true) {
		do {
			let hardwareDevices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
			for device in hardwareDevices {
				device.tags.removeAll()
			}
			if container.mainContext.hasChanges {
				try container.mainContext.save()
			}

			// Delete entities that are on the inverse side of many-to-many
			// relationships first to avoid constraint trigger violations.
			try container.mainContext.delete(model: DeviceHardwareTagEntity.self)
			try container.mainContext.delete(model: DeviceHardwareImageEntity.self)

			for modelType in MeshtasticSchema.allModels {
				if !includeRoutes && (modelType == RouteEntity.self || modelType == LocationEntity.self) {
					continue
				}
				if modelType == DeviceHardwareTagEntity.self || modelType == DeviceHardwareImageEntity.self {
					continue // already deleted above
				}
				try container.mainContext.delete(model: modelType)
			}
			try container.mainContext.save()
			Logger.data.error("SwiftData database truncated. All app data has been erased.")
		} catch {
			Logger.data.error("Failed to clear SwiftData database: \(error.localizedDescription, privacy: .public)")
		}
	}
}

#if DEBUG
@MainActor
struct PerformanceSeedConfiguration {
	let nodeCount: Int
	let telemetryHistoryPerNode: Int
	let positionHistoryPerNode: Int
	let directMessageCount: Int
	let channelMessageCount: Int
	let resetStore: Bool
	let compactNodeList: Bool
	let disableDiscovery: Bool
	let initialTab: NavigationState.Tab
}

@MainActor
enum PerformanceSeedData {
	static var configuration: PerformanceSeedConfiguration? {
		let environment = ProcessInfo.processInfo.environment
		let arguments = ProcessInfo.processInfo.arguments
		let enabled = arguments.contains("--meshtastic-perf-seed") || environment["MESHTASTIC_PERF_SEED_NODES"] != nil
		guard enabled else { return nil }

		return PerformanceSeedConfiguration(
			nodeCount: integerValue("MESHTASTIC_PERF_SEED_NODES", environment: environment, defaultValue: 5_000),
			telemetryHistoryPerNode: integerValue("MESHTASTIC_PERF_TELEMETRY_HISTORY", environment: environment, defaultValue: 3),
			positionHistoryPerNode: integerValue("MESHTASTIC_PERF_POSITION_HISTORY", environment: environment, defaultValue: 3),
			directMessageCount: integerValue("MESHTASTIC_PERF_DIRECT_MESSAGES", environment: environment, defaultValue: 0),
			channelMessageCount: integerValue("MESHTASTIC_PERF_CHANNEL_MESSAGES", environment: environment, defaultValue: 0),
			resetStore: boolValue("MESHTASTIC_PERF_RESET_STORE", environment: environment) || arguments.contains("--meshtastic-perf-reset"),
			compactNodeList: boolValue("MESHTASTIC_PERF_COMPACT_LIST", environment: environment) || arguments.contains("--meshtastic-perf-compact-list"),
			disableDiscovery: !boolValue("MESHTASTIC_PERF_ENABLE_DISCOVERY", environment: environment),
			initialTab: arguments.contains("--meshtastic-perf-start-map") ? .map : .nodes
		)
	}

	static func prepareDefaults(for configuration: PerformanceSeedConfiguration) {
		UserDefaults.firstLaunch = false
		UserDefaults.showDeviceOnboarding = false
		UserDefaults.usageDataAndCrashReporting = false
		UserDefaults.autoconnectOnDiscovery = false
		UserDefaults.standard.set(
			configuration.compactNodeList ? NodeListDensity.compact.rawValue : NodeListDensity.standard.rawValue,
			forKey: "nodeListDensity"
		)
		UserDefaults.standard.set(Int(0x0A00_0000), forKey: "preferredPeripheralNum")
	}

	static func seedIfNeeded(using controller: PersistenceController, configuration: PerformanceSeedConfiguration, router: Router) {
		let start = Date()
		let context = controller.container.mainContext

		let requestedMessageCount = configuration.directMessageCount + configuration.channelMessageCount
		if configuration.resetStore {
			controller.clearDatabase()
		} else if existingNodeCount(context: context) >= configuration.nodeCount {
			if requestedMessageCount > 0 && existingMessageCount(context: context) < requestedMessageCount {
				seedMessageHistory(baseNodeNum: 0x0A00_0000, now: Date(), configuration: configuration, context: context)
				try? context.save()
			}
			router.selectedTab = configuration.initialTab
			Logger.data.info("📈 [PerfSeed] Existing large mesh seed found; skipping reseed")
			return
		}

		Logger.data.info("📈 [PerfSeed] Seeding \(configuration.nodeCount, privacy: .public) nodes, \(configuration.telemetryHistoryPerNode, privacy: .public) telemetry samples/type, \(configuration.positionHistoryPerNode, privacy: .public) positions/node")

		let now = Date()
		let baseNodeNum: Int64 = 0x0A00_0000
		for index in 0..<configuration.nodeCount {
			insertNode(index: index, baseNodeNum: baseNodeNum, now: now, configuration: configuration, context: context)

			if index > 0 && index.isMultiple(of: 500) {
				try? context.save()
				Logger.data.debug("📈 [PerfSeed] Seeded \(index, privacy: .public) nodes")
			}
		}
		seedMessageHistory(baseNodeNum: baseNodeNum, now: now, configuration: configuration, context: context)

		do {
			try context.save()
			router.selectedTab = configuration.initialTab
			let duration = Date().timeIntervalSince(start)
			Logger.data.info("📈 [PerfSeed] Finished seeding \(configuration.nodeCount, privacy: .public) nodes in \(duration, privacy: .public) seconds")
		} catch {
			Logger.data.error("📈 [PerfSeed] Failed to save large mesh seed: \(error.localizedDescription, privacy: .public)")
		}
	}

	private static func existingNodeCount(context: ModelContext) -> Int {
		(try? context.fetchCount(FetchDescriptor<NodeInfoEntity>())) ?? 0
	}

	private static func existingMessageCount(context: ModelContext) -> Int {
		(try? context.fetchCount(FetchDescriptor<MessageEntity>())) ?? 0
	}

	private static func insertNode(
		index: Int,
		baseNodeNum: Int64,
		now: Date,
		configuration: PerformanceSeedConfiguration,
		context: ModelContext
	) {
		let nodeNum = baseNodeNum + Int64(index)
		let node = NodeInfoEntity()
		node.id = nodeNum
		node.num = nodeNum
		node.channel = Int32(index % 8)
		node.favorite = index.isMultiple(of: 19)
		node.firstHeard = now.addingTimeInterval(TimeInterval(-(index % 86_400)))
		node.hopsAway = Int32(index % 8)
		node.ignored = index.isMultiple(of: 97)
		node.lastHeard = now.addingTimeInterval(TimeInterval(-(index % 14_400)))
		node.rssi = Int32(-35 - (index % 85))
		node.snr = Float((index % 32) - 18)
		node.viaMqtt = index.isMultiple(of: 4)

		let user = UserEntity()
		user.num = nodeNum
		user.numString = String(nodeNum)
		user.userId = "!\(nodeNum.toHex())"
		user.longName = "Perf Node \(index)"
		user.shortName = shortName(for: index)
		user.hwModel = hardwareModel(for: index)
		user.hwDisplayName = user.hwModel
		user.role = Int32(index % 12)
		user.pkiEncrypted = index.isMultiple(of: 9)
		user.keyMatch = !index.isMultiple(of: 37)
		user.unmessagable = index.isMultiple(of: 23)
		node.user = user

		let metadata = DeviceMetadataEntity()
		metadata.hwModel = user.hwModel
		metadata.firmwareVersion = "2.7.\(index % 10)"
		metadata.hasBluetooth = true
		metadata.hasWifi = index.isMultiple(of: 5)
		metadata.role = user.role
		metadata.time = node.lastHeard
		node.metadata = metadata

		context.insert(node)
		context.insert(user)
		context.insert(metadata)
		if index == 0 {
			let myInfo = MyInfoEntity()
			myInfo.myNodeNum = nodeNum
			myInfo.registered = true
			myInfo.myInfoNode = node
			context.insert(myInfo)
		}

		insertTelemetry(for: node, index: index, now: now, configuration: configuration, context: context)
		insertPositions(for: node, index: index, now: now, configuration: configuration, context: context)

		if index.isMultiple(of: 25) {
			insertTraceRoute(for: node, index: index, now: now, context: context)
		}
	}

	private static func insertTelemetry(
		for node: NodeInfoEntity,
		index: Int,
		now: Date,
		configuration: PerformanceSeedConfiguration,
		context: ModelContext
	) {
		for sample in 0..<configuration.telemetryHistoryPerNode {
			let timestamp = now.addingTimeInterval(TimeInterval(-(sample * 300 + index % 300)))

			let deviceMetrics = TelemetryEntity()
			deviceMetrics.metricsType = 0
			deviceMetrics.time = timestamp
			deviceMetrics.batteryLevel = Int32((index + sample) % 130)
			deviceMetrics.voltage = 3.3 + Float((index + sample) % 90) / 100
			deviceMetrics.channelUtilization = Float((index + sample) % 100)
			deviceMetrics.airUtilTx = Float((index + sample * 3) % 100) / 10
			deviceMetrics.uptimeSeconds = Int32(index * 60 + sample)
			deviceMetrics.nodeTelemetry = node
			context.insert(deviceMetrics)

			let environmentMetrics = TelemetryEntity()
			environmentMetrics.metricsType = 1
			environmentMetrics.time = timestamp
			environmentMetrics.temperature = 15 + Float((index + sample) % 240) / 10
			environmentMetrics.relativeHumidity = 25 + Float((index + sample * 2) % 70)
			environmentMetrics.barometricPressure = 980 + Float((index + sample) % 70)
			environmentMetrics.gasResistance = Float((index + sample) % 500)
			environmentMetrics.nodeTelemetry = node
			context.insert(environmentMetrics)
		}
	}

	private static func insertPositions(
		for node: NodeInfoEntity,
		index: Int,
		now: Date,
		configuration: PerformanceSeedConfiguration,
		context: ModelContext
	) {
		let baseCoordinate = bayAreaCoordinate(for: index)

		for sample in 0..<configuration.positionHistoryPerNode {
			let position = PositionEntity()
			position.altitude = Int32(5 + (index % 600))
			position.heading = Int32((index * 17 + sample * 23) % 360)
			position.latest = sample == 0
			position.latitudeI = Int32((baseCoordinate.latitude + Double(sample) * 0.0001) * 1e7)
			position.longitudeI = Int32((baseCoordinate.longitude + Double(sample) * 0.0001) * 1e7)
			position.precisionBits = 32
			position.rssi = node.rssi
			position.satsInView = Int32(5 + (index % 8))
			position.seqNo = Int32(sample)
			position.snr = node.snr
			position.speed = Int32(index % 45)
			position.time = now.addingTimeInterval(TimeInterval(-(sample * 180 + index % 180)))
			position.nodePosition = node
			context.insert(position)
		}
	}

	private static func bayAreaCoordinate(for index: Int) -> (latitude: Double, longitude: Double) {
		let latitudeUnit = radicalInverse(index + 1, base: 2)
		let longitudeUnit = radicalInverse(index + 1, base: 3)
		let latitudeJitter = (deterministicUnitValue(index, salt: 0xA076_1D64_78BD_642F) - 0.5) * 0.004
		let longitudeJitter = (deterministicUnitValue(index, salt: 0xE703_7ED1_A0B4_28DB) - 0.5) * 0.004
		return (
			latitude: 36.92 + latitudeUnit * 1.36 + latitudeJitter,
			longitude: -122.75 + longitudeUnit * 1.20 + longitudeJitter
		)
	}

	private static func radicalInverse(_ value: Int, base: Int) -> Double {
		var value = value
		var inverse = 0.0
		var fraction = 1.0 / Double(base)
		while value > 0 {
			inverse += Double(value % base) * fraction
			value /= base
			fraction /= Double(base)
		}
		return inverse
	}

	private static func deterministicUnitValue(_ value: Int, salt: UInt64) -> Double {
		var mixed = UInt64(value) &+ salt
		mixed &+= 0x9E37_79B9_7F4A_7C15
		mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
		mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
		mixed ^= mixed >> 31
		return Double(mixed >> 11) / Double(1 << 53)
	}

	private static func insertTraceRoute(for node: NodeInfoEntity, index: Int, now: Date, context: ModelContext) {
		let traceRoute = TraceRouteEntity()
		traceRoute.id = Int64(index)
		traceRoute.response = true
		traceRoute.routeText = "Perf route \(index)"
		traceRoute.snr = node.snr
		traceRoute.time = now.addingTimeInterval(TimeInterval(-(index % 3_600)))
		traceRoute.node = node
		context.insert(traceRoute)
	}

	private static func seedMessageHistory(
		baseNodeNum: Int64,
		now: Date,
		configuration: PerformanceSeedConfiguration,
		context: ModelContext
	) {
		guard configuration.directMessageCount > 0 || configuration.channelMessageCount > 0 else { return }
		guard let localUser = fetchUser(num: baseNodeNum, context: context),
			  let remoteUser = fetchUser(num: baseNodeNum + 1, context: context) else {
			Logger.data.error("📈 [PerfSeed] Unable to seed messages without local and remote users")
			return
		}

		if configuration.directMessageCount > 0 {
			insertDirectMessages(
				count: configuration.directMessageCount,
				localUser: localUser,
				remoteUser: remoteUser,
				now: now,
				context: context
			)
		}
		if configuration.channelMessageCount > 0 {
			let channel = fetchOrCreateChannel(index: 0, myInfo: localUser.userNode?.myInfo, context: context)
			insertChannelMessages(
				count: configuration.channelMessageCount,
				channel: channel,
				localUser: localUser,
				remoteUser: remoteUser,
				now: now,
				context: context
			)
		}
	}

	private static func insertDirectMessages(
		count: Int,
		localUser: UserEntity,
		remoteUser: UserEntity,
		now: Date,
		context: ModelContext
	) {
		for index in 0..<count {
			let message = perfMessage(
				idBase: 0x0D00_0000,
				index: index,
				now: now,
				channel: 0,
				payloadPrefix: "Direct perf message"
			)
			if index.isMultiple(of: 2) {
				message.fromUser = localUser
				message.toUser = remoteUser
				message.realACK = true
				message.receivedACK = true
			} else {
				message.fromUser = remoteUser
				message.toUser = localUser
			}
			context.insert(message)
			insertPerfTapbackIfNeeded(for: message, idBase: 0x0E00_0000, index: index, from: remoteUser, to: localUser, context: context)
		}
		remoteUser.lastMessage = now
	}

	private static func insertChannelMessages(
		count: Int,
		channel: ChannelEntity,
		localUser: UserEntity,
		remoteUser: UserEntity,
		now: Date,
		context: ModelContext
	) {
		for index in 0..<count {
			let message = perfMessage(
				idBase: 0x0F00_0000,
				index: index,
				now: now,
				channel: channel.index,
				payloadPrefix: "Channel perf message"
			)
			message.fromUser = index.isMultiple(of: 3) ? localUser : remoteUser
			context.insert(message)
			insertPerfTapbackIfNeeded(for: message, idBase: 0x1000_0000, index: index, from: remoteUser, to: nil, context: context)
		}
	}

	private static func perfMessage(
		idBase: Int64,
		index: Int,
		now: Date,
		channel: Int32,
		payloadPrefix: String
	) -> MessageEntity {
		let message = MessageEntity()
		message.messageId = idBase + Int64(index)
		message.channel = channel
		message.messageTimestamp = Int32(now.addingTimeInterval(TimeInterval(-(countdownOffset(index)))).timeIntervalSince1970)
		message.messagePayload = "\(payloadPrefix) \(index) with enough text to exercise bubble layout and markdown parsing."
		message.messagePayloadMarkdown = message.messagePayload
		message.read = index < 3 ? false : true
		message.rssi = Int32(-40 - (index % 80))
		message.snr = Float((index % 24) - 12)
		return message
	}

	private static func insertPerfTapbackIfNeeded(
		for message: MessageEntity,
		idBase: Int64,
		index: Int,
		from: UserEntity,
		to: UserEntity?,
		context: ModelContext
	) {
		guard index > 0 && index.isMultiple(of: 20) else { return }
		let tapback = MessageEntity()
		tapback.messageId = idBase + Int64(index)
		tapback.channel = message.channel
		tapback.isEmoji = true
		tapback.messageTimestamp = message.messageTimestamp + 1
		tapback.messagePayload = "👍"
		tapback.replyID = message.messageId
		tapback.fromUser = from
		tapback.toUser = to
		tapback.read = true
		context.insert(tapback)
	}

	private static func countdownOffset(_ index: Int) -> Int {
		index * 30
	}

	private static func fetchUser(num: Int64, context: ModelContext) -> UserEntity? {
		var descriptor = FetchDescriptor<UserEntity>(
			predicate: #Predicate<UserEntity> { $0.num == num }
		)
		descriptor.fetchLimit = 1
		return try? context.fetch(descriptor).first
	}

	private static func fetchOrCreateChannel(index: Int32, myInfo: MyInfoEntity?, context: ModelContext) -> ChannelEntity {
		var descriptor = FetchDescriptor<ChannelEntity>(
			predicate: #Predicate<ChannelEntity> { $0.index == index }
		)
		descriptor.fetchLimit = 1
		if let existing = try? context.fetch(descriptor).first {
			if existing.myInfoChannel == nil {
				existing.myInfoChannel = myInfo
			}
			return existing
		}
		let channel = ChannelEntity()
		channel.id = index
		channel.index = index
		channel.name = "Perf Channel"
		channel.role = 1
		channel.myInfoChannel = myInfo
		context.insert(channel)
		return channel
	}

	private static func shortName(for index: Int) -> String {
		let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
		return "\(letters[index % letters.count])\(index % 100)"
	}

	private static func hardwareModel(for index: Int) -> String {
		let models = ["TBEAM", "HELTECV3", "RAK4631", "TLORAV2", "TRACKERT1000E", "UNSET"]
		return models[index % models.count]
	}

	private static func integerValue(_ key: String, environment: [String: String], defaultValue: Int) -> Int {
		guard let value = environment[key], let parsed = Int(value), parsed > 0 else {
			return defaultValue
		}
		return parsed
	}

	private static func boolValue(_ key: String, environment: [String: String]) -> Bool {
		guard let value = environment[key]?.lowercased() else { return false }
		return value == "1" || value == "true" || value == "yes"
	}
}
#endif
