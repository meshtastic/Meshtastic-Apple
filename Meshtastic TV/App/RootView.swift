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
#if DEBUG
			if CommandLine.arguments.contains("-tv-show-settings") {
				NavigationStack { SettingsView() }
			} else {
				content
			}
#else
			content
#endif
		}
		// Buttons and icons follow the app AccentColor (Blue 700, matching the iOS
		// app). The brand green fails WCAG contrast for interactive elements, so it's
		// reserved for the logo and semantic success — never an app-wide UI tint.
		// This app is a live wall display: keep the big screen awake so the tvOS
		// screensaver never interrupts the mesh map while the app is foregrounded.
		// Re-asserted on every active transition because the system can reset the
		// flag when the app returns to the foreground.
		.onAppear { UIApplication.shared.isIdleTimerDisabled = true }
#if DEBUG
		.task {
			// Headless-testing hook (MarketingCapture / SwitchStress pattern): launch with
			// `-tv-connect host:port` to connect without driving the remote. MeshClient
			// consumes `-tv-simulate-abort-after seconds` after config completes and accepts
			// `-tv-reconnect-port port` for deterministic failure injection. Debug only.
			guard let index = CommandLine.arguments.firstIndex(of: "-tv-connect"),
			      index + 1 < CommandLine.arguments.count else { return }
			let parts = CommandLine.arguments[index + 1].split(separator: ":")
			guard parts.count == 2, let port = Int(parts[1]), (1...65535).contains(port) else { return }
			client.connect(host: String(parts[0]), port: port)
		}
#endif
		.onChange(of: scenePhase) { _, phase in
			UIApplication.shared.isIdleTimerDisabled = (phase == .active)
		}
	}

	@ViewBuilder
	private var content: some View {
		switch client.state {
		case .connected:
			MapScreen(client: client)
		case .connecting:
			ConnectingView(host: client.host, mode: .connecting) { client.disconnect() }
		case .reconnecting(let attempt, let maxAttempts):
			ConnectingView(host: client.host, mode: .reconnecting(attempt: attempt, maxAttempts: maxAttempts)) {
				client.disconnect()
			}
		case .disconnected, .failed:
			ConnectView(client: client)
		}
	}
}

private struct ConnectingView: View {
	enum Mode {
		case connecting
		case reconnecting(attempt: Int, maxAttempts: Int)
	}

	let host: String
	let mode: Mode
	let onCancel: () -> Void

	var body: some View {
		VStack(spacing: 48) {
			Image(decorative: "m-logo-white")
				.resizable()
				.scaledToFit()
				.frame(width: 280)
			ProgressView()
				.scaleEffect(1.6)
			switch mode {
			case .connecting:
				Text("Connecting to \(host)…")
					.font(.title2)
					.foregroundStyle(.secondary)
			case .reconnecting(let attempt, let maxAttempts):
				Text("Connection interrupted. Reconnecting…")
					.font(.title2)
					.foregroundStyle(.secondary)
				Text("Attempt \(attempt) of \(maxAttempts)")
					.font(.callout)
					.foregroundStyle(.tertiary)
			}
			Button("Cancel", action: onCancel)
		}
	}
}
