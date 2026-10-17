//
//  SpatialFeaturesOrnament.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
#if os(visionOS)
import SwiftUI

/// The Vision Pro features beside the main window, under its tab bar: a small glass capsule with
/// a button for each (the 3D map and the Hardware Showcase), like the environment button other
/// visionOS apps keep there.
struct SpatialFeaturesOrnament: View {
	@Environment(\.openWindow) private var openWindow
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.openImmersiveSpace) private var openImmersiveSpace
	@EnvironmentObject private var appState: AppState
	@Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

	var body: some View {
		// Nothing to open without more windows, so no empty glass either.
		if supportsMultipleWindows {
			VStack(spacing: 8) {
				Button {
					openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
				} label: {
					Image("custom.map.wheel")
				}
				.help(String(localized: "Open 3D map", comment: "VoiceOver label for the button that opens the spatial map volume"))
				.accessibilityLabel(String(localized: "Open 3D map", comment: "VoiceOver label for the button that opens the spatial map volume"))
				Button {
					Task {
						// The room takes over the space, so the 3D map's volume closes.
						if await ShowcaseScene.open(openImmersiveSpace, appState: appState) {
							dismissWindow(id: SpatialMapScene.id)
						}
					}
				} label: {
					Image(systemName: "storefront")
				}
				.help(String(localized: "Enter Showcase", comment: "Spatial map: open the showcase immersive space, closing this volume"))
				.accessibilityLabel(String(localized: "Enter Showcase", comment: "Spatial map: open the showcase immersive space, closing this volume"))
			}
			.buttonStyle(.borderless)
			.buttonBorderShape(.circle)
			.font(.title3)
			.padding(10)
			.glassBackgroundEffect(in: Capsule())
		}
	}
}

extension View {
	/// Hangs `SpatialFeaturesOrnament` off the window's leading edge, below the tab bar.
	func spatialFeaturesOrnament() -> some View {
		// Below the tab bar, which the system centers on this edge, and in line with it.
		// An offset hides an ornament, so padding moves it out from the window instead.
		ornament(attachmentAnchor: .scene(UnitPoint(x: 0, y: 0.8)), contentAlignment: .trailing) {
			SpatialFeaturesOrnament()
				.padding(.trailing, 28)
		}
	}
}
#endif
