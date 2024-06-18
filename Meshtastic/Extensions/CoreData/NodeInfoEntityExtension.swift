//
//  NodeInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
import CoreData

extension NodeInfoEntity {
	convenience init(
		context: NSManagedObjectContext,
		num: Int
	) {
		self.init(context: context)
		self.id = Int64(num)
		self.num = Int64(num)
		print("MARK: Creating Emtpy User")
		self.user = UserEntity(context: context, num: num)
	}

	var hasPositions: Bool {
		return positions?.count ?? 0 > 0
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
		return user?.sensorMessageList.count ?? 0 > 0
	}

	var hasTraceRoutes: Bool {
		return traceRoutes?.count ?? 0 > 0
	}

	var hasPax: Bool {
		return pax?.count ?? 0 > 0
	}

	var isStoreForwardRouter: Bool {
		return storeForwardConfig?.isRouter ?? false
	}

	var isOnline: Bool {
		let fifteenMinutesAgo = Calendar.current.date(byAdding: .minute, value: -15, to: Date())
		if lastHeard?.compare(fifteenMinutesAgo!) == .orderedDescending {
			 return true
		}
		return false
	}
}
