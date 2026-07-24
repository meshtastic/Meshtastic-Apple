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

/// How the seed data reads: a huge synthetic Bay-Area mesh for performance/stress testing, or a small,
/// hand-curated all-on-land Seattle mesh with realistic names + messages for App Store screenshots.
@MainActor
enum SeedStyle {
	case performance
	case marketing
	/// A tiny, hand-placed mesh for demoing/QA'ing the map's coincident-node disambiguation picker.
	/// See `ClusterDemoSeed`.
	case clusterDemo
}

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
	let style: SeedStyle
}

@MainActor
enum PerformanceSeedData {
	static var configuration: PerformanceSeedConfiguration? {
		let environment = ProcessInfo.processInfo.environment
		let arguments = ProcessInfo.processInfo.arguments

		// Marketing seed: a small, curated, all-on-land Seattle-metro mesh for App Store screenshots.
		// Checked first so `--meshtastic-marketing-seed` alone produces the marketing data set,
		// independent of the performance-seed knobs below.
		if arguments.contains("--meshtastic-marketing-seed") || boolValue("MESHTASTIC_MARKETING_SEED", environment: environment) {
			return PerformanceSeedConfiguration(
				nodeCount: MarketingSeed.nodeCount,
				telemetryHistoryPerNode: 12,
				localStatsHistoryPerNode: 24,
				positionHistoryPerNode: 1,
				directMessageCount: MarketingSeed.directMessages.count,
				channelMessageCount: MarketingSeed.channelMessages.count,
				resetStore: true,
				compactNodeList: false,
				disableDiscovery: true,
				initialTab: arguments.contains("--meshtastic-perf-start-map") ? .map : .nodes,
				opensLocalStatsLog: false,
				localStatsSameHourSeed: true,
				style: .marketing
			)
		}

		// Coincident-node demo: a handful of nodes deliberately placed on (near-)coincident coordinates
		// so the map's un-splittable stack + disambiguation picker reproduce on demand. Opens straight
		// to the map. Gate: `--meshtastic-cluster-demo`.
		if arguments.contains("--meshtastic-cluster-demo") || boolValue("MESHTASTIC_CLUSTER_DEMO", environment: environment) {
			return PerformanceSeedConfiguration(
				nodeCount: ClusterDemoSeed.nodeCount,
				telemetryHistoryPerNode: 1,
				localStatsHistoryPerNode: 1,
				positionHistoryPerNode: 1,
				directMessageCount: 0,
				channelMessageCount: 0,
				resetStore: true,
				compactNodeList: false,
				disableDiscovery: true,
				initialTab: .map,
				opensLocalStatsLog: false,
				localStatsSameHourSeed: false,
				style: .clusterDemo
			)
		}

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
			localStatsSameHourSeed: arguments.contains("--meshtastic-perf-local-stats-same-hour"),
			style: .performance
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
		if configuration.style == .marketing {
			// Show individual colored node pins on the map (not count bubbles) so it reads as a real
			// mesh. All node positions are on land.
			UserDefaults.standard.set(false, forKey: "enableMapClustering")
		}
		if configuration.style == .clusterDemo {
			// Force clustering ON by default so coincident nodes collapse into one badge and tapping it
			// exercises the disambiguation picker. Pass `--cluster-demo-no-clustering` to force it OFF
			// instead, verifying a plain pin tap on a fully-occluded stack still opens the picker.
			let clusteringOff = ProcessInfo.processInfo.arguments.contains("--cluster-demo-no-clustering")
			UserDefaults.standard.set(!clusteringOff, forKey: "enableMapClustering")
		}
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

		// Marketing seed overrides the synthetic perf values with curated, realistic Seattle-mesh
		// content (names, hardware, roles, healthy telemetry, recent last-heard).
		if configuration.style == .marketing {
			MarketingSeed.apply(to: node, user: user, metadata: metadata, index: index, now: now)
		} else if configuration.style == .clusterDemo {
			user.longName = ClusterDemoSeed.longName(for: index)
			user.shortName = ClusterDemoSeed.shortName(for: index)
			user.hwDisplayName = user.hwModel
			node.hopsAway = 0
			node.viaMqtt = false
			node.lastHeard = now
			metadata.time = now
		}

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
			deviceMetrics.batteryLevel = configuration.style == .marketing
				? Int32(MarketingSeed.battery(for: index, sample: sample))
				: Int32((index + sample) % 130)
			deviceMetrics.voltage = 3.3 + Float((index + sample) % 90) / 100
			deviceMetrics.channelUtilization = Float((index + sample) % 100)
			deviceMetrics.airUtilTx = Float((index + sample * 3) % 100) / 10
			deviceMetrics.uptimeSeconds = configuration.style == .marketing
				? Int32(86_400 * (3 + index % 40) + sample * 300)   // 3–43 days, like a real long-lived node
				: Int32(index * 60 + sample)
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
		let baseCoordinate: (latitude: Double, longitude: Double)
		switch configuration.style {
		case .marketing: baseCoordinate = MarketingSeed.coordinate(for: index)
		case .clusterDemo: baseCoordinate = ClusterDemoSeed.coordinate(for: index)
		case .performance: baseCoordinate = bayAreaCoordinate(for: index)
		}
		// The cluster demo relies on the *exact* coincident coordinates, so it must not add the
		// per-sample walk offset the perf seed uses (it seeds a single position anyway).
		let sampleWalk = configuration.style == .clusterDemo ? 0.0 : 0.0001

		for sample in 0..<configuration.positionHistoryPerNode {
			let position = PositionEntity()
			position.altitude = Int32(5 + (index % 600))
			position.heading = Int32((index * 17 + sample * 23) % 360)
			position.latest = sample == 0
			position.latitudeI = Int32((baseCoordinate.latitude + Double(sample) * sampleWalk) * 1e7)
			position.longitudeI = Int32((baseCoordinate.longitude + Double(sample) * sampleWalk) * 1e7)
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

		// Marketing seed: curated, human-readable conversations (a DM thread + a lively primary channel)
		// instead of the numbered filler perf messages.
		if configuration.style == .marketing {
			let channel = fetchOrCreateChannel(index: 0, myInfo: localUser.userNode?.myInfo, context: context, name: "Seattle Mesh")
			MarketingSeed.insertConversations(localUser: localUser, remoteUser: remoteUser, channel: channel, now: now, context: context)
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

	private static func fetchOrCreateChannel(index: Int32, myInfo: MyInfoEntity?, context: ModelContext, name: String = "Perf Channel") -> ChannelEntity {
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
		channel.name = name
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

// MARK: - Discovery beacon seeding

@MainActor
extension PerformanceSeedData {

	/// Seeded beacons use node numbers in this range so a relaunch can detect an existing seed and
	/// skip re-inserting (invisible to the UI, unlike a name/summary marker).
	private static var beaconSeedBase: Int64 { 0x0BEA_C000 }

	/// One beacon's seed values (kept as a single struct so the builder stays under the parameter
	/// count limit and the sample data reads as a table).
	private struct BeaconSpec {
		let idx: Int64
		let short: String
		let long: String
		let message: String
		let preset: Int
		let region: Int
		let channelName: String
		let hasChannel: Bool
		let snr: Float
		let rssi: Int
		let heardOn: String
	}

	/// Seed one completed Discovery scan session populated with sample mesh beacons, gated by the
	/// `--meshtastic-seed-beacons` launch argument (or `MESHTASTIC_SEED_BEACONS=1`). Independent of
	/// the node performance seed: it neither resets the store nor blocks a live radio connection, so
	/// the seeded Discovery history can be viewed while the app is connected to a real/replay radio.
	static func seedDiscoveryBeaconsIfRequested(using controller: PersistenceController) {
		let args = ProcessInfo.processInfo.arguments
		let env = ProcessInfo.processInfo.environment
		// The marketing seed auto-includes a discovery session so the Local Mesh Discovery screens are
		// populated in screenshots, relocated to Seattle to match the rest of the marketing mesh.
		let marketing = args.contains("--meshtastic-marketing-seed") || boolValue("MESHTASTIC_MARKETING_SEED", environment: env)
		guard args.contains("--meshtastic-seed-beacons") || boolValue("MESHTASTIC_SEED_BEACONS", environment: env) || marketing else { return }

		let context = controller.container.mainContext

		// Idempotent: if any seeded beacon is already present, do nothing.
		let base = beaconSeedBase
		let ceiling = beaconSeedBase + 0x100
		let existing = try? context.fetch(
			FetchDescriptor<DiscoveredBeaconEntity>(predicate: #Predicate { $0.nodeNum >= base && $0.nodeNum < ceiling })
		)
		if let existing, !existing.isEmpty {
			Logger.data.info("📡 [BeaconSeed] Seeded beacons already present; skipping")
			return
		}

		let now = Date()
		let presets = ModemPresets.userSelectable
		let session = DiscoverySessionEntity()
		session.timestamp = now
		session.presetsScanned = presets.map { $0.description }.joined(separator: ", ")
		session.totalUniqueNodes = 120
		session.averageChannelUtilization = 7.9
		session.totalTextMessages = 342
		session.totalSensorPackets = 110
		session.furthestNodeDistance = 4200.0
		session.completionStatus = "complete"
		session.homePreset = "LongFast"
		session.userLatitude = marketing ? 47.5790 : 36.1699   // Seattle (Beacon Hill) for marketing, else Las Vegas / DEF CON
		session.userLongitude = marketing ? -122.3115 : -115.1398
		session.aiSummaryText = marketing
			? "Swept every selectable preset around Seattle — a public beacon on each, plus three neighborhood community channels and the nodes heard nearby. LongFast has the busiest mesh; MediumFast is the quietest of the long-range presets."
			: "Seeded DEF CON discovery session: swept every selectable preset (a public beacon on each), plus custom-channel beacons and discovered nodes."
		context.insert(session)

		// One dwell result per selectable preset, so the session looks like a full sweep.
		var resultsByPreset: [String: DiscoveryPresetResultEntity] = [:]
		for (i, preset) in presets.enumerated() {
			let unique = max(6, 60 - i * 7)
			let util = max(2.0, 8.5 - Double(i))
			let noise = -118.0 - Double(i)
			let result = presetResult(session: session, context: context, name: preset.description, dwell: 60,
									  unique: unique, direct: max(2, 12 - i), mesh: max(3, 30 - i * 3),
									  infra: max(1, 10 - i), msgs: max(8, 180 - i * 20), sensors: max(4, 50 - i * 5),
									  util: util, noise: noise)
			resultsByPreset[preset.description] = result
		}

		var idx: Int64 = 0
		var beaconCount = 0

		// A public beacon advertising a preset. The test seed puts one on every selectable preset (so
		// every row gets a beacon icon); the marketing seed keeps it realistic — only the popular
		// presets (LongFast rawValue 0, MediumFast rawValue 4) carry a public beacon.
		let publicPresets = marketing ? presets.filter { [0, 4].contains($0.rawValue) } : presets
		for (i, preset) in publicPresets.enumerated() {
			idx += 1
			let name = preset.description
			let spec = BeaconSpec(idx: idx, short: "PB\(i + 1)", long: "\(name) Mesh",
								  message: "Public beacon advertising \(name)",
								  preset: preset.rawValue, region: RegionCodes.us.rawValue,
								  channelName: "", hasChannel: false,
								  snr: Float(8 - i), rssi: -85 - i * 2, heardOn: name)
			insertBeacon(spec, session: session, presetResult: resultsByPreset[name], now: now, context: context)
			beaconCount += 1
		}

		// Custom-channel beacons — each advertises a channel, so each gets a "Switch to this channel"
		// action in the session summary.
		func addCustom(_ short: String, _ long: String, channel: String, preset: ModemPresets) {
			idx += 1
			let name = preset.description
			let spec = BeaconSpec(idx: idx, short: short, long: long,
								  message: "\(long) — join the \(channel) channel",
								  preset: preset.rawValue, region: RegionCodes.us.rawValue,
								  channelName: channel, hasChannel: true,
								  snr: 7.5, rssi: -90, heardOn: name)
			insertBeacon(spec, session: session, presetResult: resultsByPreset[name], now: now, context: context)
			beaconCount += 1
		}
		if marketing {
			addCustom("BLRD", "Ballard Mesh", channel: "Ballard", preset: .shortTurbo)
			addCustom("CAPH", "Capitol Hill Mesh", channel: "CapHill", preset: .longSlow)
			addCustom("FRMT", "Fremont Mesh", channel: "Fremont", preset: .longFast)
		} else {
			addCustom("HAX", "Hackers Village", channel: "Hax", preset: .shortTurbo)
			addCustom("CHV", "Car Hacking Village", channel: "CarHax", preset: .longSlow)
			addCustom("AIV", "AI Village", channel: "AIVillage", preset: .longFast)
		}

		// Anonymous, no-preset beacon (exercises the hex-fallback display + the "no chips" path).
		idx += 1
		let firstName = presets.first?.description ?? "LongFast"
		insertBeacon(BeaconSpec(idx: idx, short: "", long: "", message: "anonymous beacon",
								preset: -1, region: 0, channelName: "", hasChannel: false,
								snr: 1.2, rssi: -110, heardOn: firstName),
					 session: session, presetResult: resultsByPreset[firstName], now: now, context: context)
		beaconCount += 1

		// Discovered nodes around the user, so the discovery map / results are populated too.
		let firstResult = resultsByPreset[firstName] ?? resultsByPreset.values.first
		for i in 0..<18 {
			insertDiscoveredNode(index: i, presetName: firstName, session: session, presetResult: firstResult, context: context)
		}

		do {
			try context.save()
			Logger.data.info("📡 [BeaconSeed] Seeded 1 discovery session with \(beaconCount, privacy: .public) beacons across \(presets.count, privacy: .public) presets")
		} catch {
			Logger.data.error("📡 [BeaconSeed] Failed to seed beacons: \(error.localizedDescription, privacy: .public)")
		}
	}

	// swiftlint:disable:next function_parameter_count
	private static func presetResult(
		session: DiscoverySessionEntity,
		context: ModelContext,
		name: String,
		dwell: Int,
		unique: Int,
		direct: Int,
		mesh: Int,
		infra: Int,
		msgs: Int,
		sensors: Int,
		util: Double,
		noise: Double
	) -> DiscoveryPresetResultEntity {
		let result = DiscoveryPresetResultEntity()
		result.presetName = name
		result.dwellDurationSeconds = dwell
		result.uniqueNodesFound = unique
		result.directNeighborCount = direct
		result.meshNeighborCount = mesh
		result.infrastructureNodeCount = infra
		result.messageCount = msgs
		result.sensorPacketCount = sensors
		result.averageChannelUtilization = util
		result.averageNoiseFloor = noise
		result.numOnlineNodes = unique
		result.numTotalNodes = unique + 12
		result.session = session
		context.insert(result)
		return result
	}

	private static func insertDiscoveredNode(
		index: Int,
		presetName: String,
		session: DiscoverySessionEntity,
		presetResult: DiscoveryPresetResultEntity?,
		context: ModelContext
	) {
		let node = DiscoveredNodeEntity()
		node.nodeNum = 0x0D00_0000 + Int64(index)
		node.shortName = "N" + String(format: "%03d", index)
		node.longName = "Discovered Node \(index)"
		node.neighborType = index % 3 == 0 ? "direct" : "mesh"
		// A small deterministic grid around the session's user location so the discovery map has content
		// (Seattle/Beacon Hill for the marketing seed, else Las Vegas). The center matches the session's
		// userLatitude/userLongitude; both grids stay on land.
		let marketing = ProcessInfo.processInfo.arguments.contains("--meshtastic-marketing-seed") || boolValue("MESHTASTIC_MARKETING_SEED", environment: ProcessInfo.processInfo.environment)
		let centerLat = marketing ? 47.5790 : 36.1699
		let centerLon = marketing ? -122.3115 : -115.1398
		node.latitude = centerLat + Double(index % 6) * 0.008 - 0.02
		node.longitude = centerLon + Double(index / 6) * 0.008 - 0.01
		node.distanceFromUser = Double(200 + index * 150)
		node.hopCount = index % 5
		node.snr = Float(9 - index % 9)
		node.rssi = -75 - index % 30
		node.messageCount = index * 2
		node.sensorPacketCount = index
		node.isInfrastructure = index % 4 == 0
		node.presetName = presetName
		node.session = session
		node.presetResult = presetResult
		context.insert(node)
	}

	private static func insertBeacon(
		_ spec: BeaconSpec,
		session: DiscoverySessionEntity,
		presetResult: DiscoveryPresetResultEntity?,
		now: Date,
		context: ModelContext
	) {
		let beacon = DiscoveredBeaconEntity()
		beacon.nodeNum = beaconSeedBase + spec.idx
		beacon.shortName = spec.short
		beacon.longName = spec.long
		beacon.message = spec.message
		beacon.offerPreset = spec.preset
		beacon.offerRegion = spec.region
		beacon.hasOfferChannel = spec.hasChannel
		if spec.hasChannel {
			beacon.offerChannelName = spec.channelName
			var psk = Data(count: 16)
			let salt = Int(spec.idx) * 7
			for i in 0..<16 {
				psk[i] = UInt8((i * 37 + salt + 11) & 0xFF)
			}
			beacon.offerChannelPSK = psk
		}
		beacon.snr = spec.snr
		beacon.rssi = spec.rssi
		beacon.heardOnPresetName = spec.heardOn
		beacon.timestamp = now
		beacon.session = session
		beacon.presetResult = presetResult
		context.insert(beacon)
	}
}

// MARK: - Coincident-node demo seed

/// A tiny, deterministic mesh for demoing/verifying the map's coincident-node disambiguation picker.
///
/// With the map fan-out removed, nodes that sit within a few meters of each other stay stacked. When
/// clustering is on they collapse into one count badge (tap -> picker); with `--cluster-demo-no-clustering`
/// they render as overlapping pins (a plain pin tap must still open the picker, per the clustering-off
/// path in `MeshMapMK.presentNodeSelection`).
///
/// Scenarios (pick with a launch arg, or `MESHTASTIC_CLUSTER_DEMO_SCENARIO=<name>`; no rebuild needed
/// to switch once compiled):
///   • `pairs`  (default)               — local + two 2-node pairs ~0.1 m apart.
///   • `--cluster-demo-colocated10/30/50` — one exact-coincident stack of N nodes.
///   • `--cluster-demo-stacks`          — three separate small coincident stacks near each other.
/// The map's tight-frame span (`frameSpanDegrees`) scales with the scenario so the stack(s) fill the view.
@MainActor
enum ClusterDemoSeed {
	/// Center point all scenarios build around (3rd Ave S, Seattle — matches the earlier screenshots).
	private static let center = (lat: 47.6001, lon: -122.3301)
	private static let stackMemberCount = 4
	private struct StackAnchor { let label: String; let lat: Double; let lon: Double }
	/// Three coincident stacks arranged in a ~50 m triangle around `center`; members of each share one coordinate.
	private static let stackAnchors: [StackAnchor] = [
		StackAnchor(label: "A", lat: 47.60055, lon: -122.33010),  // ~50 m north
		StackAnchor(label: "B", lat: 47.59970, lon: -122.32948),  // ~50 m southeast
		StackAnchor(label: "C", lat: 47.59970, lon: -122.33072)   // ~50 m southwest
	]

	/// Raw scenario token: env var wins, else a `--cluster-demo-<token>` launch arg, else `pairs`.
	private static var rawScenario: String {
		if let env = ProcessInfo.processInfo.environment["MESHTASTIC_CLUSTER_DEMO_SCENARIO"]?.lowercased() {
			return env
		}
		let args = ProcessInfo.processInfo.arguments
		for token in ["colocated10", "colocated30", "colocated50", "stacks", "pairs"] where args.contains("--cluster-demo-\(token)") {
			return token
		}
		return "pairs"
	}

	/// For a `colocatedN` scenario, the coincident node count N; nil otherwise.
	private static var colocatedCount: Int? {
		switch rawScenario {
		case "colocated10": return 10
		case "colocated30": return 30
		case "colocated50": return 50
		default: return nil
		}
	}
	private static var isStacks: Bool { rawScenario == "stacks" }

	/// Total seeded nodes (index 0 is always the standalone local node).
	static var nodeCount: Int {
		if let count = colocatedCount { return 1 + count }
		if isStacks { return 1 + stackAnchors.count * stackMemberCount }
		return 5
	}

	/// Map tight-frame span (degrees latitude). Override with `MESHTASTIC_CLUSTER_DEMO_SPAN=<deg>`.
	static var frameSpanDegrees: Double {
		if let raw = ProcessInfo.processInfo.environment["MESHTASTIC_CLUSTER_DEMO_SPAN"], let value = Double(raw) {
			return value
		}
		switch rawScenario {
		case "stacks": return 0.0024
		default: return 0.0016
		}
	}

	static func coordinate(for index: Int) -> (latitude: Double, longitude: Double) {
		if colocatedCount != nil {
			// Local node offset clear of the stack; every other node on the *exact* same point.
			return index == 0 ? (center.lat + 0.0003, center.lon - 0.0004) : (center.lat, center.lon)
		}
		if isStacks {
			if index == 0 { return (center.lat + 0.0006, center.lon - 0.0009) } // local, NW, clear of stacks
			let anchor = stackAnchors[(index - 1) / stackMemberCount % stackAnchors.count]
			return (anchor.lat, anchor.lon)                                     // members coincident per stack
		}
		// pairs (the near-coincident default)
		switch index {
		case 1: return (47.6000045, -122.33000)  // pair 1
		case 2: return (47.6000055, -122.33000)  // pair 1, ~0.1 m away
		case 3: return (47.6001845, -122.33000)  // pair 2, ~20 m north
		case 4: return (47.6001855, -122.33000)  // pair 2, ~0.1 m away
		default: return (47.6000950, -122.33028) // local node, standalone (~10 m N, ~21 m W)
		}
	}

	static func longName(for index: Int) -> String {
		if index == 0 { return "My Node" }
		if colocatedCount != nil { return "Node \(index)" }
		if isStacks { return "Stack \(shortName(for: index))" }
		switch index {
		case 1: return "Demo A (pair 1)"
		case 2: return "Demo B (pair 1)"
		case 3: return "Demo C (pair 2)"
		case 4: return "Demo D (pair 2)"
		default: return "Demo Node \(index)"
		}
	}

	static func shortName(for index: Int) -> String {
		if index == 0 { return "ME" }
		if colocatedCount != nil { return "\(index)" }
		if isStacks {
			let anchor = stackAnchors[(index - 1) / stackMemberCount % stackAnchors.count]
			return "\(anchor.label)\((index - 1) % stackMemberCount + 1)"
		}
		switch index {
		case 1: return "A"
		case 2: return "B"
		case 3: return "C"
		case 4: return "D"
		default: return "N\(index)"
		}
	}
}

// MARK: - Marketing seed content

/// Curated, all-on-land Seattle-metro data for the App Store screenshot seed (`--meshtastic-marketing-seed`).
///
/// Nodes are scattered around ~three dozen hand-picked *inland* neighborhood anchors. Each anchor carries
/// a `radius` — the largest jitter (in degrees, applied independently to latitude/longitude) that keeps a
/// scattered node clear of the nearest water (Puget Sound, Elliott Bay, Lake Union, Lake Washington, the
/// ship canal, Green Lake). Shore-adjacent anchors get a tight radius; interior anchors get a generous one.
/// The first node at each anchor (`ring == 0`) sits exactly on the anchor with a curated "hero" name;
/// later rings jitter within the safe radius and get generated handles/callsigns.
@MainActor
enum MarketingSeed {

	struct Anchor {
		let long: String
		let short: String
		let lat: Double
		let lon: Double
		let radius: Double
	}

	/// Node 0 is the connected/local node (Capitol Hill). Node 1 (Ballard Beacon) is the DM partner.
	static let anchors: [Anchor] = [
		Anchor(long: "Capitol Hill Relay", short: "CAPH", lat: 47.6225, lon: -122.3120, radius: 0.007),
		Anchor(long: "Ballard Beacon", short: "BLRD", lat: 47.6710, lon: -122.3835, radius: 0.0030),
		Anchor(long: "Fremont Troll", short: "TROL", lat: 47.6528, lon: -122.3495, radius: 0.0012),
		Anchor(long: "Queen Anne Node", short: "QANN", lat: 47.6370, lon: -122.3565, radius: 0.006),
		Anchor(long: "U-District Solar", short: "UWSL", lat: 47.6595, lon: -122.3140, radius: 0.004),
		Anchor(long: "Beacon Hill Base", short: "BCNH", lat: 47.5790, lon: -122.3115, radius: 0.008),
		Anchor(long: "West Seattle Junction", short: "WSEA", lat: 47.5615, lon: -122.3865, radius: 0.007),
		Anchor(long: "Georgetown Node", short: "GTWN", lat: 47.5470, lon: -122.3200, radius: 0.005),
		Anchor(long: "Wallingford Relay", short: "WLFD", lat: 47.6615, lon: -122.3345, radius: 0.007),
		Anchor(long: "Greenwood Node", short: "GRNW", lat: 47.6900, lon: -122.3550, radius: 0.007),
		Anchor(long: "Green Lake Beacon", short: "GRNL", lat: 47.6800, lon: -122.3400, radius: 0.0020),
		Anchor(long: "Phinney Ridge", short: "PHNY", lat: 47.6790, lon: -122.3540, radius: 0.006),
		Anchor(long: "Ravenna Node", short: "RAVN", lat: 47.6760, lon: -122.3010, radius: 0.006),
		Anchor(long: "Northgate Relay", short: "NGTE", lat: 47.7075, lon: -122.3255, radius: 0.008),
		Anchor(long: "Maple Leaf Node", short: "MPLF", lat: 47.6960, lon: -122.3170, radius: 0.007),
		Anchor(long: "Central District", short: "CNTD", lat: 47.6060, lon: -122.3010, radius: 0.008),
		Anchor(long: "First Hill Node", short: "FRST", lat: 47.6090, lon: -122.3235, radius: 0.007),
		Anchor(long: "Pike Place Relay", short: "PIKE", lat: 47.6090, lon: -122.3380, radius: 0.0015),
		Anchor(long: "Belltown Node", short: "BELL", lat: 47.6150, lon: -122.3460, radius: 0.0020),
		Anchor(long: "Pioneer Square", short: "PION", lat: 47.6015, lon: -122.3340, radius: 0.0015),
		Anchor(long: "South Lake Union", short: "SLU", lat: 47.6205, lon: -122.3370, radius: 0.0030),
		Anchor(long: "Magnolia Node", short: "MAGN", lat: 47.6465, lon: -122.3985, radius: 0.0030),
		Anchor(long: "Columbia City", short: "COLC", lat: 47.5595, lon: -122.2875, radius: 0.006),
		Anchor(long: "Mount Baker Relay", short: "MTBK", lat: 47.5860, lon: -122.2960, radius: 0.006),
		Anchor(long: "Rainier Valley", short: "RNVL", lat: 47.5470, lon: -122.2800, radius: 0.006),
		Anchor(long: "Bellevue Downtown", short: "BELV", lat: 47.6160, lon: -122.1955, radius: 0.006),
		Anchor(long: "Crossroads Node", short: "XRDS", lat: 47.6180, lon: -122.1290, radius: 0.008),
		Anchor(long: "Redmond Node", short: "RDMD", lat: 47.6730, lon: -122.1180, radius: 0.007),
		Anchor(long: "Kirkland Relay", short: "KIRK", lat: 47.6850, lon: -122.1890, radius: 0.006),
		Anchor(long: "Renton Node", short: "RNTN", lat: 47.4830, lon: -122.2015, radius: 0.007),
		Anchor(long: "Newcastle Node", short: "NWCL", lat: 47.5390, lon: -122.1560, radius: 0.010),
		Anchor(long: "Issaquah Relay", short: "ISQH", lat: 47.5340, lon: -122.0470, radius: 0.010),
		Anchor(long: "Sammamish Node", short: "SAMM", lat: 47.6080, lon: -122.0380, radius: 0.010),
		Anchor(long: "Shoreline Relay", short: "SHOR", lat: 47.7560, lon: -122.3410, radius: 0.010),
		Anchor(long: "Mercer Island", short: "MRCR", lat: 47.5700, lon: -122.2320, radius: 0.006),
		Anchor(long: "Madison Park", short: "MADP", lat: 47.6360, lon: -122.2770, radius: 0.0015)
	]

	/// ~4 nodes per anchor. `> 100` per the marketing brief.
	static var nodeCount: Int { 144 }

	// MARK: Coordinates

	/// Node number for the marketing node at `index`. Mirrors `PerformanceSeedData.seededNodeNum` (base
	/// `0x0A00_0000` + a golden-ratio scramble of the low 24 bits) so the capture coordinator can target
	/// specific seeded nodes (index 0 = the connected/local node, index 1 = the DM partner).
	static func nodeNum(for index: Int) -> Int64 {
		let scrambled = (UInt32(truncatingIfNeeded: index) &* 0x9E3779) & 0x00FF_FFFF
		return 0x0A00_0000 + Int64(scrambled)
	}

	static func coordinate(for index: Int) -> (latitude: Double, longitude: Double) {
		let anchor = anchors[index % anchors.count]
		let ring = index / anchors.count
		guard ring > 0 else { return (anchor.lat, anchor.lon) }
		let dLat = (unit(index * 2 + 1, salt: 0xA0761D6478BD642F) - 0.5) * 2 * anchor.radius
		let dLon = (unit(index * 2 + 2, salt: 0xE7037ED1A0B428DB) - 0.5) * 2 * anchor.radius
		return (anchor.lat + dLat, anchor.lon + dLon)
	}

	// MARK: Node flavor

	static func apply(to node: NodeInfoEntity, user: UserEntity, metadata: DeviceMetadataEntity, index: Int, now: Date) {
		let anchor = anchors[index % anchors.count]
		let ring = index / anchors.count
		let named = name(for: index, anchor: anchor, ring: ring)
		user.longName = named.long
		user.shortName = named.short
		let hw = hardware(for: index)
		user.hwModel = hw.slug
		user.hwModelId = hw.id
		user.hwDisplayName = hw.display
		metadata.hwModel = hw.slug
		metadata.firmwareVersion = firmware(for: index)
		let deviceRole = role(for: index)
		user.role = deviceRole
		metadata.role = deviceRole
		metadata.hasBluetooth = true
		metadata.hasWifi = index % 3 == 0
		user.pkiEncrypted = index % 2 == 0
		user.keyMatch = true
		user.unmessagable = false
		user.isLicensed = index % 4 == 0
		node.favorite = favoriteIndices.contains(index)
		node.ignored = false
		node.channel = 0
		let lastAgo = lastHeardAgo(for: index)
		node.lastHeard = now.addingTimeInterval(-lastAgo)
		node.firstHeard = now.addingTimeInterval(-lastAgo - 86_400 * Double((index % 30) + 3))
		metadata.time = node.lastHeard
		if index == 0 {
			// The connected/local node reports no inbound SNR/RSSI/hops for itself.
			node.hopsAway = 0
			node.viaMqtt = false
			node.snr = 0
			node.rssi = 0
		} else {
			node.hopsAway = Int32(hops(for: index))
			node.viaMqtt = index % 12 == 5
			node.snr = snr(for: index)
			node.rssi = Int32(rssi(for: index))
		}
	}

	private static func name(for index: Int, anchor: Anchor, ring: Int) -> (long: String, short: String) {
		let long: String
		var short: String
		if ring == 0 {
			(long, short) = (anchor.long, anchor.short)
		} else if index % 4 == 0 {
			let call = callsign(index)
			(long, short) = (call, String(call.suffix(4)))
		} else {
			let adjective = handleAdjectives[Int(hash(index, salt: 0x0BAD_C0DE) % UInt64(handleAdjectives.count))]
			let noun = handleNouns[Int(hash(index, salt: 0x600D_F00D) % UInt64(handleNouns.count))]
			long = "\(adjective) \(noun)"
			short = (adjective.prefix(2) + noun.prefix(1)).uppercased() + String((index % 9) + 1)
		}
		// ~50% of nodes use an emoji short name — very common on real meshes, and colorful on the map.
		// Keep the connected node (index 0) textual so the connection indicator reads clearly.
		if index != 0, hash(index, salt: 0x00E5_0421) % 2 == 0 {
			short = emojiShortNames[Int(hash(index, salt: 0x005E_ED1E) % UInt64(emojiShortNames.count))]
		}
		return (long, short)
	}

	/// Single-emoji short names (what real mesh operators often use). One emoji = the node's callsign.
	private static let emojiShortNames = [
		"📡", "🛰️", "🗼", "🌲", "🏔️", "🚀", "🔋", "📶", "⚡️", "🦑", "🐟", "🦀", "🚢", "⛴️", "🏕️",
		"🧭", "🗺️", "📻", "🎒", "🌉", "🦅", "🐿️", "☕️", "🍺", "🎸", "🐙", "🦉", "🌵", "🔦", "🌧️",
		"☀️", "🌊", "🦈", "🚁", "📍", "🏝️", "🧗", "🚲", "🛶", "🦭"
	]

	private static func callsign(_ index: Int) -> String {
		let prefixes = ["K7", "N7", "W7", "KG7", "KI7", "KJ7", "AE7"]
		let letters = Array("ABCDEFGHJKLMNPRSTUVWXYZ")
		func letter(_ salt: UInt64) -> Character { letters[Int(hash(index, salt: salt) % UInt64(letters.count))] }
		return prefixes[index % prefixes.count] + String([letter(0x11), letter(0x22), letter(0x33)])
	}

	private static let handleAdjectives = [
		"Cascade", "Rainier", "Emerald", "Salish", "Olympic", "Sasquatch", "Salmon", "Cedar",
		"Alpine", "Harbor", "Pioneer", "Aurora", "Denny", "Madrona", "Fir", "Orca", "Puget",
		"Evergreen", "Sound", "Ferry"
	]
	private static let handleNouns = [
		"Relay", "Node", "Beacon", "Repeater", "Base", "Station", "Hopper", "Link", "Mesh",
		"Radio", "Tower", "Solar", "Rover", "Tracker"
	]

	/// A curated device. The numeric `id` must match `DeviceHardware.json` so the node-detail hardware
	/// lookup (`DeviceHardwareEntity.hwModel == user.hwModelId`) resolves; every entry here is a
	/// currently-supported device (supportLevel ≥ 1) so none shows the "Discontinued Hardware" banner.
	struct HardwareSpec {
		let slug: String
		let display: String
		let id: Int32
	}

	/// Index 0 (the connected node) is a Seeed Card Tracker T1000-E.
	private static let hardwareModels: [HardwareSpec] = [
		HardwareSpec(slug: "TRACKER_T1000_E", display: "Seeed Card Tracker T1000-E", id: 71),
		HardwareSpec(slug: "HELTEC_V3", display: "Heltec V3", id: 43),
		HardwareSpec(slug: "RAK4631", display: "RAK WisBlock 4631", id: 9),
		HardwareSpec(slug: "T_DECK", display: "LILYGO T-Deck", id: 50),
		HardwareSpec(slug: "SEEED_WIO_TRACKER_L1", display: "Seeed Wio Tracker L1", id: 99),
		HardwareSpec(slug: "HELTEC_WIRELESS_PAPER", display: "Heltec Wireless Paper", id: 49),
		HardwareSpec(slug: "T_ECHO", display: "LILYGO T-Echo", id: 7),
		HardwareSpec(slug: "HELTEC_WIRELESS_TRACKER", display: "Heltec Wireless Tracker V1.1", id: 48),
		HardwareSpec(slug: "NANO_G2_ULTRA", display: "Nano G2 Ultra", id: 18),
		HardwareSpec(slug: "TBEAM", display: "LILYGO T-Beam", id: 4)
	]
	static func hardware(for index: Int) -> HardwareSpec { hardwareModels[index % hardwareModels.count] }

	static func firmware(for index: Int) -> String { index % 6 == 0 ? "2.8.0" : "2.7.4" }

	static func role(for index: Int) -> Int32 {
		if index == 0 { return 0 }          // CLIENT (your node)
		if index % 11 == 3 { return 2 }     // ROUTER
		if index % 17 == 5 { return 4 }     // REPEATER
		if index % 13 == 7 { return 5 }     // TRACKER
		if index % 19 == 9 { return 6 }     // SENSOR
		return 0                            // CLIENT
	}

	private static let favoriteIndices: Set<Int> = [1, 3, 4, 8, 20]

	private static let snrValues: [Float] = [11.75, 9.5, 8.0, 6.25, 10.5, 4.5, 7.25, 2.0, 5.5, -1.5, 3.25, -5.0, 6.75, 1.0, -9.5]
	static func snr(for index: Int) -> Float { snrValues[index % snrValues.count] }

	private static let rssiValues: [Int] = [-52, -61, -68, -74, -58, -83, -71, -95, -79, -104, -88, -112, -66, -99, -115]
	static func rssi(for index: Int) -> Int { rssiValues[index % rssiValues.count] }

	private static let hopValues = [0, 1, 0, 2, 1, 0, 1, 3, 0, 2, 1]
	static func hops(for index: Int) -> Int { hopValues[index % hopValues.count] }

	private static let lastHeardValues: [Double] = [25, 70, 140, 300, 540, 900, 1_500, 2_400, 3_600, 6_300, 10_800, 180, 420, 60]
	static func lastHeardAgo(for index: Int) -> Double { lastHeardValues[index % lastHeardValues.count] + Double(index % 37) }

	private static let batteryBases = [100, 96, 88, 100, 74, 63, 100, 55, 47, 100, 34, 22, 82, 100, 17, 91, 68]
	static func battery(for index: Int, sample: Int) -> Int {
		if index == 0 { return 100 }
		return min(100, max(6, batteryBases[index % batteryBases.count] + sample))
	}

	// MARK: Messages

	static let directMessages = [
		"Hey! Picked up your beacon from Ballard 👋",
		"Nice! I'm running a Heltec V3 on solar up here",
		"Sweet. SNR looks solid — about 8 dB, 1 hop",
		"Same on my end. Coverage across the Sound has been great lately",
		"Want to try a traceroute? Curious what the path looks like",
		"Go for it, I'll watch for it",
		"Sent 📡",
		"Got it — clean 2-hop path through Fremont 🎉",
		"Perfect. Adding you as a favorite",
		"Likewise! You headed to the meetup Saturday?",
		"Planning on it, bringing the T-Beam for range testing",
		"See you there. 73!"
	]

	static let channelMessages = [
		"Morning mesh! Beautiful clear day for some range testing ☀️",
		"New repeater is live on Capitol Hill — downtown coverage is way better now",
		"Anyone else seeing the node over in West Seattle? Strong signal",
		"Field day this Saturday at Gas Works Park, who's in? 🎉",
		"Solar node at the U-District has been up 42 days straight 🔋",
		"Picked up a beacon from Bellevue across the lake, 2 hops",
		"Weather station on Beacon Hill reading 64°F, light breeze",
		"Just flashed firmware 2.7, running smooth so far",
		"Ferry to Bainbridge — dropping off the mesh for a bit ⛴️",
		"Back online from Fremont, that was a long tunnel 🚇",
		"Traceroute from Ballard → Renton, 3 hops, not bad!",
		"Anyone near Green Lake want to test a direct link?",
		"Channel utilization looking healthy tonight, ~6%",
		"Reacquired GPS lock down by the stadiums 📍",
		"Great turnout at the meetup 🙌 welcome to all the new folks",
		"Repeater on Queen Anne is back up after the power blip",
		"Mesh reached all the way out to Redmond today 🌲",
		"Testing a new antenna, SNR jumped 4 dB 📈",
		"Who's running the node up on the Space Needle? 😄",
		"Signing off — great day on the mesh, 73 all"
	]

	static func insertConversations(localUser: UserEntity, remoteUser: UserEntity, channel: ChannelEntity, now: Date, context: ModelContext) {
		// Direct-message thread between the connected node and one nearby node.
		let dmStart = now.addingTimeInterval(-TimeInterval(directMessages.count) * 240 - 120)
		for (i, text) in directMessages.enumerated() {
			let message = MessageEntity()
			message.messageId = 0x0D00_0000 + Int64(i)
			message.channel = 0
			message.messageTimestamp = Int32(dmStart.addingTimeInterval(TimeInterval(i) * 240).timeIntervalSince1970)
			message.messagePayload = text
			message.messagePayloadMarkdown = text
			message.read = true
			message.snr = snr(for: i + 2)
			message.rssi = Int32(rssi(for: i + 2))
			if i.isMultiple(of: 2) {
				message.fromUser = localUser
				message.toUser = remoteUser
				message.realACK = true
				message.receivedACK = true
			} else {
				message.fromUser = remoteUser
				message.toUser = localUser
			}
			context.insert(message)
		}
		remoteUser.lastMessage = now.addingTimeInterval(-240)

		// Primary-channel chatter from a spread of nearby nodes (the last few unread → tab badge).
		var descriptor = FetchDescriptor<UserEntity>()
		descriptor.fetchLimit = 12
		let chatters = ((try? context.fetch(descriptor)) ?? []).filter { $0.num != localUser.num }
		let channelStart = now.addingTimeInterval(-TimeInterval(channelMessages.count) * 360 - 60)
		for (i, text) in channelMessages.enumerated() {
			let message = MessageEntity()
			message.messageId = 0x0F00_0000 + Int64(i)
			message.channel = channel.index
			message.messageTimestamp = Int32(channelStart.addingTimeInterval(TimeInterval(i) * 360).timeIntervalSince1970)
			message.messagePayload = text
			message.messagePayloadMarkdown = text
			message.read = i < channelMessages.count - 3
			message.snr = snr(for: i)
			message.rssi = Int32(rssi(for: i))
			if i % 3 == 2 || chatters.isEmpty {
				message.fromUser = localUser
				message.realACK = true
				message.receivedACK = true
			} else {
				message.fromUser = chatters[i % chatters.count]
			}
			context.insert(message)
		}
	}

	// MARK: Deterministic hashing (self-contained so it doesn't couple to PerformanceSeedData internals)

	private static func hash(_ value: Int, salt: UInt64) -> UInt64 {
		var mixed = UInt64(bitPattern: Int64(value)) &+ salt &+ 0x9E37_79B9_7F4A_7C15
		mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
		mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
		mixed ^= mixed >> 31
		return mixed
	}

	private static func unit(_ value: Int, salt: UInt64) -> Double {
		Double(hash(value, salt: salt) >> 11) / Double(1 << 53)
	}
}
#endif
