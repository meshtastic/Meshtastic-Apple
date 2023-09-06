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
}
