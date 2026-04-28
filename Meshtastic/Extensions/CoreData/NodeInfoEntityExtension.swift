//
//  NodeInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
import SwiftData

extension NodeInfoEntity {

	var latestPosition: PositionEntity? {
		return self.positions.sorted(by: { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }).last
	}

	var latestDeviceMetrics: TelemetryEntity? {
		return self.telemetries.filter { $0.metricsType == 0 }.sorted(by: { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }).last
	}

	var latestEnvironmentMetrics: TelemetryEntity? {
		return self.telemetries.filter { $0.metricsType == 1 }.sorted(by: { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }).last
	}

	var latestPowerMetrics: TelemetryEntity? {
		return self.telemetries.filter { $0.metricsType == 2 }.sorted(by: { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }).last
	}

	var hasPositions: Bool {
		return self.positions.count > 0
	}

	var hasDeviceMetrics: Bool {
		let deviceMetrics = telemetries.filter { $0.metricsType == 0 }
		return deviceMetrics.count > 0
	}

	var hasEnvironmentMetrics: Bool {
		let environmentMetrics = telemetries.filter { $0.metricsType == 1 }
		return environmentMetrics.count > 0
	}

	func hasDataForLatestEnvironmentMetrics(attributes: [String]) -> Bool {
		guard let latest = self.latestEnvironmentMetrics else { return false }
		for attribute in attributes {
			let mirror = Mirror(reflecting: latest)
			if let child = mirror.children.first(where: { $0.label == attribute }) {
				if child.value is Optional<Any> {
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
		return user?.sensorMessageList.count ?? 0 > 0
	}

	var hasPowerMetrics: Bool {
		let powerMetrics = telemetries.filter { $0.metricsType == 2 }
		return powerMetrics.count > 0
	}

	var hasTraceRoutes: Bool {
		let routes = traceRoutes.filter { $0.response }
		return routes.count > 0
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
