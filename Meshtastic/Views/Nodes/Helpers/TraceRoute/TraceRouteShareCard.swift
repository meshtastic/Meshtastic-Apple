//
//  TraceRouteShareCard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import MapKit
import SwiftUI

/// Colors and sizes for the share image. It always uses the dark Meshtastic look so it reads the
/// same in whatever app it's posted to, whatever the sender's appearance setting.
enum TraceRouteShareStyle {
	/// Meshtastic brand green.
	static let brand = Color(red: 0x67 / 255, green: 0xEA / 255, blue: 0x94 / 255)
	static let backgroundTop = Color(red: 0.13, green: 0.14, blue: 0.19)
	static let backgroundBottom = Color(red: 0.07, green: 0.08, blue: 0.10)
	static let panel = Color.white.opacity(0.06)
	static let panelBorder = Color.white.opacity(0.08)
	static let primaryText = Color.white
	static let secondaryText = Color.white.opacity(0.62)
	static let tertiaryText = Color.white.opacity(0.42)
	/// Ring around the origin's circle, on the map and in the chain.
	static let originRing = brand
	/// Ring around the destination's circle.
	static let destinationRing = Color.white

	/// Width of the image in points; rendered at 2.5x for 1800 pixels.
	static let width: CGFloat = 720
	/// Height of the image in points when the content is short (1400 pixels at 2.5x), so even a
	/// direct route stays close to square.
	static let minimumHeight: CGFloat = 560
	static let margin: CGFloat = 28
	static var contentWidth: CGFloat { width - margin * 2 }
	/// Gap between the two columns, and between the map and the stats under it.
	static let columnSpacing: CGFloat = 16
	/// Width of the map in the left column.
	static let mapWidth: CGFloat = 356
	/// Width of the hop chains in the right column, beside the map.
	static var chainColumnWidth: CGFloat { contentWidth - mapWidth - columnSpacing }
}

/// The trace route share image: the Meshtastic wordmark, the route and its date, then the map with
/// the stats under it on the left and both hop chains on the right. Without a map the stats run
/// across the top and the chains sit side by side under them.
struct TraceRouteShareCard: View {
	let model: TraceRouteShareModel
	/// The map tiles for `model.map`; nil leaves the map out.
	let mapImage: UIImage?
	/// False leaves out the margin, minimum height and background, for a view that draws the
	/// background itself, sized to its own frame. The share image keeps them.
	var framed = true

	private typealias Style = TraceRouteShareStyle

	var body: some View {
		if framed {
			content
				.padding(Style.margin)
				.frame(width: Style.width, alignment: .topLeading)
				.frame(minHeight: Style.minimumHeight, alignment: .top)
				.background(TraceRouteShareBackground())
				.environment(\.colorScheme, .dark)
		} else {
			content
				.frame(width: Style.contentWidth, alignment: .topLeading)
				.environment(\.colorScheme, .dark)
		}
	}

	private var content: some View {
		VStack(alignment: .leading, spacing: 0) {
			header
			// When the content is shorter than the minimum height, the spacers on either side of the
			// body share the extra space so it sits in the middle rather than leaving a gap at the bottom.
			Spacer(minLength: 18)
			Group {
				if let map = model.map, let mapImage {
					HStack(alignment: .top, spacing: Style.columnSpacing) {
						VStack(spacing: Style.columnSpacing) {
							TraceRouteShareMap(frame: map, image: mapImage, legs: model.legs)
							TraceRouteShareStats(model: model, columns: 2)
						}
						.frame(width: Style.mapWidth)
						TraceRouteShareChains(model: model, sideBySide: false)
							.frame(width: Style.chainColumnWidth)
					}
				} else {
					VStack(alignment: .leading, spacing: 18) {
						TraceRouteShareStats(model: model, columns: nil)
						TraceRouteShareChains(model: model, sideBySide: true)
					}
				}
			}
			Spacer(minLength: 16)
			footer
		}
	}

	// MARK: Header

	/// The wordmark as the title, "Trace Route" under it, then origin → destination. The date sits
	/// on the right.
	private var header: some View {
		HStack(alignment: .top, spacing: 16) {
			VStack(alignment: .leading, spacing: 0) {
				Image(decorative: "meshtastic-wordmark-white")
					.resizable()
					.scaledToFit()
					.frame(height: 28)
					.padding(.bottom, 12)
				Text("Trace Route")
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(Style.brand)
					.padding(.bottom, 2)
				if let origin = model.origin, let destination = model.destination {
					HStack(alignment: .firstTextBaseline, spacing: 10) {
						Text(routeTitle(origin: origin, destination: destination))
							.font(.system(size: 22, weight: .semibold))
							.foregroundStyle(Style.primaryText)
							.lineLimit(2)
							.minimumScaleFactor(0.75)
							.fixedSize(horizontal: false, vertical: true)
						if model.observed {
							Text("Observed")
								.font(.system(size: 12, weight: .semibold))
								.foregroundStyle(Color.orange)
								.padding(.horizontal, 8)
								.padding(.vertical, 3)
								.background(Color.orange.opacity(0.15), in: Capsule())
								.fixedSize()
						}
					}
				}
			}
			Spacer(minLength: 0)
			if let date = model.date {
				VStack(alignment: .trailing, spacing: 2) {
					Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
					Text(date.formatted(.dateTime.hour().minute()))
				}
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(Style.secondaryText)
				.fixedSize()
			}
		}
	}

	/// "Origin → Destination" with the arrow in the round trip purple, since the route runs both ways.
	private func routeTitle(origin: TraceRouteStop, destination: TraceRouteStop) -> AttributedString {
		var arrow = AttributedString(" → ")
		arrow.foregroundColor = TraceRouteColors.roundTrip
		return AttributedString(origin.longName) + arrow + AttributedString(destination.longName)
	}

	static func decibels(_ snr: Float) -> String {
		"\(snr.formatted(.number.precision(.fractionLength(1)))) dB"
	}

	// MARK: Footer

	private var footer: some View {
		VStack(spacing: 10) {
			Rectangle()
				.fill(Style.panelBorder)
				.frame(height: 1)
			// The wordmark at the top already names the app, so the footer only carries the site.
			Text(verbatim: "meshtastic.org")
				.font(.system(size: 15, weight: .semibold))
				.foregroundStyle(Style.brand)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}

/// The share image's background: dark with a faint green glow from the top left. `glowRadius`
/// scales the glow for a background drawn larger than the image.
struct TraceRouteShareBackground: View {
	var glowRadius: CGFloat = 460

	var body: some View {
		ZStack {
			LinearGradient(colors: [TraceRouteShareStyle.backgroundTop, TraceRouteShareStyle.backgroundBottom], startPoint: .top, endPoint: .bottom)
			RadialGradient(
				colors: [TraceRouteShareStyle.brand.opacity(0.2), .clear],
				center: .topLeading,
				startRadius: 0,
				endRadius: glowRadius
			)
		}
	}
}

/// Hops, round trip, distance and the SNR range as tiles: in a grid of `columns` under the map, or
/// in one row across the image when there's no map.
struct TraceRouteShareStats: View {
	let model: TraceRouteShareModel
	/// Tiles per row; nil puts them all in one row.
	let columns: Int?

	private typealias Style = TraceRouteShareStyle

	var body: some View {
		let tiles = self.tiles
		let perRow = max(columns ?? tiles.count, 1)
		let rows = stride(from: 0, to: tiles.count, by: perRow).map { Array(tiles[$0..<min($0 + perRow, tiles.count)]) }
		VStack(spacing: 10) {
			ForEach(rows.indices, id: \.self) { row in
				HStack(spacing: 10) {
					ForEach(rows[row].indices, id: \.self) { rows[row][$0] }
				}
			}
		}
		// Never squeezed shorter than its content, which would shrink the values to fit.
		.fixedSize(horizontal: false, vertical: true)
	}

	private var tiles: [AnyView] {
		var tiles: [AnyView] = []
		tiles.append(AnyView(tile(
			label: String(localized: "Hops"),
			systemImage: "point.3.connected.trianglepath.dotted"
		) {
			HStack(spacing: 10) {
				HStack(spacing: 3) {
					Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
					Text(verbatim: "\(model.hopsTowards)")
				}
				.foregroundStyle(TraceRouteColors.forward)
				if let back = model.hopsBack {
					HStack(spacing: 3) {
						Image(systemName: "arrow.left").font(.system(size: 15, weight: .bold))
						Text(verbatim: "\(back)")
					}
					.foregroundStyle(TraceRouteColors.back)
				}
			}
		}))
		if let roundTrip = model.roundTrip {
			tiles.append(AnyView(tile(
				label: String(localized: "Round trip", comment: "Trace route: time from sending the request to getting the response"),
				systemImage: "timer"
			) {
				Text(TraceRouteCardModel.formattedRoundTrip(roundTrip))
					.foregroundStyle(Style.primaryText)
			}))
		}
		if let distance = model.routeDistance {
			tiles.append(AnyView(tile(label: String(localized: "Distance"), systemImage: "ruler") {
				Text(Measurement(value: distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
					.foregroundStyle(Style.primaryText)
			}))
		}
		if let snr = snrTile {
			tiles.append(snr)
		}
		return tiles
	}

	private var snrTile: AnyView? {
		guard let best = model.bestLeg, let bestSnr = best.snr else { return nil }
		let worst = model.worstLeg.flatMap { $0 == best ? nil : $0 }
		let label = worst == nil
			? String(localized: "SNR")
			: String(localized: "Best / worst SNR", comment: "Trace route share image: the highest and lowest SNR of the legs")
		return AnyView(tile(label: label, systemImage: "cellularbars") {
			HStack(spacing: 6) {
				Text(TraceRouteShareCard.decibels(bestSnr))
					.foregroundStyle(best.quality?.color ?? Style.primaryText)
				if let worst, let worstSnr = worst.snr {
					Text(verbatim: "/")
						.foregroundStyle(Style.tertiaryText)
					Text(TraceRouteShareCard.decibels(worstSnr))
						.foregroundStyle(worst.quality?.color ?? Style.primaryText)
				}
			}
		})
	}

	private func tile<Value: View>(label: String, systemImage: String, @ViewBuilder value: () -> Value) -> some View {
		VStack(alignment: .leading, spacing: 5) {
			value()
				.font(.system(size: 20, weight: .semibold, design: .rounded))
				.monospacedDigit()
				.lineLimit(1)
				.minimumScaleFactor(0.6)
			Label(label, systemImage: systemImage)
				.labelStyle(TraceRouteTightLabelStyle())
				.font(.system(size: 11, weight: .semibold))
				.textCase(.uppercase)
				.foregroundStyle(Style.secondaryText)
				.lineLimit(1)
				.minimumScaleFactor(0.7)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 11)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Style.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Style.panelBorder))
	}
}

/// Icon and title side by side with a small gap, for the stat tiles and the timeline headings.
struct TraceRouteTightLabelStyle: LabelStyle {
	func makeBody(configuration: Configuration) -> some View {
		HStack(spacing: 4) {
			configuration.icon
			configuration.title
		}
	}
}

/// Both hop chains: stacked in the column beside the map, or side by side across the image when
/// there's no map. A route without a return path shows the forward chain and a note.
struct TraceRouteShareChains: View {
	let model: TraceRouteShareModel
	let sideBySide: Bool

	private typealias Style = TraceRouteShareStyle

	var body: some View {
		if model.legs.back.isEmpty {
			VStack(alignment: .leading, spacing: 10) {
				forward
				Text("No return route was reported.", comment: "Trace route timeline and share image: the response didn't include the path back")
					.font(.system(size: 13))
					.foregroundStyle(Style.tertiaryText)
			}
		} else if sideBySide {
			HStack(alignment: .top, spacing: Style.columnSpacing) {
				forward
				back
			}
		} else {
			VStack(spacing: Style.columnSpacing) {
				forward
				back
			}
		}
	}

	/// Smaller circles and rows once a chain gets long, so a long route doesn't run far down.
	private var dense: Bool { max(model.legs.forward.count, model.legs.back.count) > 6 }

	private var forward: some View {
		TraceRouteShareChain(
			title: String(localized: "Forward route", comment: "Trace route timeline: heading for the path towards the target"),
			systemImage: "arrow.down",
			color: TraceRouteColors.forward,
			stops: model.legs.forward,
			dense: dense,
			showsDistance: model.legs.back.isEmpty || !sideBySide,
			startRing: Style.originRing,
			endRing: Style.destinationRing
		)
	}

	private var back: some View {
		TraceRouteShareChain(
			title: String(localized: "Return route", comment: "Trace route timeline: heading for the path back from the target"),
			systemImage: "arrow.up",
			color: TraceRouteColors.back,
			stops: model.legs.back,
			dense: dense,
			showsDistance: !sideBySide,
			startRing: Style.destinationRing,
			endRing: Style.originRing
		)
	}
}

/// Colors for `TraceRouteShareNodeCircle`: light on dark for the share image and the map, or
/// system colors that follow the appearance in the app's lists.
struct TraceRouteNodeCircleColors {
	let unknownFill: Color
	let unknownStroke: Color
	/// A faint edge so a node color close to the background still shows.
	let edge: Color

	static let shareImage = Self(unknownFill: Color.white.opacity(0.04), unknownStroke: TraceRouteShareStyle.secondaryText, edge: Color.white.opacity(0.22))
	static let app = Self(unknownFill: Color.secondary.opacity(0.08), unknownStroke: .secondary, edge: Color.primary.opacity(0.15))
}

/// A node's short name in a circle of its color, or a dashed "?" for an unknown repeater.
struct TraceRouteShareNodeCircle: View {
	let stop: TraceRouteStop
	let size: CGFloat
	var ring: Color?
	var colors: TraceRouteNodeCircleColors = .shareImage

	var body: some View {
		Group {
			if stop.isUnknownRepeater {
				ZStack {
					Circle()
						.fill(colors.unknownFill)
					Circle()
						.strokeBorder(colors.unknownStroke, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
					Text(verbatim: "?")
						.font(.system(size: size * 0.45, weight: .bold))
						.foregroundStyle(colors.unknownStroke)
				}
				.frame(width: size, height: size)
			} else {
				CircleText(text: stop.shortName, color: Color(UIColor(hex: UInt32(truncatingIfNeeded: stop.num))), circleSize: size)
					.overlay(Circle().strokeBorder(colors.edge, lineWidth: 1))
			}
		}
		.overlay {
			if let ring {
				Circle()
					.strokeBorder(ring, lineWidth: 2)
					.padding(-3)
			}
		}
		.padding(ring == nil ? 0 : 3)
	}
}

/// A relay's position in its chain, on the top right of its circle.
struct TraceRouteHopNumberBadge: View {
	let number: Int

	var body: some View {
		Text(verbatim: "\(number)")
			.font(.system(size: 9.5, weight: .bold, design: .rounded))
			.foregroundStyle(Color.white)
			.frame(minWidth: 15, minHeight: 15)
			.background(Circle().fill(Color.black))
			.overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
			.offset(x: 6, y: -4)
	}
}

/// One direction of the route as a vertical chain: node circles joined by lines colored by the SNR
/// of each leg, with the SNR beside each line.
private struct TraceRouteShareChain: View {
	let title: String
	let systemImage: String
	let color: Color
	let stops: [TraceRouteStop]
	/// Smaller circles and gaps for a long route.
	let dense: Bool
	/// Adds each leg's length beside its SNR when there's room.
	let showsDistance: Bool
	/// Rings for the first and last stops, so the origin and destination match the header and map.
	let startRing: Color
	let endRing: Color

	private typealias Style = TraceRouteShareStyle

	private var circleSize: CGFloat { dense ? 25 : 28 }
	private var connectorHeight: CGFloat { dense ? 13 : 15 }

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Label(title, systemImage: systemImage)
				.font(.system(size: 14, weight: .bold))
				.foregroundStyle(color)
				.lineLimit(1)
				.padding(.bottom, 8)
			ForEach(stops) { stop in
				if stop.id > 0 {
					connector(stop)
				}
				row(stop)
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.frame(maxWidth: .infinity, alignment: .topLeading)
		.background(Style.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Style.panelBorder))
	}

	private func ring(for stop: TraceRouteStop) -> Color? {
		if stop.id == 0 { return startRing }
		if stop.id == stops.count - 1 { return endRing }
		return nil
	}

	private func row(_ stop: TraceRouteStop) -> some View {
		let isEndpoint = stop.id == 0 || stop.id == stops.count - 1
		return HStack(spacing: 10) {
			ZStack(alignment: .topTrailing) {
				TraceRouteShareNodeCircle(stop: stop, size: circleSize, ring: isEndpoint ? ring(for: stop) : nil)
				if !isEndpoint {
					TraceRouteHopNumberBadge(number: stop.id)
				}
			}
			.frame(width: circleSize + 6)
			if stop.viaMqtt {
				// The badge goes beside a name that fits on one line, and under one that doesn't, so
				// the name keeps the full width rather than being cut off.
				ViewThatFits(in: .horizontal) {
					HStack(spacing: 8) {
						name(stop, isEndpoint: isEndpoint)
							.fixedSize()
						mqttBadge
					}
					VStack(alignment: .leading, spacing: 3) {
						name(stop, isEndpoint: isEndpoint)
						mqttBadge
					}
				}
			} else {
				name(stop, isEndpoint: isEndpoint)
			}
			Spacer(minLength: 0)
		}
	}

	private func name(_ stop: TraceRouteStop, isEndpoint: Bool) -> some View {
		Text(stop.longName)
			.font(.system(size: dense ? 14.5 : 15.5, weight: isEndpoint ? .semibold : .regular))
			.foregroundStyle(stop.isUnknownRepeater ? Style.secondaryText : Style.primaryText)
			.lineLimit(2)
			.truncationMode(.tail)
			.fixedSize(horizontal: false, vertical: true)
			// A little room above and below a name that wraps, so it doesn't touch the SNR lines.
			.padding(.vertical, 2)
	}

	private var mqttBadge: some View {
		HStack(spacing: 3) {
			Image(systemName: "network")
			Text(verbatim: "MQTT")
		}
		.font(.system(size: 10, weight: .bold))
		.foregroundStyle(Color(red: 0.80, green: 0.66, blue: 1.0))
		.padding(.horizontal, 6)
		.padding(.vertical, 2)
		.background(Color.purple.opacity(0.25), in: Capsule())
		.fixedSize()
	}

	private func connector(_ stop: TraceRouteStop) -> some View {
		let lineColor = stop.quality?.color ?? Color.gray
		return HStack(spacing: 10) {
			TraceRouteLegLine()
				.stroke(lineColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: stop.snr == nil ? [3, 4] : []))
				.frame(width: circleSize + 6, height: connectorHeight)
			Group {
				if let snr = stop.snr {
					Text(TraceRouteShareCard.decibels(snr))
						.foregroundStyle(lineColor)
				} else {
					Text("Unknown signal", comment: "Trace route timeline: a leg whose SNR wasn't reported")
						.foregroundStyle(Style.tertiaryText)
				}
			}
			.font(.system(size: 12, weight: .semibold))
			.monospacedDigit()
			if showsDistance, let distance = stop.legDistance {
				Text(Measurement(value: distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
					.font(.system(size: 12))
					.foregroundStyle(Style.tertiaryText)
			}
			Spacer(minLength: 0)
		}
		.lineLimit(1)
	}
}

/// A vertical line down the middle of its frame, inset so it doesn't touch the circles.
struct TraceRouteLegLine: Shape {
	func path(in rect: CGRect) -> Path {
		Path { path in
			path.move(to: CGPoint(x: rect.midX, y: rect.minY + 3))
			path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 3))
		}
	}
}

// MARK: - Map

/// The map tiles with the route drawn on top: forward legs solid orange and return legs dashed blue,
/// like the in-app map, with an arrow for direction, SNR labels on the forward legs, numbered relays
/// and the two endpoints.
struct TraceRouteShareMap: View {
	let frame: TraceRouteShareModel.MapFrame
	let image: UIImage
	let legs: TraceRouteLegs
	/// Minimum gap between hop badges in points. Nil keeps the layout's default share of the
	/// map width, which suits the share card's map; a much smaller map sets this so the
	/// fixed-size badges don't land on each other.
	var minimumBadgeGap: CGFloat?

	private var visibleRect: MKMapRect { frame.rect }

	private var visibleBadges: [TraceRouteMapLayout.Badge] {
		guard let minimumBadgeGap, frame.size.width > 0 else {
			return frame.layout.visibleBadges(in: visibleRect)
		}
		let fraction = max(TraceRouteMapLayout.badgeMinSeparationFraction, Double(minimumBadgeGap / frame.size.width))
		return frame.layout.visibleBadges(in: visibleRect, separationFraction: fraction)
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			Image(uiImage: image)
				.resizable()
				.interpolation(.high)
				.frame(width: frame.size.width, height: frame.size.height)
			Canvas { context, _ in
				drawSegments(in: &context)
			}
			.frame(width: frame.size.width, height: frame.size.height)
			ForEach(relayCoordinates, id: \.num) { relay in
				Circle()
					.fill(Color(UIColor(hex: UInt32(truncatingIfNeeded: relay.num))))
					.overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
					.frame(width: 11, height: 11)
					.position(frame.point(for: relay.coordinate))
			}
			ForEach(visibleBadges, id: \.id) { badge in
				hopBadge(number: badge.number, isBack: badge.isBack)
					.position(frame.point(for: badge.coordinate))
					.offset(x: 11, y: badge.isBack ? 11 : -11)
			}
			ForEach(forwardLabels, id: \.id) { label in
				snrLabel(label.snr, color: color(snr: label.snr))
					.position(frame.point(for: label.coordinate))
			}
			ForEach(endpoints, id: \.stop.num) { endpoint in
				TraceRouteShareNodeCircle(stop: endpoint.stop, size: 24, ring: endpoint.ring)
					.shadow(color: .black.opacity(0.5), radius: 3, y: 1)
					.position(frame.point(for: endpoint.coordinate))
			}
		}
		.frame(width: frame.size.width, height: frame.size.height)
		.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(TraceRouteShareStyle.panelBorder))
	}

	/// Rough size of an SNR label, for checking it doesn't cover a circle or badge.
	private static let labelSize = CGSize(width: 50, height: 15)

	/// Only the forward SNRs go on the map; the return ones are in its chain below. With no return
	/// label to make room for, each sits at the middle of its leg. A label that would cover an
	/// endpoint, relay dot or hop badge is left off; every SNR is in the hop chains anyway.
	private var forwardLabels: [TraceRouteMapLayout.Label] {
		let obstacles: [(center: CGPoint, radius: CGFloat)] =
			endpoints.map { (frame.point(for: $0.coordinate), 15) }
			+ relayCoordinates.map { (frame.point(for: $0.coordinate), 6) }
			+ visibleBadges.map { badge in
				let point = frame.point(for: badge.coordinate)
				return (CGPoint(x: point.x + 11, y: point.y + (badge.isBack ? 11 : -11)), 8)
			}
		return frame.layout.visibleLabels(in: visibleRect).filter { !$0.isBack }.compactMap { label in
			guard let segment = frame.layout.segments.first(where: { $0.id == label.id }) else { return nil }
			let start = MKMapPoint(segment.from), end = MKMapPoint(segment.to)
			let middle = MKMapPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
			let center = frame.point(for: middle.coordinate)
			let box = CGRect(
				x: center.x - Self.labelSize.width / 2,
				y: center.y - Self.labelSize.height / 2,
				width: Self.labelSize.width,
				height: Self.labelSize.height
			)
			let covers = obstacles.contains { box.insetBy(dx: -$0.radius, dy: -$0.radius).contains($0.center) }
			guard !covers else { return nil }
			return TraceRouteMapLayout.Label(id: label.id, isBack: false, snr: label.snr, coordinate: middle.coordinate, length: label.length)
		}
	}

	private var preset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast }

	private func color(snr: Float?) -> Color {
		guard let snr else { return .gray }
		return getSnrColor(snr: snr, preset: preset)
	}

	private struct Endpoint {
		let stop: TraceRouteStop
		let coordinate: CLLocationCoordinate2D
		let ring: Color
	}

	private var endpoints: [Endpoint] {
		var result: [Endpoint] = []
		// Destination first so the origin draws on top when the two are close.
		if let stop = legs.forward.last, let coordinate = frame.positions[stop.num] {
			result.append(Endpoint(stop: stop, coordinate: coordinate, ring: TraceRouteShareStyle.destinationRing))
		}
		if let stop = legs.forward.first, let coordinate = frame.positions[stop.num] {
			result.append(Endpoint(stop: stop, coordinate: coordinate, ring: TraceRouteShareStyle.originRing))
		}
		return result
	}

	/// Relays with a position, once each, for the small dots under the hop badges.
	private var relayCoordinates: [(num: Int64, coordinate: CLLocationCoordinate2D)] {
		let endpointNums = Set(endpoints.map(\.stop.num))
		var seen = Set<Int64>()
		var result: [(num: Int64, coordinate: CLLocationCoordinate2D)] = []
		for segment in frame.layout.segments {
			for num in [segment.fromNum, segment.toNum] where !endpointNums.contains(num) && !seen.contains(num) {
				if let coordinate = frame.positions[num] {
					seen.insert(num)
					result.append((num, coordinate))
				}
			}
		}
		return result
	}

	private func drawSegments(in context: inout GraphicsContext) {
		let segments = frame.layout.segments
		for segment in segments {
			var from = frame.point(for: segment.from)
			var to = frame.point(for: segment.to)
			// When both directions use a leg, push each to its own side so neither hides the other.
			if frame.layout.sharesLeg(segment) {
				let length = max(hypot(to.x - from.x, to.y - from.y), 0.001)
				let offset = CGPoint(x: -(to.y - from.y) / length * 4, y: (to.x - from.x) / length * 4)
				from = CGPoint(x: from.x + offset.x, y: from.y + offset.y)
				to = CGPoint(x: to.x + offset.x, y: to.y + offset.y)
			}
			let color = segment.isBack ? TraceRouteColors.back : TraceRouteColors.forward
			var path = Path()
			path.move(to: from)
			path.addLine(to: to)
			let width: CGFloat = segment.isBack ? 2.5 : 3.5
			let dash: [CGFloat] = segment.isBack ? [5, 5] : (segment.snr == nil ? [3, 5] : [])
			context.stroke(path, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: width + 2.5, lineCap: .round, dash: dash))
			context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
			drawArrow(in: &context, from: from, to: to, color: color)
		}
	}

	/// A small arrowhead three quarters of the way along a leg, pointing the way the packet went.
	private func drawArrow(in context: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
		let length = hypot(to.x - from.x, to.y - from.y)
		guard length > 36 else { return }
		let direction = CGPoint(x: (to.x - from.x) / length, y: (to.y - from.y) / length)
		let tip = CGPoint(x: from.x + (to.x - from.x) * 0.75 + direction.x * 4, y: from.y + (to.y - from.y) * 0.75 + direction.y * 4)
		let size: CGFloat = 7
		let base = CGPoint(x: tip.x - direction.x * size * 1.4, y: tip.y - direction.y * size * 1.4)
		let normal = CGPoint(x: -direction.y, y: direction.x)
		var arrow = Path()
		arrow.move(to: tip)
		arrow.addLine(to: CGPoint(x: base.x + normal.x * size, y: base.y + normal.y * size))
		arrow.addLine(to: CGPoint(x: base.x - normal.x * size, y: base.y - normal.y * size))
		arrow.closeSubpath()
		context.stroke(arrow, with: .color(.black.opacity(0.6)), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
		context.fill(arrow, with: .color(color))
	}

	private func snrLabel(_ snr: Float, color: Color) -> some View {
		Text(TraceRouteShareCard.decibels(snr))
			.font(.system(size: 9, weight: .bold))
			.monospacedDigit()
			.foregroundStyle(.black)
			.padding(.horizontal, 5)
			.padding(.vertical, 1.5)
			.background(Capsule().fill(color))
			.overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 0.75))
			.fixedSize()
	}

	/// A relay's number, like the in-app map and Vision Pro: filled orange on the way out, a blue
	/// ring on the way back.
	private func hopBadge(number: Int, isBack: Bool) -> some View {
		Text(verbatim: "\(number)")
			.font(.system(size: 9.5, weight: .bold, design: .rounded))
			.monospacedDigit()
			// Black on the orange: white on it is too faint for digits this small.
			.foregroundStyle(isBack ? Color.white : Color.black)
			.frame(minWidth: 16, minHeight: 16)
			.background(Circle().fill(isBack ? Color.black.opacity(0.75) : TraceRouteColors.forward))
			.overlay(Circle().strokeBorder(isBack ? TraceRouteColors.back : Color.white, lineWidth: isBack ? 1.75 : 1.25))
	}
}
