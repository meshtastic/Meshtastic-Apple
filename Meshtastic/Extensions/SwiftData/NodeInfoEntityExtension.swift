//
//  NodeInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
@preconcurrency import SwiftData

extension NodeInfoEntity {

	/// Returns this node's user only while both sides of the relationship are still backed by
	/// SwiftData. A node detail view can outlive `clearDatabase`, which removes users before it
	/// removes nodes; reading a persisted property from that deleted user traps in SwiftData.
	var liveUser: UserEntity? {
		guard modelContext != nil, !isDeleted,
			let user,
			user.modelContext != nil, !user.isDeleted
		else { return nil }
		return user
	}

	// MARK: - Targeted Fetch Helpers
	// These use FetchDescriptor with fetchLimit to avoid loading entire relationship arrays.

	var latestPosition: PositionEntity? {
		guard let ctx = modelContext else { return nil }
		// The ingest layer keeps the cache pointed at the latest row, but the handle it hands back
		// can't be trusted on its own. A context only learns about deletes made through itself, so
		// a row the ingest actor deleted and saved still reports `modelContext != nil` and
		// `isDeleted == false` here, and the first persisted-property read on it traps (the node
		// list's top crash). Confirm the row through the store instead: reading persistentModelID
		// on the stale handle is safe, and a fetch loads the row's values, so what it returns can
		// be read even if the row is deleted afterwards.
		if let cached = latestPositionCache {
			let cachedID = cached.persistentModelID
			if (cachedID.storeIdentifier ?? "").isEmpty {
				// A temporary id is this context's own unsaved insert (the ingest actor reads it
				// between debounced saves). No other context can have deleted it, and a fetch by a
				// temporary id is not valid on every OS, so hand it back without the store lookup.
				if cached.modelContext != nil, !cached.isDeleted {
					return cached
				}
			} else {
				var byID = FetchDescriptor<PositionEntity>(
					predicate: #Predicate<PositionEntity> { $0.persistentModelID == cachedID }
				)
				byID.fetchLimit = 1
				if let row = try? ctx.fetch(byID).first {
					return row
				}
			}
		}
		// No cache (migrated / restored / seeded data) or the cached row is gone: a sorted limit-1
		// query. The next position packet warms the cache again.
		let nodeNum = self.num
		var descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> { $0.nodePosition?.num == nodeNum },
			sortBy: [SortDescriptor(\PositionEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? ctx.fetch(descriptor).first
	}

	func positionCount(context: ModelContext? = nil) -> Int {
		guard let ctx = context ?? modelContext else { return 0 }
		let nodeNum = self.num
		let descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> { $0.nodePosition?.num == nodeNum }
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0
	}

	func positionsSortedByTime(context: ModelContext? = nil, ascending: Bool = false, limit: Int? = nil) -> [PositionEntity] {
		guard let ctx = context ?? modelContext else { return [] }
		let nodeNum = self.num
		var descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> { $0.nodePosition?.num == nodeNum },
			sortBy: [SortDescriptor(\PositionEntity.time, order: ascending ? .forward : .reverse)]
		)
		if let limit {
			descriptor.fetchLimit = limit
		}
		return (try? ctx.fetch(descriptor)) ?? []
	}

	func telemetryCount(ofType metricsType: Int32, context: ModelContext? = nil) -> Int {
		guard let ctx = context ?? modelContext else { return 0 }
		let nodeNum = self.num
		let descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType)
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0
	}

	func paxCount(context: ModelContext? = nil) -> Int {
		guard let ctx = context ?? modelContext else { return 0 }
		let nodeNum = self.num
		let descriptor = FetchDescriptor<PaxCounterEntity>(
			predicate: #Predicate<PaxCounterEntity> { $0.paxNode?.num == nodeNum }
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0
	}

	func paxCountersSortedByTime(context: ModelContext? = nil, ascending: Bool = false, limit: Int? = nil) -> [PaxCounterEntity] {
		guard let ctx = context ?? modelContext else { return [] }
		let nodeNum = self.num
		var descriptor = FetchDescriptor<PaxCounterEntity>(
			predicate: #Predicate<PaxCounterEntity> { $0.paxNode?.num == nodeNum },
			sortBy: [SortDescriptor(\PaxCounterEntity.time, order: ascending ? .forward : .reverse)]
		)
		if let limit {
			descriptor.fetchLimit = limit
		}
		return (try? ctx.fetch(descriptor)) ?? []
	}

	var latestDeviceMetrics: TelemetryEntity? {
		guard let ctx = modelContext else { return nil }
		let nodeNum = self.num
		let metricsType: Int32 = 0
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType),
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? ctx.fetch(descriptor).first
	}

	var latestEnvironmentMetrics: TelemetryEntity? {
		guard let ctx = modelContext else { return nil }
		let nodeNum = self.num
		let metricsType: Int32 = 1
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType),
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? ctx.fetch(descriptor).first
	}

	var latestAirQualityMetrics: TelemetryEntity? {
		guard let ctx = modelContext else { return nil }
		let nodeNum = self.num
		let metricsType: Int32 = 3
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType),
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? ctx.fetch(descriptor).first
	}

	/// NowCast-derived AQI (0–500) computed from the last 12 hours of PM2.5 telemetry, or `nil`
	/// when there isn't enough recent history to compute a NowCast. Per design#54, callers should
	/// fall back to showing the raw PM2.5 reading rather than a misleading instantaneous AQI.
	var airQualityNowCastAQI: Int? {
		let twelveHoursAgo = Calendar.current.date(byAdding: .hour, value: -12, to: Date()) ?? .distantPast
		let readings = safeTelemetries(ofType: 3).compactMap { telemetry -> (date: Date, pm25: Double)? in
			guard let time = telemetry.time, time >= twelveHoursAgo, let pm25 = telemetry.pm25Standard else { return nil }
			return (date: time, pm25: Double(pm25))
		}
		return EPAAirQuality.nowCastAQI(from: readings)
	}

	var hasAirQualityMetrics: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 3
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType)
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	var latestPowerMetrics: TelemetryEntity? {
		guard let ctx = modelContext else { return nil }
		let nodeNum = self.num
		let metricsType: Int32 = 2
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType),
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? ctx.fetch(descriptor).first
	}

	var hasPositions: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		var descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> { $0.nodePosition?.num == nodeNum }
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	var hasDeviceMetrics: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 0
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType)
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	var hasEnvironmentMetrics: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 1
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType)
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	func hasDataForLatestEnvironmentMetrics(attributes: [String]) -> Bool {
		guard let latest = self.latestEnvironmentMetrics else { return false }
		for attribute in attributes {
			let mirror = Mirror(reflecting: latest)
			if let child = mirror.children.first(where: { $0.label == attribute }) {
				if child.value is Any? {
					let m = Mirror(reflecting: child.value)
					if m.displayStyle == .optional && m.children.count > 0 {
						return true
					}
				} else {
					return true
				}
			}
		}
		return false
	}

	@MainActor
	var hasDetectionSensorMetrics: Bool {
		guard let ctx = modelContext, let userNum = user?.num else { return false }
		let portNum: Int32 = 10
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { $0.fromUser?.num == userNum && $0.portNum == portNum }
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	var hasPowerMetrics: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 2
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType)
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	var latestLocalStats: TelemetryEntity? {
		guard let ctx = modelContext else { return nil }
		let nodeNum = self.num
		let metricsType: Int32 = 4
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType),
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? ctx.fetch(descriptor).first
	}

	/// The receiving radio's most recent noise floor (dBm) from Local Stats telemetry
	/// (`DeviceMetrics.noise_floor`), or nil when it's absent, zero, or older than the
	/// online threshold (2 h). Used to compute a real link margin (`rssi - noiseFloor`)
	/// for signal-quality rating instead of guessed fixed RSSI thresholds.
	var recentNoiseFloor: Int32? {
		guard let stats = latestLocalStats,
			  let time = stats.time,
			  let noiseFloor = stats.noiseFloor,
			  noiseFloor != 0,
			  let twoHoursAgo = Calendar.current.date(byAdding: .minute, value: -120, to: Date()),
			  time.compare(twoHoursAgo) == .orderedDescending
		else { return nil }
		return noiseFloor
	}

	var hasLocalStats: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 4
		let descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType)
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0 > 0
	}

	var hasTraceRoutes: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		var descriptor = FetchDescriptor<TraceRouteEntity>(
			predicate: #Predicate<TraceRouteEntity> { $0.node?.num == nodeNum }
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	var hasPax: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		var descriptor = FetchDescriptor<PaxCounterEntity>(
			predicate: #Predicate<PaxCounterEntity> { $0.paxNode?.num == nodeNum }
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	var isStoreForwardRouter: Bool {
		return storeForwardConfig?.isRouter ?? false
	}

	/// Safely fetches telemetries of a given type using FetchDescriptor.
	/// This avoids crashes when relationship arrays contain references to deleted entities.
	func safeTelemetries(ofType metricsType: Int32) -> [TelemetryEntity] {
		guard let ctx = modelContext else { return [] }
		let nodeNum = self.num
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: TelemetryEntity.predicate(forNode: nodeNum, metricsType: metricsType),
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 500
		return (try? ctx.fetch(descriptor)) ?? []
	}

	/// Safely fetches trace routes using FetchDescriptor.
	/// This avoids stale relationship arrays after reconnects or restore/import flows.
	func safeTraceRoutes() -> [TraceRouteEntity] {
		guard let ctx = modelContext else { return [] }
		let nodeNum = self.num
		var descriptor = FetchDescriptor<TraceRouteEntity>(
			predicate: #Predicate<TraceRouteEntity> { $0.node?.num == nodeNum },
			sortBy: [SortDescriptor(\TraceRouteEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 500
		return (try? ctx.fetch(descriptor)) ?? []
	}

	/// The radio has not heard this node on its current LoRa settings. MQTT nodes are left out: they
	/// never reach the radio over RF, so the radio can never report them heard.
	var isUnheardOnCurrentLora: Bool {
		heardOnCurrentLora == false && !viaMqtt
	}

	var isOnline: Bool {
		let twoHoursAgo = Calendar.current.date(byAdding: .minute, value: -120, to: Date())
		if lastHeard?.compare(twoHoursAgo!) == .orderedDescending {
			 return true
		}
		return false
	}

	var canRemoteAdmin: Bool {
		if UserDefaults.enableAdministration {
			return true
		} else {
			let adminChannel = myInfo?.channels.filter { $0.name?.lowercased() == "admin" }
			return adminChannel?.count ?? 0 > 0
		}
	}
}

func createNodeInfo(num: Int64, context: ModelContext) -> NodeInfoEntity {

	let newNode = NodeInfoEntity()
	newNode.id = Int64(num)
	newNode.num = Int64(num)
	// Reuse an existing/pending user for this `num` rather than inserting a second one — see
	// `findOrCreateUser`. Inserting a fresh `UserEntity` whose unique `num` collides with a row
	// that already exists (saved or pending) is what trapped here (NodeInfoEntityExtension.swift /
	// UpdateSwiftData.swift SwiftData `_assertionFailure`).
	newNode.user = findOrCreateUser(num: num, context: context)
	context.insert(newNode)
	return newNode
}

/// Returns the `UserEntity` for `num`, creating and inserting a stub only when none exists yet.
///
/// `UserEntity.num` is `@Attribute(.unique)` and carries the same caveat as `NodeInfoEntity` (see
/// `findOrCreateNode`): SwiftData resolves unique collisions against the **saved** store only, not
/// against un-saved inserts pending in the same context. `createNodeInfo` previously inserted a
/// fresh `UserEntity` unconditionally, so whenever a user row for `num` already existed — orphaned,
/// or pending from another packet — while the matching `NodeInfoEntity` did not, that second unique
/// insert trapped with a SwiftData assertion ("…remapped to a temporary identifier… fatal logic
/// error in DefaultStore"). Routing user creation through this helper guarantees one user per `num`.
/// An existing user keeps its real fields; only a brand-new stub gets the "Meshtastic XXXX" default.
func findOrCreateUser(num: Int64, context: ModelContext) -> UserEntity {
	var descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate<UserEntity> { $0.num == num })
	descriptor.fetchLimit = 1
	if let existing = (try? context.fetch(descriptor))?.first {
		return existing
	}
	// A fetch also returns this context's unsaved inserts (`includePendingChanges` defaults to
	// true; checked on this toolchain), so the pending scan below is a backstop, not the usual path.
	if let pending = context.insertedModelsArray.lazy
		.compactMap({ $0 as? UserEntity })
		.first(where: { $0.num == num }) {
		return pending
	}
	let newUser = UserEntity()
	newUser.num = Int64(num)
	// toHex() already prefixes "!", so interpolating another one produced "!!deadbeef"
	// for any node heard before its NodeInfo arrived — visible in message rows, used for
	// search matching, and exported as `userProto.id` onto the mesh.
	let userId = num.toHex()
	newUser.userId = userId
	let last4 = String(userId.suffix(4))
	newUser.longName = "Meshtastic \(last4)"
	newUser.shortName = last4
	newUser.hwModel = "UNSET"
	context.insert(newUser)
	return newUser
}

/// Returns the `NodeInfoEntity` for `num`, creating and inserting a stub only when none exists yet.
///
/// `NodeInfoEntity.num` is `@Attribute(.unique)`, but the constraint is only enforced at save: two
/// pending inserts with the same `num` (a POSITION packet creating a stub before the matching
/// NodeInfo packet arrives, or two packets for a new node back-to-back before a save) trap there
/// with a SwiftData assertion (`_assertionFailure`, "…remapped to a temporary identifier… fatal
/// logic error in DefaultStore"). Routing every node creation through this helper guarantees
/// exactly one node per `num`: the fetch finds pending inserts on the checked toolchain, and the
/// `insertedModelsArray` scan is the backstop.
func findOrCreateNode(num: Int64, context: ModelContext) -> NodeInfoEntity {
	var descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == num })
	descriptor.fetchLimit = 1
	if let existing = (try? context.fetch(descriptor))?.first {
		return existing
	}
	// A fetch also returns this context's unsaved inserts (`includePendingChanges` defaults to
	// true; checked on this toolchain), so the pending scan below is a backstop, not the usual path.
	if let pending = context.insertedModelsArray.lazy
		.compactMap({ $0 as? NodeInfoEntity })
		.first(where: { $0.num == num }) {
		return pending
	}
	return createNodeInfo(num: num, context: context)
}
