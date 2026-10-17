//
//  WidgetSharedViews.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  Small views the widgets share: the Meshtastic mark, the node chip,
//  the connection dot, the battery readout, and the share card look the
//  map and trace route widgets use.
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

/// Signal quality as bars, 0 (none) to 3 (good).
struct SignalBars: View {
	let rating: Int?

	var body: some View {
		if let rating {
			Image(systemName: "cellularbars", variableValue: Double(rating) / 3)
				.font(.caption)
				.widgetAccentable()
				.accessibilityLabel("Signal \(rating) of 3")
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

// MARK: - Share card look

/// The trace route share image's palette. The map and trace route widgets
/// always use its dark look, like the share image, so they read the same in
/// light and dark mode.
enum ShareCardStyle {
	/// Meshtastic brand green.
	static let brand = Color(red: 0x67 / 255, green: 0xEA / 255, blue: 0x94 / 255)
	static let backgroundTop = Color(red: 0.13, green: 0.14, blue: 0.19)
	static let backgroundBottom = Color(red: 0.07, green: 0.08, blue: 0.10)
	static let panel = Color.white.opacity(0.06)
	static let secondaryText = Color.white.opacity(0.62)
	static let tertiaryText = Color.white.opacity(0.42)
	/// Route colors agreed across clients (meshtastic/design#165).
	static let forward = Color(red: 0xE8 / 255, green: 0x6A / 255, blue: 0x00 / 255)
	static let back = Color(red: 0x00 / 255, green: 0x81 / 255, blue: 0xC7 / 255)
	static let roundTrip = Color.purple

	static var background: some View {
		ZStack {
			LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
			RadialGradient(colors: [brand.opacity(0.2), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
		}
	}
}

/// A map the app rendered. Kept full color on tinted home screens, where an
/// opaque image would otherwise flatten into a solid block.
struct ShareMapImage: View {
	let image: UIImage

	var body: some View {
		if #available(iOS 18.0, *) {
			Image(uiImage: image)
				.resizable()
				.widgetAccentedRenderingMode(.fullColor)
				.scaledToFit()
		} else {
			Image(uiImage: image)
				.resizable()
				.scaledToFit()
		}
	}
}

/// One labeled value in a row of tiles under a large widget's map.
struct ShareStatTile: View {
	let title: LocalizedStringKey
	let value: String
	var color: Color = .white

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			Text(title)
				.font(.system(size: 9, weight: .semibold))
				.foregroundStyle(ShareCardStyle.tertiaryText)
				.lineLimit(1)
			Text(value)
				.font(.caption.weight(.semibold))
				.foregroundStyle(color)
				.lineLimit(1)
				.minimumScaleFactor(0.7)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 7)
		.padding(.vertical, 5)
		.background(ShareCardStyle.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
	}
}

/// A distance for a road-scale readout, in the locale's units.
func shareDistanceText(_ meters: Double) -> String {
	Measurement(value: meters, unit: UnitLength.meters)
		.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
}
