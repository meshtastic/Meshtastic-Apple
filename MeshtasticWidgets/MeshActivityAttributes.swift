//
//  MeshActivityAttributes.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2/24/23.
//

import Foundation
import ActivityKit

struct MeshActivityAttributes: ActivityAttributes {
	public typealias MyActivityStatus = ContentState
	
	public struct ContentState: Codable, Hashable {
		var timerRange: ClosedRange<Date>
	}
	
	var nodeNum: Int
	var nodeName: String
	var channelUtilization: Double
	var airtime: Double
	var activityName: String
}
