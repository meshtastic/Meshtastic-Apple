//
//  CinemaPanel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
#if os(visionOS)
import SwiftUI

/// The small panel near the viewer in the cinema: which environment to sit in, the 3D map while
/// it is closed, and Leave.
struct CinemaPanel: View {
	@Binding var environment: CinemaEnvironment
	/// Whether the 3D map is showing or on its way; the button to open it is only there while not.
	let spatialMapOpen: Bool
	let onOpenSpatialMap: () -> Void
	let onLeave: () -> Void

	var body: some View {
		VStack(spacing: 12) {
			Picker(String(localized: "Environment", comment: "Cinema: picker for the place the big screen is set in"), selection: $environment) {
				ForEach(CinemaEnvironment.allCases) { environment in
					Text(environment.title).tag(environment)
				}
			}
			.pickerStyle(.menu)
			if !spatialMapOpen {
				Button(action: onOpenSpatialMap) {
					Label {
						Text("Open 3D Map", comment: "Cinema: opens the 3D map volume from the panel in the immersive cinema")
					} icon: {
						Image("custom.map.wheel")
					}
				}
			}
			Button(role: .cancel, action: onLeave) {
				Label(String(localized: "Leave", comment: "Cinema: close the immersive cinema and go back to the app window"), systemImage: "xmark")
			}
		}
		.padding(20)
		.glassBackgroundEffect()
	}
}
#endif
