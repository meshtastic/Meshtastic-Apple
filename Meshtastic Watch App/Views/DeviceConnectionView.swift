//
//  DeviceConnectionView.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import SwiftUI

/// Shows the connectivity status between the Watch and the companion
/// iPhone app. Node data is received via WatchConnectivity.
struct DeviceConnectionView: View {

	@ObservedObject var phoneManager: PhoneConnectivityManager

	var body: some View {
		VStack(spacing: 12) {
			if phoneManager.isPhoneReachable {
				reachableView
			} else {
				unreachableView
			}
		}
		.padding()
		.navigationTitle("Phone")
	}

	// MARK: - Phone Reachable

	@ViewBuilder
	private var reachableView: some View {
		Image(systemName: "iphone.radiowaves.left.and.right")
			.font(.title2)
			.foregroundStyle(.green)
		Text("Phone Connected")
			.font(.headline)
		Text("\(phoneManager.nodes.count) nodes")
			.font(.caption2)
			.foregroundStyle(.secondary)

		Button {
			phoneManager.requestRefresh()
		} label: {
			Label("Refresh", systemImage: "arrow.clockwise")
		}
		.buttonStyle(.bordered)
	}

	// MARK: - Phone Unreachable

	@ViewBuilder
	private var unreachableView: some View {
		Image(systemName: "iphone.slash")
			.font(.title2)
			.foregroundStyle(.secondary)
		Text("Phone Not Reachable")
			.font(.headline)

		if phoneManager.hasReceivedData {
			Text("\(phoneManager.nodes.count) cached nodes")
				.font(.caption2)
				.foregroundStyle(.secondary)
		} else {
			Text("Open Meshtastic on your iPhone to sync node data.")
				.font(.caption2)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
	}
}
