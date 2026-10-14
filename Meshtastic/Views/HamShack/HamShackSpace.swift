//
//  HamShackSpace.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import OSLog
import RealityKit
import SwiftUI

/// Root of the ham shack immersive space: the room, placed with the viewer's seat at the origin.
/// Closes itself when the app goes to the background.
struct HamShackSpace: View {
	@EnvironmentObject private var appState: AppState
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

	var body: some View {
		RealityView { content in
			let room = await ShackRoom.load()
			content.add(room.root)
		}
		.onAppear {
			appState.hamShackOpen = true
		}
		.onDisappear {
			appState.hamShackOpen = false
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .background {
				Task { await dismissImmersiveSpace() }
			}
		}
		.trackScreen(.hamShack)
	}
}
#endif
