//
//  MeshActivityAttributes.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/1/23.
//

#if canImport(ActivityKit)

import ActivityKit
import WidgetKit
import SwiftUI

struct MeshActivityAttributes: ActivityAttributes {
	public typealias MyActivityStatus = ContentState
	public struct ContentState: Codable, Hashable {
		// Dynamic stateful properties about your activity go here!
		var timerRange: ClosedRange<Date>
	}

	// Fixed non-changing properties about your activity go here!
	var nodeNum: Int
	var name: String
	var connected: Bool
	var channelUtilization: Float
	var airtime: Float
	var batteryLevel: UInt32
}
#endif
