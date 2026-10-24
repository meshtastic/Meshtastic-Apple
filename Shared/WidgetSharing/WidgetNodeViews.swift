//
//  WidgetNodeViews.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/24/26.
//
//  Small node views the widgets and the app share: the Meshtastic mark, the
//  node chip, the battery readout and the signal bars. Moved here from the
//  widget extension so the visionOS cinema's team board can use them too.
//

import SwiftUI
import WidgetKit

/// The Meshtastic mark in a brand color on every widget: the accent green on
/// dark backgrounds, the primary dark gray on light ones, where green is too
/// faint. The asset is about 2:1, so it is sized by height.
struct MeshLogo: View {
	@Environment(\.colorScheme) private var colorScheme
	let height: CGFloat

	/// Brand accent, #67EA94.
	private static let green = Color(red: 0x67 / 255, green: 0xEA / 255, blue: 0x94 / 255)
	/// Brand primary, #2C2D3C.
	private static let darkGray = Color(red: 0x2C / 255, green: 0x2D / 255, blue: 0x3C / 255)

	var body: some View {
		Image("m-logo-white")
			.renderingMode(.template)
			.resizable()
			.aspectRatio(contentMode: .fit)
			.frame(height: height)
			.foregroundStyle(colorScheme == .dark ? Self.green : Self.darkGray)
	}
}

/// A node's shortname fitted in a circle of its node color — the same look
/// as the app's CircleText annotations. Never a capsule.
struct NodeChip: View {
	let shortName: String
	let colorSeed: UInt32
	let size: CGFloat

	// Accented rendering is left off: tinting flattens the opaque circle and
	// its text to one alpha, leaving an unreadable solid disc.
	var body: some View {
		Text(shortName)
			.font(.system(size: size * 0.34, weight: .bold))
			.minimumScaleFactor(0.4)
			.lineLimit(1)
			.padding(2)
			.foregroundStyle(isLight ? Color.black : Color.white)
			.frame(width: size, height: size)
			.background(Circle().fill(Color(red: red, green: green, blue: blue)))
	}

	// Same derivation the app uses: the node number's low 24 bits as RRGGBB.
	private var red: Double { Double((colorSeed >> 16) & 0xFF) / 255 }
	private var green: Double { Double((colorSeed >> 8) & 0xFF) / 255 }
	private var blue: Double { Double(colorSeed & 0xFF) / 255 }

	// WCAG relative luminance, matching the app's Color.isLight(), so chip text
	// flips black/white at the same colors as in the app.
	private var isLight: Bool {
		func linearize(_ channel: Double) -> Double {
			channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
		}
		let luminance = 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
		return luminance > 0.179
	}
}

struct BatteryRow: View {
	let level: Int32?
	let font: Font
	var color: Color = .accentColor

	var body: some View {
		if let level {
			HStack(spacing: 3) {
				BatteryIcon(batteryLevel: level, font: font, color: color)
					.widgetAccentable()
				Text(level > 100 ? "Powered" : "\(level)%")
					.font(font)
			}
		}
	}
}

/// Signal quality as bars, 0 (none) to 3 (good).
struct SignalBars: View {
	let rating: Int?
	var font: Font = .caption

	var body: some View {
		if let rating {
			Image(systemName: "cellularbars", variableValue: Double(rating) / 3)
				.font(font)
				.widgetAccentable()
				.accessibilityLabel("Signal \(rating) of 3")
		}
	}
}
