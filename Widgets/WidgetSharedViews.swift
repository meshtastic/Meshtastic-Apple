//
//  WidgetSharedViews.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  Small views the widgets share: the Meshtastic mark, the node chip,
//  the connection dot and the battery readout.
//

import SwiftUI
import WidgetKit

/// The Meshtastic mark, picked for the color scheme. The asset is about 2:1,
/// so it is sized by height.
struct MeshLogo: View {
	@Environment(\.colorScheme) private var colorScheme
	let height: CGFloat

	var body: some View {
		Image(colorScheme == .dark ? "m-logo-white" : "m-logo-black")
			.resizable()
			.aspectRatio(contentMode: .fit)
			.frame(height: height)
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

struct ConnectionDot: View {
	let state: WidgetConnectionState

	var body: some View {
		HStack(spacing: 3) {
			Circle()
				.fill(state == .connected ? Color.green : (state == .connecting ? Color.orange : Color.secondary))
				.frame(width: 7, height: 7)
			if state != .connected {
				Text(stateText(state))
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
		.accessibilityLabel(stateText(state))
	}
}

struct BatteryRow: View {
	let level: Int32?
	let font: Font

	var body: some View {
		if let level {
			HStack(spacing: 3) {
				BatteryIcon(batteryLevel: level, font: font, color: .accentColor)
					.widgetAccentable()
				Text(level > 100 ? "Powered" : "\(level)%")
					.font(font)
			}
		}
	}
}

func stateText(_ state: WidgetConnectionState) -> String {
	switch state {
	case .connected:
		return String(localized: "Connected", comment: "Widget connection state label")
	case .connecting:
		return String(localized: "Connecting", comment: "Widget connection state label")
	case .disconnected:
		return String(localized: "Disconnected", comment: "Widget connection state label")
	}
}
