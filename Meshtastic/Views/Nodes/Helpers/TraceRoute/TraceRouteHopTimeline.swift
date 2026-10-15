//
//  TraceRouteHopTimeline.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import CoreLocation
import SwiftUI

/// The forward and return paths of a trace route as compact chains of stops, like the share image,
/// with the signal and distance of each leg on one line between them. Side by side when there is room.
struct TraceRouteHopTimeline: View {
	let legs: TraceRouteLegs
	/// Whether a stop can be opened; the connected radio and unknown repeaters can't.
	var canSelectStop: (Int64) -> Bool = { _ in true }
	/// Called with a node number when a stop that can be opened is tapped.
	var onSelectStop: ((Int64) -> Void)?

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass

	var body: some View {
		if legs.back.isEmpty {
			VStack(alignment: .leading, spacing: 10) {
				forwardChain
				Text("No return route was reported.", comment: "Trace route timeline and share image: the response didn't include the path back")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		} else if horizontalSizeClass == .regular {
			HStack(alignment: .top, spacing: 24) {
				forwardChain
				backChain
			}
		} else {
			VStack(alignment: .leading, spacing: 20) {
				forwardChain
				backChain
			}
		}
	}

	/// Smaller circles and gaps once a chain gets long, as on the share image.
	private var dense: Bool { max(legs.forward.count, legs.back.count) > 6 }

	private var forwardChain: some View {
		TraceRouteHopChain(
			title: String(localized: "Forward route", comment: "Trace route timeline: heading for the path towards the target"),
			systemImage: "arrow.down",
			color: TraceRouteColors.forward,
			stops: legs.forward,
			dense: dense,
			startRing: TraceRouteHopChain.originRing,
			endRing: TraceRouteHopChain.destinationRing,
			canSelectStop: canSelectStop,
			onSelectStop: onSelectStop
		)
	}

	private var backChain: some View {
		TraceRouteHopChain(
			title: String(localized: "Return route", comment: "Trace route timeline: heading for the path back from the target"),
			systemImage: "arrow.up",
			color: TraceRouteColors.back,
			stops: legs.back,
			dense: dense,
			startRing: TraceRouteHopChain.destinationRing,
			endRing: TraceRouteHopChain.originRing,
			canSelectStop: canSelectStop,
			onSelectStop: onSelectStop
		)
	}
}

/// One direction of a trace route: node circles joined by lines colored by each leg's signal.
private struct TraceRouteHopChain: View {
	/// The origin keeps the share image's green ring; the destination's white ring becomes the
	/// primary color so it shows on a light background.
	static let originRing = TraceRouteShareStyle.originRing
	static let destinationRing = Color.primary

	let title: String
	let systemImage: String
	let color: Color
	let stops: [TraceRouteStop]
	let dense: Bool
	let startRing: Color
	let endRing: Color
	let canSelectStop: (Int64) -> Bool
	let onSelectStop: ((Int64) -> Void)?

	@Environment(\.dynamicTypeSize) private var dynamicTypeSize

	private var circleSize: CGFloat { dense ? 32 : 36 }
	/// The circle plus room for its ring; the leg lines are centered under it.
	private var circleColumnWidth: CGFloat { circleSize + 6 }
	private var connectorHeight: CGFloat { dense ? 13 : 15 }

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Label(title, systemImage: systemImage)
				.labelStyle(TraceRouteTightLabelStyle())
				.font(.subheadline.weight(.bold))
				.foregroundStyle(color)
				.padding(.bottom, 8)
				.accessibilityAddTraits(.isHeader)
			ForEach(stops) { stop in
				if stop.id > 0 {
					TraceRouteHopLeg(stop: stop, lineWidth: circleColumnWidth, minHeight: connectorHeight)
				}
				stopRow(stop)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder
	private func stopRow(_ stop: TraceRouteStop) -> some View {
		if let onSelectStop, !stop.isUnknownRepeater, canSelectStop(stop.num) {
			Button {
				onSelectStop(stop.num)
			} label: {
				row(stop, showsChevron: true)
			}
			.buttonStyle(.plain)
		} else {
			row(stop, showsChevron: false)
		}
	}

	private func row(_ stop: TraceRouteStop, showsChevron: Bool) -> some View {
		let isStart = stop.id == 0
		let isEnd = stop.id == stops.count - 1
		return HStack(spacing: 10) {
			ZStack(alignment: .topTrailing) {
				TraceRouteShareNodeCircle(
					stop: stop,
					size: circleSize,
					ring: isStart ? startRing : (isEnd ? endRing : nil),
					colors: .app
				)
				// The long name already says "Unknown repeater"; don't read the "?" first.
				.accessibilityHidden(stop.isUnknownRepeater)
				if !isStart && !isEnd {
					TraceRouteHopNumberBadge(number: stop.id)
						// Read as the relay's place in the route, not a bare number.
						.accessibilityLabel(Text("Relay \(stop.id)", comment: "Trace route timeline: VoiceOver label for a relay's number badge, the order the packet reached it"))
				}
			}
			.frame(width: circleColumnWidth)
			name(stop, isEndpoint: isStart || isEnd)
			Spacer(minLength: 0)
			if showsChevron {
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.tertiary)
					.accessibilityHidden(true)
			}
		}
		// Apple's minimum tap height, so stops that open a node are easy to hit.
		.frame(minHeight: 44)
		.contentShape(Rectangle())
		.accessibilityElement(children: .combine)
	}

	/// The name with the MQTT badge beside it when both fit on one line, and under it when not.
	@ViewBuilder
	private func name(_ stop: TraceRouteStop, isEndpoint: Bool) -> some View {
		let text = Text(stop.longName)
			.font(.subheadline.weight(isEndpoint ? .semibold : .regular))
			.foregroundStyle(stop.isUnknownRepeater ? .secondary : .primary)
			// Long names need more lines once the text is large.
			.lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
		if stop.viaMqtt {
			ViewThatFits(in: .horizontal) {
				HStack(spacing: 8) {
					text.fixedSize()
					mqttBadge
				}
				VStack(alignment: .leading, spacing: 3) {
					text.fixedSize(horizontal: false, vertical: true)
					mqttBadge
				}
			}
			.padding(.vertical, 2)
		} else {
			text
				.fixedSize(horizontal: false, vertical: true)
				.padding(.vertical, 2)
		}
	}

	private var mqttBadge: some View {
		HStack(spacing: 3) {
			Image(systemName: "network")
				// VoiceOver reads "MQTT", not "network, MQTT".
				.accessibilityHidden(true)
			Text(verbatim: "MQTT")
		}
		.font(.caption2.weight(.bold))
		.foregroundStyle(Color.purple)
		.padding(.horizontal, 6)
		.padding(.vertical, 2)
		.background(Color.purple.opacity(0.15), in: Capsule())
		.fixedSize()
	}
}

/// The leg arriving at a stop: a short line colored by signal quality, with the SNR, its quality and
/// the distance on one line beside it. The distance moves under the signal when the line doesn't fit,
/// which only happens at the larger text sizes. Dashed gray when the SNR wasn't reported.
private struct TraceRouteHopLeg: View {
	let stop: TraceRouteStop
	let lineWidth: CGFloat
	let minHeight: CGFloat

	private var color: Color { stop.quality?.color ?? .gray }

	private var distance: String? {
		stop.legDistance.map { Measurement(value: $0, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)) }
	}

	var body: some View {
		HStack(spacing: 10) {
			TraceRouteLegLine()
				.stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: stop.snr == nil ? [3, 4] : []))
				.frame(width: lineWidth)
			ViewThatFits(in: .horizontal) {
				HStack(spacing: 4) {
					signal
					if let distance {
						separator
						distanceText(distance)
					}
				}
				.fixedSize()
				VStack(alignment: .leading, spacing: 1) {
					signal
					if let distance {
						distanceText(distance)
					}
				}
			}
			.font(.caption)
			Spacer(minLength: 0)
		}
		.frame(minHeight: minHeight)
		// Sizes the row to its text so the line fills that height instead of growing without limit.
		.fixedSize(horizontal: false, vertical: true)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityText)
	}

	private var separator: some View {
		Text(verbatim: "·")
			.foregroundStyle(.secondary)
	}

	@ViewBuilder
	private var signal: some View {
		if let snr = stop.snr, let quality = stop.quality {
			HStack(spacing: 4) {
				Text(TraceRouteShareCard.decibels(snr))
					.monospacedDigit()
				Text(verbatim: "·")
				Text(quality.description)
			}
			.fontWeight(.semibold)
			.foregroundStyle(color)
		} else {
			Text("Unknown signal", comment: "Trace route timeline: a leg whose SNR wasn't reported")
				.fontWeight(.semibold)
				.foregroundStyle(.secondary)
		}
	}

	private func distanceText(_ distance: String) -> some View {
		Text(distance)
			.foregroundStyle(.secondary)
	}

	/// The signal, its quality word and the distance.
	private var accessibilityText: String {
		var parts: [String] = []
		if let snr = stop.snr, let quality = stop.quality {
			let value = snr.formatted(.number.precision(.fractionLength(1)))
			parts.append(String(localized: "SNR \(value) dB"))
			parts.append(quality.description)
		} else {
			parts.append(String(localized: "Unknown signal", comment: "Trace route timeline: a leg whose SNR wasn't reported"))
		}
		if let distance {
			parts.append(distance)
		}
		return parts.joined(separator: ", ")
	}
}
