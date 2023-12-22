//
//  NodeInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation

extension NodeInfoEntity {
	
	var hasPositions: Bool {
		return positions?.count ?? 0 > 0
	}
	
	var hasDeviceMetrics: Bool {
		let deviceMetrics = telemetries?.filter{ ($0 as AnyObject).metricsType == 0 }
		return deviceMetrics?.count ?? 0 > 0
	}
	
	var hasEnvironmentMetrics: Bool {
		let environmentMetrics = telemetries?.filter{ ($0 as AnyObject).metricsType == 1 }
		return environmentMetrics?.count ?? 0 > 0
	}
	var hasDetectionSensorMetrics: Bool {
		return user?.sensorMessageList.count ?? 0 > 0
	}
	
	var hasTraceRoutes: Bool {
		return traceRoutes?.count ?? 0 > 0
	}
	
	var isOnline: Bool {
		let fifteenMinutesAgo = Calendar.current.date(byAdding: .minute, value: -15, to: Date())
		if lastHeard?.compare(fifteenMinutesAgo!) == .orderedDescending {
			 return true
		}
		return false
	}
}
