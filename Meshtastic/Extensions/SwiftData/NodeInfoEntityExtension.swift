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
		guard let ctx = modelContext else { return nil }
		let nodeNum = self.num
		var descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> { $0.nodePosition?.num == nodeNum },
			sortBy: [SortDescriptor(\PositionEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? ctx.fetch(descriptor).first
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
		let descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> { $0.nodePosition?.num == nodeNum }
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0 > 0
	}

	var hasDeviceMetrics: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 0
		let descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType }
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0 > 0
	}

	var hasEnvironmentMetrics: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 1
		let descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType }
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0 > 0
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
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { $0.fromUser?.num == userNum && $0.portNum == portNum }
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0 > 0
	}

	var hasPowerMetrics: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let metricsType: Int32 = 2
		let descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> { $0.nodeTelemetry?.num == nodeNum && $0.metricsType == metricsType }
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0 > 0
	}

	var hasTraceRoutes: Bool {
		guard let ctx = modelContext else { return false }
		let nodeNum = self.num
		let descriptor = FetchDescriptor<TraceRouteEntity>(
			predicate: #Predicate<TraceRouteEntity> { $0.node?.num == nodeNum && $0.response == true }
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0 > 0
	}

	var hasPax: Bool {
		return pax.count > 0
	}

	var isStoreForwardRouter: Bool {
		return storeForwardConfig?.isRouter ?? false
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
	let newUser = UserEntity()
	newUser.num = Int64(num)
	let userId = num.toHex()
	newUser.userId = "!\(userId)"
	let last4 = String(userId.suffix(4))
	newUser.longName = "Meshtastic \(last4)"
	newUser.shortName = last4
	newUser.hwModel = "UNSET"
	newNode.user = newUser
	context.insert(newNode)
	context.insert(newUser)
	return newNode
}
