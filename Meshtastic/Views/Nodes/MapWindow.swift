// MARK: MapWindow
//
//  MapWindow.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import SwiftUI

/// A standalone map view designed to be opened in a separate window
/// on visionOS and Mac Catalyst.
struct MapWindow: View {

	@EnvironmentObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.scenePhase) private var scenePhase

	var body: some View {
		TabView {
			meshMapView
				.tabItem {
					Label("Mesh Map", systemImage: "map")
				}
		}
		.frame(minWidth: 400, idealWidth: 900, maxWidth: .infinity, minHeight: 300, idealHeight: 700, maxHeight: .infinity)
		.onChange(of: scenePhase) { _, newPhase in
			if newPhase == .background {
				dismissWindow(id: "meshmap-window")
			}
		}
		.onAppear {
			// If the map window is restored on launch without the main window, dismiss it
			let mainScenes = UIApplication.shared.connectedScenes.filter {
				$0.session.configuration.name != "meshmap-window" && $0.activationState != .unattached
			}
			if mainScenes.isEmpty {
				dismissWindow(id: "meshmap-window")
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { _ in
			// Close the map window when the main window is closed
			let remainingScenes = UIApplication.shared.connectedScenes.filter { $0.activationState != .unattached }
			if remainingScenes.count <= 1 {
				dismissWindow(id: "meshmap-window")
			}
		}
	}

	@ViewBuilder
	private var meshMapView: some View {
		#if os(visionOS)
		MeshMap(router: appState.router, showOpenWindowButton: false)
			.toolbar(.hidden, for: .windowToolbar)
			.persistentSystemOverlays(.hidden)
		#else
		MeshMap(router: appState.router, showOpenWindowButton: false)
		#endif
	}
}
