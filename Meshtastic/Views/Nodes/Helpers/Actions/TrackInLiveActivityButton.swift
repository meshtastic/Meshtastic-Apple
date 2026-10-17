//
//  TrackInLiveActivityButton.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//

import SwiftUI

/// Starts a Live Activity that follows this node, or stops it when this node
/// is the one being tracked. Shown only when a start would go through — Live
/// Activities on, the radio connected and no lockdown — or to stop tracking.
struct TrackInLiveActivityButton: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@ObservedObject private var liveActivities = MeshLiveActivityManager.shared
	let nodeNum: Int64

	private var canStart: Bool {
		liveActivities.isAvailable
			&& accessoryManager.isConnected
			&& accessoryManager.lockdownCoordinator?.isBlockingSession != true
	}

	var body: some View {
		let isTracking = liveActivities.currentMode == .trackNode(num: nodeNum)
		if isTracking || canStart {
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
