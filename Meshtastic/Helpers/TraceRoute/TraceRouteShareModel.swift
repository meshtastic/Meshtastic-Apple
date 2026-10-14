//
//  TraceRouteShareModel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import CoreLocation
import Foundation
import MapKit

/// What the trace route share image shows: the endpoints, the stats, both hop chains and, when
/// enough stops have a position snapshot, how to frame the map. Plain values so it can be tested.
struct TraceRouteShareModel {

	/// The map part of the image: the area to show and the route drawn on it.
	struct MapFrame {
		/// The area the map shows, already matching the aspect ratio of `size`.
		let rect: MKMapRect
		/// Size of the map in points.
		let size: CGSize
		let layout: TraceRouteMapLayout
		let positions: [Int64: CLLocationCoordinate2D]

		/// Where a coordinate lands on the map, in points from its top left corner.
		func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
			let mapPoint = MKMapPoint(coordinate)
			return CGPoint(
				x: (mapPoint.x - rect.minX) / rect.width * size.width,
				y: (mapPoint.y - rect.minY) / rect.height * size.height
			)
		}
	}

	/// Share of the route's width and height added as margin on each side of the map.
	static let mapPaddingFraction = 0.22
	/// The map never shows less than this many meters across, so nodes close together still
	/// show some streets around them.
	static let mapMinimumSpanMeters: CLLocationDistance = 800
	/// Height over width of the map follows the shape of the route within these, so the map stays
	/// close to square. The image can still make it taller to line up with the hop chains beside it.
	static let mapAspectRange: ClosedRange<Double> = 0.75...1.0

	let legs: TraceRouteLegs
	let date: Date?
	let observed: Bool
	let roundTrip: TimeInterval?
	let map: MapFrame?

	var origin: TraceRouteStop? { legs.forward.first }
	var destination: TraceRouteStop? { legs.forward.last }
	/// Relays on the way out.
	var hopsTowards: Int { max(legs.forward.count - 2, 0) }
	/// Relays on the way back; nil when the response didn't carry a return path.
	var hopsBack: Int? { legs.back.isEmpty ? nil : max(legs.back.count - 2, 0) }

	/// Every leg with a reported SNR, both directions.
	private var knownLegs: [TraceRouteStop] { (legs.forward + legs.back).filter { $0.snr != nil } }
	/// The leg with the highest SNR.
	var bestLeg: TraceRouteStop? { knownLegs.max { ($0.snr ?? 0) < ($1.snr ?? 0) } }
	/// The leg with the lowest SNR.
	var worstLeg: TraceRouteStop? { knownLegs.min { ($0.snr ?? 0) < ($1.snr ?? 0) } }

	/// Length of the forward path through the stops that have a position, in meters. Nil unless
	/// both the origin and the destination have one, so it never shows part of a route as the whole.
	var routeDistance: CLLocationDistance? {
		guard let map, let origin, let destination,
			  map.positions[origin.num] != nil, map.positions[destination.num] != nil else { return nil }
		let forward = map.layout.segments.filter { !$0.isBack }
		guard !forward.isEmpty else { return nil }
		return forward.reduce(0) { total, segment in
			total + CLLocation(latitude: segment.from.latitude, longitude: segment.from.longitude)
				.distance(from: CLLocation(latitude: segment.to.latitude, longitude: segment.to.longitude))
		}
	}

	/// - Parameters:
	///   - mapWidth: width of the map in points; its height follows the shape of the route.
	///   - mapHeight: a set height for the map instead of one from the route's shape; the area
	///     shown widens to match, so the route is never cropped.
	init(
		legs: TraceRouteLegs,
		positions: [Int64: CLLocationCoordinate2D],
		date: Date?,
		observed: Bool,
		roundTrip: TimeInterval?,
		mapWidth: CGFloat,
		mapHeight: CGFloat? = nil
	) {
		self.legs = legs
		self.date = date
		self.observed = observed
		self.roundTrip = roundTrip
		let layout = TraceRouteMapLayout(legs: legs, positions: positions)
		// A map needs at least one drawn line, which takes two stops with a position.
		if !layout.segments.isEmpty {
			let points = layout.segments.flatMap { [MKMapPoint($0.from), MKMapPoint($0.to)] }
			let (rect, size) = Self.frame(points: points, width: mapWidth, height: mapHeight)
			map = MapFrame(rect: rect, size: size, layout: layout, positions: positions)
		} else {
			map = nil
		}
	}

	/// The same route with the map `height` points tall, so it lines up with the hop chains beside
	/// it. It's never made flatter than `mapAspectRange` allows.
	func fittingMap(height: CGFloat) -> TraceRouteShareModel {
		guard let map else { return self }
		let height = max(height, (map.size.width * Self.mapAspectRange.lowerBound).rounded(.up))
		guard height != map.size.height else { return self }
		return TraceRouteShareModel(
			legs: legs,
			positions: map.positions,
			date: date,
			observed: observed,
			roundTrip: roundTrip,
			mapWidth: map.size.width,
			mapHeight: height
		)
	}

	/// The map area and size for a set of points: their bounds with padding and a minimum span,
	/// widened in one direction to match the map's aspect ratio. A set `height` replaces the
	/// aspect ratio from the route's shape.
	static func frame(points: [MKMapPoint], width: CGFloat, height: CGFloat? = nil) -> (rect: MKMapRect, size: CGSize) {
		let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
		let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
		let center = MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
		let minimumSpan = mapMinimumSpanMeters * MKMapPointsPerMeterAtLatitude(center.coordinate.latitude)
		var spanX = max((maxX - minX) * (1 + 2 * mapPaddingFraction), minimumSpan)
		var spanY = max((maxY - minY) * (1 + 2 * mapPaddingFraction), minimumSpan)
		let aspect = height.map { Double($0 / width) }
			?? min(max(spanY / spanX, mapAspectRange.lowerBound), mapAspectRange.upperBound)
		// Grow whichever side is short so the area matches the aspect ratio without cropping.
		if spanY / spanX < aspect {
			spanY = spanX * aspect
		} else {
			spanX = spanY / aspect
		}
		let rect = MKMapRect(x: center.x - spanX / 2, y: center.y - spanY / 2, width: spanX, height: spanY)
		let size = CGSize(width: width, height: (width * aspect).rounded())
		return (rect, size)
	}
}

extension TraceRouteShareModel {

	/// Builds the model for a stored trace route.
	init(route: TraceRouteEntity, legs: TraceRouteLegs, mapWidth: CGFloat) {
		self.init(
			legs: legs,
			positions: route.nodePositionsByNum.compactMapValues { $0.coordinate },
			date: route.time,
			observed: route.observed,
			roundTrip: route.roundTrip,
			mapWidth: mapWidth
		)
	}

	/// The route as plain text, for apps that take text rather than an image.
	var plainText: String {
		var lines: [String] = []
		if let origin, let destination {
			lines.append(String(localized: "Trace Route") + ": \(origin.longName) → \(destination.longName)")
		}
		lines.append(String(localized: "Route: \(legs.forward.map(\.longName).joined(separator: " → "))"))
		if !legs.back.isEmpty {
			lines.append(String(localized: "Route Back: \(legs.back.map(\.longName).joined(separator: " → "))"))
		}
		if let date {
			lines.append(date.formatted(date: .abbreviated, time: .shortened))
		}
		lines.append("meshtastic.org")
		return lines.joined(separator: "\n")
	}
}
