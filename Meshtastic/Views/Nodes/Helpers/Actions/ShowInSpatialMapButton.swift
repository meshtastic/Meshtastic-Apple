//
//  ShowInSpatialMapButton.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
#if os(visionOS)
import SwiftUI

/// Opens (or brings forward) the spatial map volume with this node selected.
struct ShowInSpatialMapButton: View {
	let nodeNum: Int64
	@EnvironmentObject private var appState: AppState
	@Environment(\.openWindow) private var openWindow
	@Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

	var body: some View {
		if supportsMultipleWindows {
			Button {
				appState.spatialMapFocus = SpatialMapFocusRequest(nodeNum: nodeNum)
				openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
			} label: {
				Label {
					Text("Show in 3D", comment: "Node detail action: open the spatial map volume at this node")
				} icon: {
					Image("custom.map.wheel")
				}
			}
		}
	}
}
#endif
