//
//  TraceRouteCard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import SwiftUI

/// Route colors for every trace route surface: the log chart and cards, the hop timeline, the map,
/// the share image and Vision Pro. Forward and return match the Android app's outgoing and return
/// routes, a pair that reads on light and dark maps and for most color-blind viewers. They are
/// fixed values rather than system colors, so they look the same in light, dark and on Vision Pro.
enum TraceRouteColors {
	/// Orange, #E86A00.
	static let forward = Color(red: 0xE8 / 255, green: 0x6A / 255, blue: 0x00 / 255)
	/// Blue, #0081C7.
	static let back = Color(red: 0x00 / 255, green: 0x81 / 255, blue: 0xC7 / 255)
	/// Purple, so the round trip doesn't read as either direction.
	static let roundTrip = Color.purple
}

/// One trace route in a log: when, what came back, and chips for the hop counts and round trip.
struct TraceRouteCard: View {
	let model: TraceRouteCardModel
	/// "Observed" or "Requested" under the title in the app-wide log.
	var showsOrigin = false

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: systemImage)
				.symbolRenderingMode(.hierarchical)
				.font(.title2)
				.foregroundStyle(iconColor)
				.frame(width: 32)
			VStack(alignment: .leading, spacing: 4) {
				if let title = model.title {
					Text(title)
						.font(.callout)
						.fontWeight(.medium)
				}
				Text(model.summary)
					.font(.headline)
				if let date = model.date {
					Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				if model.hasRoute {
					chips
				}
				if showsOrigin {
					Text(model.state == .observed ? "Observed" : "Requested")
						.font(.caption2)
						.foregroundStyle(model.state == .observed ? Color.orange : Color.accentColor)
				}
			}
			Spacer(minLength: 0)
		}
		.padding(.vertical, 4)
		.accessibilityElement(children: .combine)
	}

	private var systemImage: String {
		if model.hasRoute && model.hopsTowards == 0 {
			return "person.line.dotted.person"
		}
		return model.state.systemImage
	}

	private var iconColor: Color {
		switch model.state {
		case .complete, .observed: .accentColor
		case .pending: .secondary
		case .noResponse, .rateLimited: .orange
		}
	}

	private var chips: some View {
		ViewThatFits(in: .horizontal) {
			HStack(spacing: 6) { chipContent }
			VStack(alignment: .leading, spacing: 4) { chipContent }
		}
	}

	@ViewBuilder
	private var chipContent: some View {
		TraceRouteChip(
			systemImage: "arrow.right",
			text: TraceRouteCardModel.hops(model.hopsTowards),
			color: TraceRouteColors.forward,
			accessibilityLabel: String(localized: "Forward hops", comment: "Trace route: hop count towards the target")
		)
		if let hopsBack = model.hopsBack {
			TraceRouteChip(
				systemImage: "arrow.left",
				text: TraceRouteCardModel.hops(hopsBack),
				color: TraceRouteColors.back,
				accessibilityLabel: String(localized: "Return hops", comment: "Trace route: hop count on the way back")
			)
		}
		if let roundTrip = model.roundTrip {
			TraceRouteChip(
				systemImage: "timer",
				text: TraceRouteCardModel.formattedRoundTrip(roundTrip),
				color: TraceRouteColors.roundTrip,
				accessibilityLabel: String(localized: "Round trip", comment: "Trace route: time from sending the request to getting the response")
			)
		}
	}
}

/// A small colored capsule with an icon and a value.
struct TraceRouteChip: View {
	let systemImage: String
	let text: String
	let color: Color
	let accessibilityLabel: String

	var body: some View {
		HStack(spacing: 4) {
			Image(systemName: systemImage)
				.foregroundStyle(color)
			// Primary text, not the route color: the route colors are too light for small text.
			Text(text)
				.foregroundStyle(.primary)
		}
		.font(.caption.weight(.medium))
		.padding(.horizontal, 8)
		.padding(.vertical, 3)
		.background(color.opacity(0.15), in: Capsule())
		.fixedSize()
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityLabel)
		.accessibilityValue(text)
	}
}
