//
//  SpatialFeaturesOrnament.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
#if os(visionOS)
import SwiftUI

/// The Vision Pro features beside the main window, under its tab bar: a small glass capsule with
/// a button for each, like the environment button other visionOS apps keep there.
struct SpatialFeaturesOrnament: View {
	@Environment(\.openWindow) private var openWindow
	@Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

	var body: some View {
		VStack(spacing: 8) {
			if supportsMultipleWindows {
				Button {
					openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
				} label: {
					Image("custom.map.wheel")
				}
				.help(String(localized: "Open 3D map", comment: "VoiceOver label for the button that opens the spatial map volume"))
				.accessibilityLabel(String(localized: "Open 3D map", comment: "VoiceOver label for the button that opens the spatial map volume"))
			}
		}
		.buttonStyle(.borderless)
		.buttonBorderShape(.circle)
		.font(.title3)
		.padding(10)
		.glassBackgroundEffect(in: Capsule())
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
