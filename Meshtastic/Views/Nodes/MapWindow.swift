// MARK: MapWindow
//
//  MapWindow.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import SwiftUI
import OSLog

/// A standalone map view designed to be opened in a separate window
/// on visionOS and Mac Catalyst.
struct MapWindow: View {

	@EnvironmentObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var router: Router
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.scenePhase) private var scenePhase
	@AppStorage("isMeshMapWindowOpen") private var isMeshMapWindowOpen = false
	@AppStorage("meshMapWindowOpenRequested") private var meshMapWindowOpenRequested = false

	var body: some View {
		TabView {
			meshMapView
				.tabItem {
					Label("Mesh Map", systemImage: "map")
				}
		}
		.frame(minWidth: 400, idealWidth: 900, maxWidth: .infinity, minHeight: 300, idealHeight: 700, maxHeight: .infinity)
		.onChange(of: scenePhase) { _, newPhase in
			// Note: On Mac Catalyst, switching focus between windows puts the
			// unfocused window in .background — do NOT dismiss or reset state here.
			// The window lifecycle is handled by onDisappear and didDisconnectNotification.
		}
		.onAppear {
			// If the map window is restored on launch without the main window, dismiss it
			let mainScenes = UIApplication.shared.connectedScenes.filter {
				$0.session.configuration.name != "meshmap-window" && $0.activationState != .unattached
			}
			if mainScenes.isEmpty {
				isMeshMapWindowOpen = false
				meshMapWindowOpenRequested = false
				router.mapWindowOpen = false
				dismissWindow(id: "meshmap-window")
				return
			}

			// Only allow this window when explicitly requested from the primary map.
			// This prevents system-restored secondary windows from launching with the app.
			if !meshMapWindowOpenRequested {
				isMeshMapWindowOpen = false
				router.mapWindowOpen = false
				dismissWindow(id: "meshmap-window")
				return
			}

			// Mark the map window as open — this covers both the explicit open path
			// (where MeshMap already set this) and any system restore that we allow.
			meshMapWindowOpenRequested = false
			isMeshMapWindowOpen = true
			router.mapWindowOpen = true
			Logger.services.info("🗺️ [MapWindow] onAppear — set mapWindowOpen = true")
		}
		.onDisappear {
			isMeshMapWindowOpen = false
			meshMapWindowOpenRequested = false
			router.mapWindowOpen = false
		}
		.onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { _ in
			// Close the map window when the main window is closed
			let remainingScenes = UIApplication.shared.connectedScenes.filter { $0.activationState != .unattached }
			if remainingScenes.count <= 1 {
				isMeshMapWindowOpen = false
				meshMapWindowOpenRequested = false
				router.mapWindowOpen = false
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
