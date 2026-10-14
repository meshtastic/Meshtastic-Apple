//
//  TraceRouteHopTimeline.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import CoreLocation
import SwiftUI

/// The forward and return paths of a trace route as vertical lists of stops, with the signal and
/// distance of each leg between them. Side by side when there is room.
struct TraceRouteHopTimeline: View {
	let legs: TraceRouteLegs
	/// Whether a stop can be opened; the connected radio and unknown repeaters can't.
	var canSelectStop: (Int64) -> Bool = { _ in true }
	/// Called with a node number when a stop that can be opened is tapped.
	var onSelectStop: ((Int64) -> Void)?

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass

	var body: some View {
		if horizontalSizeClass == .regular && !legs.back.isEmpty {
			HStack(alignment: .top, spacing: 24) {
				forwardSection
				backSection
			}
		} else {
			VStack(alignment: .leading, spacing: 24) {
				forwardSection
				backSection
			}
		}
	}

	private var forwardSection: some View {
		TraceRouteHopColumn(
			title: String(localized: "Forward route", comment: "Trace route timeline: heading for the path towards the target"),
			systemImage: "arrow.down",
			color: TraceRouteColors.forward,
			stops: legs.forward,
			canSelectStop: canSelectStop,
			onSelectStop: onSelectStop
		)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder
	private var backSection: some View {
		if !legs.back.isEmpty {
			TraceRouteHopColumn(
				title: String(localized: "Return route", comment: "Trace route timeline: heading for the path back from the target"),
				systemImage: "arrow.up",
				color: TraceRouteColors.back,
				stops: legs.back,
				canSelectStop: canSelectStop,
				onSelectStop: onSelectStop
			)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}

/// One direction of a trace route.
private struct TraceRouteHopColumn: View {
	let title: String
	let systemImage: String
	let color: Color
	let stops: [TraceRouteStop]
	let canSelectStop: (Int64) -> Bool
	let onSelectStop: ((Int64) -> Void)?

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Label(title, systemImage: systemImage)
				.font(.headline)
				.foregroundStyle(color)
				.padding(.bottom, 8)
			ForEach(stops) { stop in
				if stop.id > 0 {
					TraceRouteLegConnector(stop: stop)
				}
				stopRow(stop)
			}
		}
	}

	@ViewBuilder
	private func stopRow(_ stop: TraceRouteStop) -> some View {
		if let onSelectStop, !stop.isUnknownRepeater, canSelectStop(stop.num) {
			Button {
				onSelectStop(stop.num)
			} label: {
				TraceRouteStopRow(stop: stop, showsChevron: true)
			}
			.buttonStyle(.plain)
		} else {
			TraceRouteStopRow(stop: stop, showsChevron: false)
		}
	}
}

/// Circle size for stops; the connector lines are centered under it.
private let stopCircleSize: CGFloat = 40

private struct TraceRouteStopRow: View {
	let stop: TraceRouteStop
	let showsChevron: Bool

	var body: some View {
		HStack(spacing: 12) {
			if stop.isUnknownRepeater {
				ZStack {
					Circle()
						.strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
					Text(stop.shortName)
						.font(.headline)
						.foregroundStyle(.secondary)
				}
				.frame(width: stopCircleSize, height: stopCircleSize)
				// The long name already says "Unknown repeater"; don't read the "?" first.
				.accessibilityHidden(true)
			} else {
				CircleText(text: stop.shortName, color: Color(UIColor(hex: UInt32(truncatingIfNeeded: stop.num))), circleSize: stopCircleSize)
			}
			VStack(alignment: .leading, spacing: 2) {
				Text(stop.longName)
					.font(.body)
					.foregroundStyle(stop.isUnknownRepeater ? .secondary : .primary)
					.lineLimit(2)
				if stop.viaMqtt {
					Label("MQTT", systemImage: "network")
						.font(.caption2.weight(.semibold))
						.foregroundStyle(.secondary)
				}
			}
			Spacer(minLength: 0)
			if showsChevron {
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.tertiary)
					.accessibilityHidden(true)
			}
		}
		.contentShape(Rectangle())
		.accessibilityElement(children: .combine)
	}
}

/// The leg arriving at a stop: a vertical line colored by signal quality with the SNR and the
/// distance beside it. Dashed gray when the SNR wasn't reported.
private struct TraceRouteLegConnector: View {
	let stop: TraceRouteStop

	private var color: Color { stop.quality?.color ?? .gray }

	var body: some View {
		HStack(spacing: 12) {
			TraceRouteLegLine()
				.stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: stop.snr == nil ? [4, 4] : []))
				.frame(width: stopCircleSize)
			VStack(alignment: .leading, spacing: 2) {
				signalText
					.font(.caption.weight(.medium))
				if let distance = stop.legDistance {
					Text(Measurement(value: distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			Spacer(minLength: 0)
		}
		.frame(minHeight: 44)
		// Sizes the row to its text so the line fills that height instead of growing without limit.
		.fixedSize(horizontal: false, vertical: true)
		.accessibilityElement(children: .combine)
	}

	@ViewBuilder
	private var signalText: some View {
		if let snr = stop.snr, let quality = stop.quality {
			let value = snr.formatted(.number.precision(.fractionLength(1)))
			HStack(spacing: 4) {
				Text("SNR \(value) dB")
				Text(verbatim: "·")
					.foregroundStyle(.secondary)
					.accessibilityHidden(true)
				Text(quality.description)
			}
			.foregroundStyle(color)
		} else {
			Text("Unknown signal", comment: "Trace route timeline: a leg whose SNR wasn't reported")
				.foregroundStyle(.secondary)
		}
	}
}

/// A vertical line down the middle of its frame.
private struct TraceRouteLegLine: Shape {
	func path(in rect: CGRect) -> Path {
		Path { path in
			path.move(to: CGPoint(x: rect.midX, y: rect.minY))
			path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
		}
	}
}
