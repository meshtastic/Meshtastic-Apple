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
	public typealias MeshActivityStatus = ContentState
	public struct ContentState: Codable, Hashable {
		// Dynamic stateful properties about your activity go here!
		var uptimeSeconds: UInt32
		var channelUtilization: Float
		var airtime: Float
		var sentPackets: UInt32
		var receivedPackets: UInt32
		var badReceivedPackets: UInt32
		var nodesOnline: UInt32
		var totalNodes: UInt32
		var timerRange: ClosedRange<Date>
	}

	// Fixed non-changing properties about your activity go here!
	var nodeNum: Int
	var name: String
}
#endif
