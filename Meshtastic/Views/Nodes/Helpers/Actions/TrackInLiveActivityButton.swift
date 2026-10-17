//
//  TrackInLiveActivityButton.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//

import SwiftUI

/// Starts a Live Activity that follows this node, or stops it when this node
/// is the one being tracked. Hidden where Live Activities are off or missing.
struct TrackInLiveActivityButton: View {
	@ObservedObject private var liveActivities = MeshLiveActivityManager.shared
	let nodeNum: Int64

	var body: some View {
		if liveActivities.isAvailable {
			let isTracking = liveActivities.currentMode == .trackNode(num: nodeNum)
			Button {
				if isTracking {
					liveActivities.stop()
				} else {
					liveActivities.start(mode: .trackNode(num: nodeNum))
				}
			} label: {
				Label(
					isTracking ? "Stop Tracking in Live Activity" : "Track in Live Activity",
					systemImage: "platter.filled.bottom.iphone"
				)
			}
		}
	}
}
