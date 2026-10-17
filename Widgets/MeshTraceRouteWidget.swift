//
//  MeshTraceRouteWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  The most recent trace route, requested or observed, in the share image's
//  look: the route on a dark map, the endpoints, hop counts and round trip,
//  and the hop chain. The app renders the map; this process loads a PNG and
//  lays out the rest from plain values.
//

import SwiftUI
import WidgetKit

// MARK: - Style

private typealias RouteStyle = ShareCardStyle
private typealias RouteMapImage = ShareMapImage

// MARK: - Timeline

struct MeshTraceRouteEntry: TimelineEntry {
	let date: Date
	let route: WidgetTraceRoute?
	let isPreview: Bool
}

struct MeshTraceRouteProvider: TimelineProvider {
	func placeholder(in context: Context) -> MeshTraceRouteEntry {
		MeshTraceRouteEntry(date: .now, route: WidgetTraceRouteStore.load() ?? .preview, isPreview: true)
	}

	func getSnapshot(in context: Context, completion: @escaping (MeshTraceRouteEntry) -> Void) {
		let route = WidgetTraceRouteStore.load() ?? (context.isPreview ? .preview : nil)
		completion(MeshTraceRouteEntry(date: .now, route: route, isPreview: context.isPreview))
	}

	// A trace route is a moment, not a live value, so there is no stale dim:
	// the age next to it says how old it is. The app reloads on a new route.
	func getTimeline(in context: Context, completion: @escaping (Timeline<MeshTraceRouteEntry>) -> Void) {
		let entry = MeshTraceRouteEntry(date: .now, route: WidgetTraceRouteStore.load(), isPreview: false)
		completion(Timeline(entries: [entry], policy: .never))
	}
}

// MARK: - Widget

struct MeshTraceRouteWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "MeshTraceRoute", provider: MeshTraceRouteProvider()) { entry in
			MeshTraceRouteWidgetView(entry: entry)
				.containerBackground(for: .widget) { RouteStyle.background }
				.environment(\.colorScheme, .dark)
				.widgetURL(entry.route.flatMap { URL(string: "meshtastic:///map?tracerouteId=\($0.routeId)") }
					?? URL(string: "meshtastic:///nodes"))
		}
		.configurationDisplayName("Trace Route")
		.description("Your most recent trace route, requested or seen on the mesh.")
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
		.contentMarginsDisabled()
	}
}

// MARK: - Views

struct MeshTraceRouteWidgetView: View {
	@Environment(\.widgetFamily) private var family
	let entry: MeshTraceRouteEntry

	var body: some View {
		if let route = entry.route {
			switch family {
			case .systemLarge:
				RouteLargeView(route: route, map: mapImage(wide: true, route: route))
			case .systemMedium:
				RouteMediumView(route: route, map: mapImage(wide: false, route: route))
			default:
				RouteSmallView(route: route, map: mapImage(wide: false, route: route))
			}
		} else {
			VStack(spacing: 6) {
				Image(systemName: "point.3.connected.trianglepath.dotted")
					.font(.title2)
					.foregroundStyle(RouteStyle.brand)
					.widgetAccentable()
				Text("Run a trace route to see it here")
					.font(.caption2)
					.multilineTextAlignment(.center)
					.foregroundStyle(RouteStyle.secondaryText)
			}
			.padding(12)
		}
	}

	/// The rendered map; the gallery falls back to the bundled sample.
	private func mapImage(wide: Bool, route: WidgetTraceRoute) -> UIImage? {
		guard route.hasMap else { return nil }
		if let data = WidgetTraceRouteStore.loadImageData(routeId: route.routeId, wide: wide),
		   let image = UIImage(data: data) {
			return image
		}
		return entry.isPreview ? UIImage(named: wide ? "widget-traceroute-preview-wide" : "widget-traceroute-preview") : nil
	}
}

// MARK: Families

private struct RouteSmallView: View {
	let route: WidgetTraceRoute
	let map: UIImage?

	// Header, map and title stacked, so no label sits over the map's circles.
	var body: some View {
		VStack(alignment: .leading, spacing: 5) {
			HStack(spacing: 4) {
				RouteHeader(route: route, compact: true)
				Spacer(minLength: 2)
				AgeLine(route: route)
			}
			if let map {
				RouteMapImage(image: map)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				Spacer(minLength: 0)
				// Endpoints and a relay or two, so the chain fits the small width.
				HopChain(stops: route.forward, color: RouteStyle.forward, size: 22, maxStops: 4)
				Spacer(minLength: 0)
			}
			HStack(spacing: 4) {
				Text(shortTitle)
					.font(.caption2.weight(.semibold))
					.lineLimit(1)
					.minimumScaleFactor(0.7)
				Spacer(minLength: 2)
				HopsLabel(count: route.hopsTowards, color: RouteStyle.forward)
			}
		}
		.padding(12)
	}

	private var shortTitle: String {
		guard let origin = route.origin, let destination = route.destination else { return "" }
		return "\(origin.shortName) → \(destination.shortName)"
	}
}

private struct RouteMediumView: View {
	let route: WidgetTraceRoute
	let map: UIImage?

	var body: some View {
		HStack(spacing: 12) {
			if let map {
				RouteMapImage(image: map)
			}
			VStack(alignment: .leading, spacing: 5) {
				RouteHeader(route: route, compact: false)
				RouteTitle(route: route, font: .subheadline.weight(.semibold), lineLimit: 2)
				Spacer(minLength: 0)
				StatsLine(route: route)
				if map == nil {
					HopChain(stops: route.forward, color: RouteStyle.forward, size: 20)
				}
				AgeLine(route: route)
			}
			Spacer(minLength: 0)
		}
		.padding(12)
	}
}

private struct RouteLargeView: View {
	let route: WidgetTraceRoute
	let map: UIImage?

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			RouteHeader(route: route, compact: false)
			RouteTitle(route: route, font: .headline, lineLimit: 2)
			if let map {
				RouteMapImage(image: map)
					.frame(maxWidth: .infinity)
			}
			StatTiles(route: route)
			// The map shows the route; the chains only earn their space when
			// there is no map to show it.
			if map == nil {
				VStack(alignment: .leading, spacing: 6) {
					HopChain(stops: route.forward, color: RouteStyle.forward, size: 20)
					if !route.back.isEmpty {
						// The way back starts at the destination and ends at the origin,
						// so its rings swap ends, as in the share image.
						HopChain(stops: route.back, color: RouteStyle.back, size: 20, startRing: .white, endRing: RouteStyle.brand)
					}
				}
			}
			Spacer(minLength: 0)
			// On its own line: the self-updating age is wide, and beside the
			// header it squeezed the title.
			AgeLine(route: route)
		}
		.padding(14)
	}
}

// MARK: Pieces

/// The Meshtastic mark, "Trace Route" in brand green and, for a route seen on
/// the mesh, an "Observed" tag.
private struct RouteHeader: View {
	let route: WidgetTraceRoute
	let compact: Bool

	var body: some View {
		HStack(spacing: 5) {
			MeshLogo(height: 10)
			if !compact {
				Text("Trace Route")
					.font(.caption.weight(.semibold))
					.foregroundStyle(RouteStyle.brand)
					.lineLimit(1)
					.fixedSize()
			}
			if route.observed {
				Text("Observed")
					.font(.system(size: 10, weight: .semibold))
					.foregroundStyle(Color.orange)
					.padding(.horizontal, 5)
					.padding(.vertical, 1)
					.background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
					.fixedSize()
			}
		}
	}
}

/// "Origin → Destination" with the arrow in the round trip purple, like the
/// share image's title.
private struct RouteTitle: View {
	let route: WidgetTraceRoute
	let font: Font
	let lineLimit: Int

	var body: some View {
		if let origin = route.origin, let destination = route.destination {
			Text(title(origin: origin.longName, destination: destination.longName))
				.font(font)
				.lineLimit(lineLimit)
				.minimumScaleFactor(0.7)
		}
	}

	private func title(origin: String, destination: String) -> AttributedString {
		var arrow = AttributedString(" → ")
		arrow.foregroundColor = RouteStyle.roundTrip
		return AttributedString(origin) + arrow + AttributedString(destination)
	}
}

private struct HopsLabel: View {
	let count: Int
	let color: Color

	// The app's own "%d Hops" plural key, so the count reads the same here and
	// in the trace route log, in every language.
	var body: some View {
		Group {
			if count == 0 {
				Text("Direct")
			} else {
				Text("\(Int32(count)) Hops")
			}
		}
		.font(.caption2.weight(.semibold))
		.foregroundStyle(color)
		.lineLimit(1)
		.fixedSize()
	}
}

/// Hops out, hops back and the round trip on one line.
private struct StatsLine: View {
	let route: WidgetTraceRoute

	var body: some View {
		HStack(spacing: 8) {
			HopsLabel(count: route.hopsTowards, color: RouteStyle.forward)
			if let back = route.hopsBack {
				HopsLabel(count: back, color: RouteStyle.back)
			}
			if let roundTrip = route.roundTrip {
				Text(roundTripText(roundTrip))
					.font(.caption2.weight(.semibold))
					.foregroundStyle(RouteStyle.roundTrip)
					.lineLimit(1)
			}
		}
	}
}

/// The large widget's stat tiles: hops each way, round trip, distance.
private struct StatTiles: View {
	let route: WidgetTraceRoute

	var body: some View {
		HStack(spacing: 6) {
			ShareStatTile(title: "Hops Out", value: hopsText(route.hopsTowards), color: RouteStyle.forward)
			ShareStatTile(title: "Hops Back", value: route.hopsBack.map(hopsText) ?? "—", color: RouteStyle.back)
			ShareStatTile(title: "Round Trip", value: route.roundTrip.map(roundTripText) ?? "—", color: RouteStyle.roundTrip)
			ShareStatTile(title: "Distance", value: route.distance.map(shareDistanceText) ?? "—")
		}
	}

	private func hopsText(_ count: Int) -> String {
		count == 0 ? String(localized: "Direct") : "\(count)"
	}
}

/// The stops as node circles joined by a line in the direction's color. Long
/// routes keep the endpoints and the first relays, with a count for the rest.
private struct HopChain: View {
	let stops: [WidgetTraceRoute.Stop]
	let color: Color
	let size: CGFloat
	var maxStops = 7
	/// Ring on the first stop; the origin's green on the way out.
	var startRing: Color = RouteStyle.brand
	/// Ring on the last stop; the destination's white on the way out.
	var endRing: Color = .white

	var body: some View {
		HStack(spacing: 0) {
			ForEach(Array(visible.enumerated()), id: \.offset) { index, item in
				if index > 0 {
					Rectangle()
						.fill(color)
						.frame(height: 2)
						.frame(minWidth: 4, maxWidth: 14)
				}
				switch item {
				case .stop(let stop, let ring):
					StopCircle(stop: stop, size: size, ring: ring)
				case .more(let count):
					Text("+\(count)")
						.font(.system(size: size * 0.4, weight: .semibold))
						.foregroundStyle(RouteStyle.secondaryText)
						.frame(width: size, height: size)
						.background(Circle().fill(RouteStyle.panel))
				}
			}
		}
	}

	private enum Item {
		case stop(WidgetTraceRoute.Stop, ring: Color?)
		case more(Int)
	}

	private var visible: [Item] {
		func ring(_ index: Int) -> Color? {
			if index == 0 { return startRing }
			if index == stops.count - 1 { return endRing }
			return nil
		}
		guard stops.count > maxStops else {
			return stops.enumerated().map { .stop($1, ring: ring($0)) }
		}
		// The first stops, a count for the ones left out, then the last stop.
		let head = stops.prefix(maxStops - 2).enumerated().map { Item.stop($1, ring: ring($0)) }
		let hidden = stops.count - (maxStops - 2) - 1
		return head + [.more(hidden), .stop(stops[stops.count - 1], ring: endRing)]
	}
}

/// A node's short name in a circle of its node color, ringed for an endpoint
/// like the share image's circles.
private struct StopCircle: View {
	let stop: WidgetTraceRoute.Stop
	let size: CGFloat
	let ring: Color?

	var body: some View {
		Group {
			if stop.isUnknownRepeater {
				// A repeater that didn't add its number: a dashed "?" like the
				// share image, not a node with a color.
				Text(verbatim: "?")
					.font(.system(size: size * 0.45, weight: .bold))
					.foregroundStyle(RouteStyle.secondaryText)
					.frame(width: size, height: size)
					.background(Circle().fill(RouteStyle.panel))
					.overlay(Circle().strokeBorder(RouteStyle.secondaryText, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
			} else {
				Text(stop.shortName)
					.font(.system(size: size * 0.32, weight: .bold))
					.minimumScaleFactor(0.4)
					.lineLimit(1)
					.padding(2)
					.foregroundStyle(isLight ? Color.black : Color.white)
					.frame(width: size, height: size)
					.background(Circle().fill(Color(red: red, green: green, blue: blue)))
			}
		}
		.overlay {
			if let ring {
				Circle().strokeBorder(ring, lineWidth: 1.5)
			}
		}
		.overlay(alignment: .bottomTrailing) {
			if stop.viaMqtt {
				// Heard over MQTT rather than radio.
				Image(systemName: "network")
					.font(.system(size: size * 0.32, weight: .bold))
					.foregroundStyle(.white)
					.padding(1.5)
					.background(Circle().fill(RouteStyle.backgroundBottom))
					.offset(x: 3, y: 3)
			}
		}
	}

	// The node number's low 24 bits as RRGGBB, as everywhere in the app.
	private var seed: UInt32 { UInt32(truncatingIfNeeded: stop.num) }
	private var red: Double { Double((seed >> 16) & 0xFF) / 255 }
	private var green: Double { Double((seed >> 8) & 0xFF) / 255 }
	private var blue: Double { Double(seed & 0xFF) / 255 }

	// WCAG relative luminance with the app's 0.179 cutoff.
	private var isLight: Bool {
		func linearize(_ channel: Double) -> Double {
			channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
		}
		return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue) > 0.179
	}
}

private struct AgeLine: View {
	let route: WidgetTraceRoute

	var body: some View {
		if let time = route.time {
			Text("\(time, style: .relative) ago")
				.font(.caption2)
				.foregroundStyle(RouteStyle.tertiaryText)
				.lineLimit(1)
		}
	}
}

// MARK: Helpers

/// "7.3 sec", formatted for the locale the same way the app's trace route log
/// shows a round trip.
private func roundTripText(_ seconds: TimeInterval) -> String {
	Duration.milliseconds(Int64((seconds * 1000).rounded()))
		.formatted(.units(allowed: [.seconds], width: .abbreviated, fractionalPart: .show(length: 1)))
}

// MARK: Preview data

extension WidgetTraceRoute {
	/// Gallery and placeholder content — never written to the store.
	static var preview: WidgetTraceRoute {
		WidgetTraceRoute(
			generatedAt: Date(timeIntervalSinceNow: -60),
			routeId: 0,
			time: Date(timeIntervalSinceNow: -300),
			observed: false,
			forward: [
				Stop(num: 0x67EA94, shortName: "5fac", longName: "Meshtastic 5fac", isUnknownRepeater: false, viaMqtt: false),
				Stop(num: 0x43B2A1, shortName: "BCS1", longName: "Basecamp Solar", isUnknownRepeater: false, viaMqtt: false),
				Stop(num: 0x1A2B3C, shortName: "WX2", longName: "Weather Station 2", isUnknownRepeater: false, viaMqtt: false)
			],
			back: [
				Stop(num: 0x1A2B3C, shortName: "WX2", longName: "Weather Station 2", isUnknownRepeater: false, viaMqtt: false),
				Stop(num: 0x43B2A1, shortName: "BCS1", longName: "Basecamp Solar", isUnknownRepeater: false, viaMqtt: false),
				Stop(num: 0x67EA94, shortName: "5fac", longName: "Meshtastic 5fac", isUnknownRepeater: false, viaMqtt: false)
			],
			roundTrip: 4.2,
			distance: 12_400,
			bestSNR: 9.5,
			worstSNR: -6.25,
			hasMap: true
		)
	}
}
