//
//  PerformanceSeedData.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/2/26.
//

#if DEBUG
import SwiftData
import OSLog
import Foundation

@MainActor
struct PerformanceSeedConfiguration {
	let nodeCount: Int
	let telemetryHistoryPerNode: Int
	let localStatsHistoryPerNode: Int
	let positionHistoryPerNode: Int
	let directMessageCount: Int
	let channelMessageCount: Int
	let resetStore: Bool
	let compactNodeList: Bool
	let disableDiscovery: Bool
	let initialTab: NavigationState.Tab
	let opensLocalStatsLog: Bool
	let localStatsSameHourSeed: Bool
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
			localStatsHistoryPerNode: integerValue("MESHTASTIC_PERF_LOCAL_STATS_HISTORY", environment: environment, defaultValue: integerValue("MESHTASTIC_PERF_TELEMETRY_HISTORY", environment: environment, defaultValue: 3)),
			positionHistoryPerNode: integerValue("MESHTASTIC_PERF_POSITION_HISTORY", environment: environment, defaultValue: 3),
			directMessageCount: integerValue("MESHTASTIC_PERF_DIRECT_MESSAGES", environment: environment, defaultValue: 0),
			channelMessageCount: integerValue("MESHTASTIC_PERF_CHANNEL_MESSAGES", environment: environment, defaultValue: 0),
			resetStore: boolValue("MESHTASTIC_PERF_RESET_STORE", environment: environment) || arguments.contains("--meshtastic-perf-reset"),
			compactNodeList: boolValue("MESHTASTIC_PERF_COMPACT_LIST", environment: environment) || arguments.contains("--meshtastic-perf-compact-list"),
			disableDiscovery: !boolValue("MESHTASTIC_PERF_ENABLE_DISCOVERY", environment: environment),
			initialTab: arguments.contains("--meshtastic-perf-start-map") ? .map : .nodes,
			opensLocalStatsLog: arguments.contains("--meshtastic-perf-start-local-stats"),
			localStatsSameHourSeed: arguments.contains("--meshtastic-perf-local-stats-same-hour")
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
			if configuration.opensLocalStatsLog {
				router.selectedNodeNum = 0x0A00_0000
			}
			Logger.data.info("📈 [PerfSeed] Existing large mesh seed found; skipping reseed")
			return
		}

		Logger.data.info("📈 [PerfSeed] Seeding \(configuration.nodeCount, privacy: .public) nodes, \(configuration.telemetryHistoryPerNode, privacy: .public) telemetry samples/type, \(configuration.localStatsHistoryPerNode, privacy: .public) local stats samples/node, \(configuration.positionHistoryPerNode, privacy: .public) positions/node")

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
			if configuration.opensLocalStatsLog {
				router.selectedNodeNum = baseNodeNum
			}
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

	/// Node number for a seeded node at `index`.
	///
	/// The app derives a node's map/pin color from `UIColor(hex: UInt32(num))` — i.e. the low 24 bits
	/// of the number become its RGB. Sequential numbers (`base + index`) leave those bits at `0, 1,
	/// 2, …`, which all render as near-identical near-black, so every seeded node looked the same
	/// color. Scramble the index with a multiplicative (golden-ratio) hash so the low 24 bits — and
	/// thus the colors — spread across the wheel like real, randomly-numbered radios do.
	///
	/// The hash is a bijection mod 2²⁴ (the constant is odd → coprime to 2²⁴), so numbers stay unique
	/// for any realistic node count, index 0 maps back to `baseNodeNum` (the local node), and every
	/// number stays ≤ `0x0AFFFFFF` — well under `UInt32.max`, which `UInt32(num)` requires (it traps
	/// on overflow).
	private static func seededNodeNum(baseNodeNum: Int64, index: Int) -> Int64 {
		let scrambled = (UInt32(truncatingIfNeeded: index) &* 0x9E3779) & 0x00FF_FFFF
		return baseNodeNum + Int64(scrambled)
	}

	private static func insertNode(
		index: Int,
		baseNodeNum: Int64,
		now: Date,
		configuration: PerformanceSeedConfiguration,
		context: ModelContext
	) {
		let nodeNum = seededNodeNum(baseNodeNum: baseNodeNum, index: index)
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

		// Seed a trace route on every 4th node (skipping the first few so the target isn't the
		// originator itself) — gives a handful of complete, multi-hop, both-ways routes to test with.
		if index >= 4, index.isMultiple(of: 4) {
			insertTraceRoute(for: node, index: index, now: now, baseNodeNum: baseNodeNum, context: context)
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

		for sample in 0..<configuration.localStatsHistoryPerNode {
			let timestamp = if configuration.localStatsSameHourSeed {
				localStatsSameHourTimestamp(now: now, sample: sample)
			} else {
				now.addingTimeInterval(TimeInterval(-(sample * 900 + index % 600)))
			}
			let localStats = TelemetryEntity()
			localStats.metricsType = 4
			localStats.time = timestamp
			localStats.noiseFloor = syntheticNoiseFloor(nodeIndex: index, sample: sample)
			localStats.channelUtilization = Float((index * 3 + sample * 5) % 100) / 2
			localStats.airUtilTx = Float((index + sample * 2) % 80) / 10
			localStats.numPacketsTx = Int32(120 + index % 70 + sample * 3)
			localStats.numPacketsRx = Int32(300 + index % 140 + sample * 5)
			localStats.numPacketsRxBad = Int32((index + sample) % 11)
			localStats.numRxDupe = Int32((index + sample * 2) % 9)
			localStats.numTxRelay = Int32((index + sample * 3) % 24)
			localStats.numTxRelayCanceled = Int32((index + sample) % 4)
			localStats.numOnlineNodes = Int32(max(1, min(250, configuration.nodeCount - (sample % 12))))
			localStats.numTotalNodes = Int32(configuration.nodeCount)
			localStats.uptimeSeconds = Int32(86_400 + index * 60 + sample * 900)
			localStats.nodeTelemetry = node
			context.insert(localStats)
		}
	}

	private static func localStatsSameHourTimestamp(now: Date, sample: Int) -> Date {
		let calendar = Calendar.current
		let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
		let minute = calendar.component(.minute, from: now)
		let hourStart = minute < 25 ? currentHourStart.addingTimeInterval(-3_600) : currentHourStart
		return hourStart.addingTimeInterval(TimeInterval(sample * 300))
	}

	private static func syntheticNoiseFloor(nodeIndex: Int, sample: Int) -> Int32 {
		let dailyWave = sin(Double(sample) / 8.0) * 5.0
		let nodeBias = Double((nodeIndex % 13) - 6)
		let interferenceSpike = sample.isMultiple(of: 37) ? 14.0 : 0.0
		let deterministicJitter = (deterministicUnitValue(nodeIndex * 4_096 + sample, salt: 0x8EBC_6AF0_9C88_C6E3) - 0.5) * 6.0
		let value = -102.0 + dailyWave + nodeBias + interferenceSpike + deterministicJitter
		return Int32(value.rounded())
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
			if position.latest { node.latestPositionCache = position }
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

	private static func insertTraceRoute(for node: NodeInfoEntity, index: Int, now: Date, baseNodeNum: Int64, context: ModelContext) {
		let traceRoute = TraceRouteEntity()
		traceRoute.id = Int64(index)
		traceRoute.response = true
		traceRoute.sent = true
		traceRoute.routeText = "Perf route \(index)"
		traceRoute.snr = node.snr
		traceRoute.time = now.addingTimeInterval(TimeInterval(-(index % 3_600)))
		traceRoute.node = node
		traceRoute.fromNum = baseNodeNum
		traceRoute.toNum = node.num
		context.insert(traceRoute)

		// Forward path: originator -> several earlier seeded nodes -> target. More intermediate hops
		// make a richer flyover; only reference nodes that already exist (num < target) so the
		// snapshot lookups resolve.
		var forwardNums: [Int64] = [baseNodeNum]
		for divisor in [6, 5, 4, 3, 2] {
			let hopIndex = index / divisor
			// hopIndex < index (divisor ≥ 2) so the node was seeded earlier and exists; skip 0, which
			// is the originator (baseNodeNum) already at the head of the path.
			guard hopIndex > 0 else { continue }
			let candidate = seededNodeNum(baseNodeNum: baseNodeNum, index: hopIndex)
			if !forwardNums.contains(candidate) {
				forwardNums.append(candidate)
			}
		}
		forwardNums.append(node.num)
		traceRoute.hopsTowards = Int32(max(0, forwardNums.count - 2))

		// Return path: target -> back through the same intermediate nodes -> originator. The stored
		// back hops are the intermediate return nodes only (endpoints are bracketed when rendering).
		let returnIntermediates = Array(forwardNums.dropFirst().dropLast().reversed())
		traceRoute.hopsBack = Int32(returnIntermediates.count)

		// Spread hop SNRs across the good/fair/bad/none bands (relative to longFast's -17.5 limit) so
		// the per-leg signal coloring is visible when testing with seeded routes.
		let snrSpread: [Float] = [8, -12, -19, -21, -24, -30]
		var snapshotted = Set<Int64>()
		func snapshot(_ num: Int64, _ hopNode: NodeInfoEntity?) {
			guard !snapshotted.contains(num), let position = hopNode?.latestPosition, position.nodeCoordinate != nil else { return }
			snapshotted.insert(num)
			let snap = TraceRouteNodePositionEntity()
			snap.num = num
			snap.latitudeI = position.latitudeI
			snap.longitudeI = position.longitudeI
			snap.altitude = position.altitude
			snap.time = position.time
			snap.traceRoute = traceRoute
			context.insert(snap)
			traceRoute.hasPositions = true
		}

		// Forward hops (toward the target).
		for (hopIndex, num) in forwardNums.enumerated() {
			let hopNode = num == node.num ? node : getNodeInfo(id: num, context: context)
			let hop = TraceRouteHopEntity()
			hop.back = false
			hop.index = Int32(hopIndex)
			hop.num = num
			hop.name = hopNode?.user?.longName
			hop.snr = snrSpread[(index + hopIndex) % snrSpread.count]
			hop.time = traceRoute.time
			hop.traceRoute = traceRoute
			context.insert(hop)
			snapshot(num, hopNode)
		}

		// Return hops (back toward the originator) — intermediate nodes only, with distinct SNRs.
		for (hopIndex, num) in returnIntermediates.enumerated() {
			let hopNode = getNodeInfo(id: num, context: context)
			let hop = TraceRouteHopEntity()
			hop.back = true
			hop.index = Int32(hopIndex)
			hop.num = num
			hop.name = hopNode?.user?.longName
			hop.snr = snrSpread[(index + hopIndex + 3) % snrSpread.count]
			hop.time = traceRoute.time
			hop.traceRoute = traceRoute
			context.insert(hop)
			snapshot(num, hopNode)
		}
	}

	private static func seedMessageHistory(
		baseNodeNum: Int64,
		now: Date,
		configuration: PerformanceSeedConfiguration,
		context: ModelContext
	) {
		guard configuration.directMessageCount > 0 || configuration.channelMessageCount > 0 else { return }
		guard let localUser = fetchUser(num: baseNodeNum, context: context),
			  let remoteUser = fetchUser(num: seededNodeNum(baseNodeNum: baseNodeNum, index: 1), context: context) else {
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
