//
//  WidgetSharedViews.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  Small views the widgets share: the connection dot and the share card
//  look the map and trace route widgets use. The node chip, battery and
//  signal views are in Shared/WidgetSharing/WidgetNodeViews.swift, which
//  the app compiles too.
//

import SwiftUI
import WidgetKit

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
