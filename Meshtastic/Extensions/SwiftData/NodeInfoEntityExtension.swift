//
//  NodeInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
@preconcurrency import SwiftData

extension NodeInfoEntity {

	// MARK: - Targeted Fetch Helpers
	// These use FetchDescriptor with fetchLimit to avoid loading entire relationship arrays.

	var latestPosition: PositionEntity? {
		// Fast path: the ingest layer keeps this populated, so reads are O(1).
		if let cached = latestPositionCache {
			return cached
		}
		// Fallback for data created without the cache (migrated / restored / seeded): a sorted
		// limit-1 query. Runs at most once per node until the cache warms on the next position.
		guard let ctx = modelContext else { return nil }
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
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType }
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
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType },
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
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType },
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
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType },
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? ctx.fetch(descriptor).first
	}

	var hasAirQualityMetrics: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 3
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType }
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	var latestPowerMetrics: TelemetryEntity? {
		guard let ctx = modelContext else { return nil }
		let nodeNum = self.num
		let metricsType: Int32 = 2
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType },
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
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType }
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	var hasEnvironmentMetrics: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 1
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType }
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
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType }
		)
		descriptor.fetchLimit = 1
		return ((try? ctx.fetch(descriptor)) ?? []).isEmpty == false
	}

	var latestLocalStats: TelemetryEntity? {
		guard let ctx = modelContext else { return nil }
		let nodeNum = self.num
		let metricsType: Int32 = 4
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType },
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? ctx.fetch(descriptor).first
	}

	var hasLocalStats: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 4
		let descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType }
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
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType },
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
	// `fetch` only sees saved rows; an un-saved insert for this `num` won't appear above.
	if let pending = context.insertedModelsArray.lazy
		.compactMap({ $0 as? UserEntity })
		.first(where: { $0.num == num }) {
		return pending
	}
	let newUser = UserEntity()
	newUser.num = Int64(num)
	let userId = num.toHex()
	newUser.userId = "!\(userId)"
	let last4 = String(userId.suffix(4))
	newUser.longName = "Meshtastic \(last4)"
	newUser.shortName = last4
	newUser.hwModel = "UNSET"
	context.insert(newUser)
	return newUser
}

/// Returns the `NodeInfoEntity` for `num`, creating and inserting a stub only when none exists yet.
///
/// `NodeInfoEntity.num` is `@Attribute(.unique)`. SwiftData resolves unique collisions against the
/// **saved** store only — it does NOT dedup against un-saved inserts pending in the same context.
/// So a plain `fetch`-then-`insert` can leave two pending rows with the same `num` (e.g. a POSITION
/// packet creates a stub before the matching NodeInfo packet arrives, or two packets for a new node
/// arrive back-to-back before a save), which then traps at insert/save time with a SwiftData
/// assertion (`_assertionFailure`, "…remapped to a temporary identifier… fatal logic error in
/// DefaultStore"). Routing every node creation through this helper — which checks pending inserts in
/// addition to the store — guarantees exactly one node per `num`.
func findOrCreateNode(num: Int64, context: ModelContext) -> NodeInfoEntity {
	var descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == num })
	descriptor.fetchLimit = 1
	if let existing = (try? context.fetch(descriptor))?.first {
		return existing
	}
	// `fetch` only sees saved rows; an un-saved insert for this `num` won't appear above.
	if let pending = context.insertedModelsArray.lazy
		.compactMap({ $0 as? NodeInfoEntity })
		.first(where: { $0.num == num }) {
		return pending
	}
	return createNodeInfo(num: num, context: context)
}
