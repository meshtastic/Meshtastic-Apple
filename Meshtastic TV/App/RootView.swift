//
//  RootView.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//

import SwiftUI

struct RootView: View {
	@Bindable var client: MeshClient

	var body: some View {
		switch client.state {
		case .connected:
			MapScreen(client: client)
		case .connecting:
			ConnectingView(host: client.host) { client.disconnect() }
		case .disconnected, .failed:
			ConnectView(client: client)
		}
	}
}

private struct ConnectingView: View {
	let host: String
	let onCancel: () -> Void

	var body: some View {
		VStack(spacing: 40) {
			ProgressView()
				.scaleEffect(2)
			Text("Connecting to \(host)…")
				.font(.title2)
				.foregroundStyle(.secondary)
			Button("Cancel", action: onCancel)
		}
	}
}
