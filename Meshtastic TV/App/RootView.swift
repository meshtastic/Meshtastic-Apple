//
//  RootView.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//

import SwiftUI
import UIKit

struct RootView: View {
	@Bindable var client: MeshClient
	@Environment(\.scenePhase) private var scenePhase

	var body: some View {
		Group {
			switch client.state {
			case .connected:
				MapScreen(client: client)
			case .connecting:
				ConnectingView(host: client.host) { client.disconnect() }
			case .disconnected, .failed:
				ConnectView(client: client)
			}
		}
		// Meshtastic brand green (the Live Activity / widget tint).
		.tint(Color("LightIndigo"))
		// This app is a live wall display: keep the big screen awake so the tvOS
		// screensaver never interrupts the mesh map while the app is foregrounded.
		// Re-asserted on every active transition because the system can reset the
		// flag when the app returns to the foreground.
		.onAppear { UIApplication.shared.isIdleTimerDisabled = true }
		.onChange(of: scenePhase) { _, phase in
			UIApplication.shared.isIdleTimerDisabled = (phase == .active)
		}
	}
}

private struct ConnectingView: View {
	let host: String
	let onCancel: () -> Void

	var body: some View {
		VStack(spacing: 48) {
			Image("m-logo-white")
				.resizable()
				.scaledToFit()
				.frame(width: 280)
			ProgressView()
				.scaleEffect(1.6)
				.tint(Color("LightIndigo"))
			Text("Connecting to \(host)…")
				.font(.title2)
				.foregroundStyle(.secondary)
			Button("Cancel", action: onCancel)
		}
	}
}
