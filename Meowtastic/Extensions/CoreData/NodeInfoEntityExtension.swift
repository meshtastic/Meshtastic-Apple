//
//  NodeInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
import CoreData

extension NodeInfoEntity {
	var hasPositions: Bool {
		positions?.count ?? 0 > 0
	}

	var hasDeviceMetrics: Bool {
		let deviceMetrics = telemetries?.filter { ($0 as AnyObject).metricsType == 0 }
		return deviceMetrics?.count ?? 0 > 0
	}

	var hasEnvironmentMetrics: Bool {
		let environmentMetrics = telemetries?.filter { ($0 as AnyObject).metricsType == 1 }
		return environmentMetrics?.count ?? 0 > 0
	}

	var hasDetectionSensorMetrics: Bool {
		user?.sensorMessageList?.count ?? 0 > 0
	}

	var hasTraceRoutes: Bool {
		traceRoutes?.count ?? 0 > 0
	}

	var hasPax: Bool {
		pax?.count ?? 0 > 0
	}

	var isStoreForwardRouter: Bool {
		storeForwardConfig?.isRouter ?? false
	}

	var isOnline: Bool {
		let fifteenMinutesAgo = Calendar.current.date(byAdding: .minute, value: -15, to: Date())
		if lastHeard?.compare(fifteenMinutesAgo!) == .orderedDescending {
			 return true
		}
		return false
	}
}

public func createNodeInfo(
	num: Int64,
	context: NSManagedObjectContext
) -> NodeInfoEntity {
	let newUser = UserEntity(context: context)
	newUser.num = Int64(num)

	let userId = String(format: "%2X", num)
	newUser.userId = "!\(userId)"

	let last4 = String(userId.suffix(4))

	newUser.longName = "Meshtastic \(last4)"
	newUser.shortName = last4
	newUser.hwModel = "UNSET"

	let newNode = NodeInfoEntity(context: context)
	newNode.id = Int64(num)
	newNode.num = Int64(num)
	newNode.user = newUser

	return newNode
}
