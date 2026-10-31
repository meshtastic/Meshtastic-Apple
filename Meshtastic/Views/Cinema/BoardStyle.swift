//
//  BoardStyle.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/29/26.
//
#if os(visionOS)
import SwiftUI

/// Marker on a whiteboard, for the boards the cinema draws by hand: the team roster and the status
/// board. The surface matches the blank board in the tent image, which has a light on it so it is
/// this light, and every ink below reads at a WCAG contrast of at least 4.5:1 across the gradient.
/// Top / bottom: ink 7.8 / 6.6, blue 6.8 / 5.7, red 5.7 / 4.8, green 5.7 / 4.8, faded 5.6 / 4.7.
enum BoardStyle {
	static let surface = LinearGradient(
		colors: [Color(red: 184 / 255, green: 164 / 255, blue: 134 / 255), Color(red: 170 / 255, green: 150 / 255, blue: 121 / 255)],
		startPoint: .top,
		endPoint: .bottom
	)
	static let ink = Color(red: 0.07, green: 0.07, blue: 0.08)
	static let blue = Color(red: 0.04, green: 0.10, blue: 0.33)
	static let red = Color(red: 0.38, green: 0.02, blue: 0.02)
	static let green = Color(red: 0, green: 0.21, blue: 0.07)
	/// The star before the favorites title. Decoration, outlined in ink, so it needn't meet the contrast.
	static let gold = Color(red: 0.96, green: 0.76, blue: 0.12)
	/// Nodes not heard lately, hints and missing values.
	static let faded = Color(red: 0.19, green: 0.18, blue: 0.17)

	/// The board's handwriting, falling back to the system font where Chalkboard isn't installed.
	static func marker(_ size: CGFloat) -> Font {
		.custom("ChalkboardSE-Regular", fixedSize: size)
	}
}
#endif
