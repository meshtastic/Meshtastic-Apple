//
//  BatteryHelper.swift
//  Meshtastic
//
//  Created by Gabe Kangas on 8/6/24.
//

import Foundation
import MeshtasticProtobufs

class BatteryHelper {
	static func getBatteryFromTelemetries(_ telemetries: NSOrderedSet?) -> Double? {
		let deviceMetrics = telemetries?.filtered(using: NSPredicate(format: "metricsType == 0"))
		guard let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity else {
			return nil
		}

		let batteryLevel = Double(mostRecent.batteryLevel)
		return batteryLevel
	}
}
