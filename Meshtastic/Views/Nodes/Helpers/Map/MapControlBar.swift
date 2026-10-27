//
//  MapControlBar.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/26/26.
//

import SwiftUI

/// The map's own buttons stacked in one bar, like the Maps app's: icons in the text color on Liquid
/// Glass, not the accent color.
struct MapControlBar<Content: View>: View {
	@ViewBuilder let content: () -> Content

	var body: some View {
		VStack(spacing: 0) {
			content()
		}
		.buttonStyle(MapControlButtonStyle())
		.modifier(MapControlBarBackground())
	}
}

private struct MapControlButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 20, weight: .medium))
			.foregroundStyle(.primary)
			.frame(width: 48, height: 48)
			.contentShape(Rectangle())
			.opacity(configuration.isPressed ? 0.5 : 1)
			#if os(visionOS)
			.hoverEffect()
			#endif
	}
}

private struct MapControlBarBackground: ViewModifier {
	func body(content: Content) -> some View {
		#if os(visionOS)
		content.glassBackgroundEffect(in: Capsule())
		#else
		if #available(iOS 26.0, macCatalyst 26.0, *) {
			content.glassEffect(.regular.interactive(), in: Capsule())
		} else {
			content
				.background(.regularMaterial, in: Capsule())
				.shadow(color: .black.opacity(0.2), radius: 2, y: 1)
		}
		#endif
	}
}
