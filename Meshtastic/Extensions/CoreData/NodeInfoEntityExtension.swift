//
//  NodeInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
import CoreData

extension NodeInfoEntity {

	var latestPosition: PositionEntity? {
		return self.positions?.lastObject as? PositionEntity
	}

	var latestDeviceMetrics: TelemetryEntity? {
		return self.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0")).lastObject as? TelemetryEntity
	}

	var latestEnvironmentMetrics: TelemetryEntity? {
		return self.telemetries?.filtered(using: NSPredicate(format: "metricsType == 1")).lastObject as? TelemetryEntity
	}

	var latestPowerMetrics: TelemetryEntity? {
		return self.telemetries?.filtered(using: NSPredicate(format: "metricsType == 2")).lastObject as? TelemetryEntity
	}

	var hasPositions: Bool {
		return self.positions?.count ?? 0 > 0
	}

	var hasDeviceMetrics: Bool {
		let deviceMetrics = telemetries?.filter { ($0 as AnyObject).metricsType == 0 }
		return deviceMetrics?.count ?? 0 > 0
	}

	var hasEnvironmentMetrics: Bool {
		let environmentMetrics = telemetries?.filter { ($0 as AnyObject).metricsType == 1 }
		return environmentMetrics?.count ?? 0 > 0
	}

	func hasDataForLatestEnvironmentMetrics(attributes: [String]) -> Bool {
		for attribute in attributes {
			guard self.latestEnvironmentMetrics?.entity.attributesByName.keys.contains(attribute) ?? false else {
				return false
			}
			if self.latestEnvironmentMetrics?.value(forKey: attribute) != nil {
				return true
			}
		}
		return false
	}

	var hasDetectionSensorMetrics: Bool {
		return user?.sensorMessageList.count ?? 0 > 0
	}

	var hasPowerMetrics: Bool {
		let powerMetrics = telemetries?.filter { ($0 as AnyObject).metricsType == 2 }
		return powerMetrics?.count ?? 0 > 0
	}

	var hasTraceRoutes: Bool {
		let routes = traceRoutes?.filter { ($0 as AnyObject).response  }
		return routes?.count ?? 0 > 0
	}

	var hasPax: Bool {
		return pax?.count ?? 0 > 0
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
			let adminChannel = myInfo?.channels?.filter { ($0 as AnyObject).name?.lowercased() == "admin" }
			return adminChannel?.count ?? 0 > 0
		}
	}
}

public func createNodeInfo(num: Int64, context: NSManagedObjectContext) -> NodeInfoEntity {

	let newNode = NodeInfoEntity(context: context)
	newNode.id = Int64(num)
	newNode.num = Int64(num)
	let newUser = UserEntity(context: context)
	newUser.num = Int64(num)
	let userId = num.toHex()
	newUser.userId = "!\(userId)"
	let last4 = String(userId.suffix(4))
	newUser.longName = "Meshtastic \(last4)"
	newUser.shortName = last4
	newUser.hwModel = "UNSET"
	newNode.user = newUser
	return newNode
}
