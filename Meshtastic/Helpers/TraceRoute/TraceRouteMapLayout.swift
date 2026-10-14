//
//  TraceRouteMapLayout.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import CoreLocation
import MapKit

/// The lines, hop number badges and SNR labels for a trace route on the map, built from
/// `TraceRouteLegs` and the position snapshots. Plain values so placement can be tested.
struct TraceRouteMapLayout {

	/// One drawn line between two stops that both have a position. A stop without a position is
	/// skipped, so a segment can span it.
	struct Segment {
		let id: String
		let isBack: Bool
		let fromNum: Int64
		let toNum: Int64
		let from: CLLocationCoordinate2D
		let to: CLLocationCoordinate2D
		/// SNR the arriving stop heard the leg at; nil when unknown.
		let snr: Float?
	}

	/// A numbered relay. Relays are numbered from 1 in their direction, the same order as the
	/// hop timeline; the endpoints get no badge.
	struct Badge {
		let id: String
		let isBack: Bool
		let number: Int
		let coordinate: CLLocationCoordinate2D
	}

	/// The SNR of a segment, placed on the line.
	struct Label {
		let id: String
		let isBack: Bool
		let snr: Float
		let coordinate: CLLocationCoordinate2D
		/// Segment length in map points, used to decide whether the label fits.
		let length: Double
	}

	/// A label is shown only when its segment is at least this share of the visible width.
	static let labelMinSegmentFraction = 0.2
	/// Labels closer than this share of the visible width to a shown label are dropped.
	static let labelMinSeparationFraction = 0.08
	/// Badges closer than this share of the visible width to a shown badge are dropped.
	static let badgeMinSeparationFraction = 0.05
	/// Where a label sits along its segment when the reverse segment is also drawn, so the two
	/// labels don't land on the same spot.
	static let sharedSegmentLabelFraction = 0.35

	let segments: [Segment]
	let badges: [Badge]
	let labels: [Label]

	init(legs: TraceRouteLegs, positions: [Int64: CLLocationCoordinate2D]) {
		var segments = Self.segments(for: legs.forward, isBack: false, positions: positions)
		// The return path is drawn only when it went through relays; a direct return would sit
		// on top of the forward line.
		if legs.back.count > 2 {
			segments += Self.segments(for: legs.back, isBack: true, positions: positions)
		}
		self.segments = segments
		badges = Self.badges(for: legs.forward, isBack: false, positions: positions)
			+ (legs.back.count > 2 ? Self.badges(for: legs.back, isBack: true, positions: positions) : [])
		labels = segments.compactMap { segment in
			guard let snr = segment.snr else { return nil }
			let shared = segments.contains { $0.isBack != segment.isBack && $0.fromNum == segment.toNum && $0.toNum == segment.fromNum }
			let fraction = shared ? Self.sharedSegmentLabelFraction : 0.5
			let from = MKMapPoint(segment.from), to = MKMapPoint(segment.to)
			let point = MKMapPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
			return Label(id: segment.id, isBack: segment.isBack, snr: snr, coordinate: point.coordinate, length: Self.distance(from, to))
		}
	}

	/// Badges that don't crowd each other in `rect`. Forward and return badges sit on opposite
	/// sides of a node, so each direction is thinned on its own.
	func visibleBadges(in rect: MKMapRect) -> [Badge] {
		let minDistance = rect.width * Self.badgeMinSeparationFraction
		let forward = Self.thinned(badges.filter { !$0.isBack }, coordinate: \.coordinate, minDistance: minDistance)
		let back = Self.thinned(badges.filter { $0.isBack }, coordinate: \.coordinate, minDistance: minDistance)
		return forward + back
	}

	/// Labels whose segment is long enough on screen to hold them, thinned so they don't overlap.
	func visibleLabels(in rect: MKMapRect) -> [Label] {
		let minLength = rect.width * Self.labelMinSegmentFraction
		let long = labels.filter { $0.length >= minLength }
		return Self.thinned(long, coordinate: \.coordinate, minDistance: rect.width * Self.labelMinSeparationFraction)
	}

	/// The map rect covering a region, for the visibility checks.
	static func mapRect(for region: MKCoordinateRegion) -> MKMapRect {
		let topLeft = MKMapPoint(CLLocationCoordinate2D(
			latitude: min(region.center.latitude + region.span.latitudeDelta / 2, 85),
			longitude: region.center.longitude - region.span.longitudeDelta / 2))
		let bottomRight = MKMapPoint(CLLocationCoordinate2D(
			latitude: max(region.center.latitude - region.span.latitudeDelta / 2, -85),
			longitude: region.center.longitude + region.span.longitudeDelta / 2))
		return MKMapRect(x: topLeft.x, y: topLeft.y, width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))
	}

	private static func segments(for stops: [TraceRouteStop], isBack: Bool, positions: [Int64: CLLocationCoordinate2D]) -> [Segment] {
		var result: [Segment] = []
		var previous: (stop: TraceRouteStop, coordinate: CLLocationCoordinate2D)?
		for stop in stops {
			guard !stop.isUnknownRepeater, let coordinate = positions[stop.num] else { continue }
			if let previous {
				result.append(Segment(
					id: "\(isBack ? "back" : "fwd")-\(stop.id)",
					isBack: isBack,
					fromNum: previous.stop.num,
					toNum: stop.num,
					from: previous.coordinate,
					to: coordinate,
					snr: stop.snr
				))
			}
			previous = (stop, coordinate)
		}
		return result
	}

	private static func badges(for stops: [TraceRouteStop], isBack: Bool, positions: [Int64: CLLocationCoordinate2D]) -> [Badge] {
		guard stops.count > 2 else { return [] }
		return stops.dropFirst().dropLast().compactMap { stop in
			guard !stop.isUnknownRepeater, let coordinate = positions[stop.num] else { return nil }
			return Badge(id: "\(isBack ? "back" : "fwd")-\(stop.id)", isBack: isBack, number: stop.id, coordinate: coordinate)
		}
	}

	/// Straight-line distance in map points (`MKMapPoint.distance(to:)` returns meters).
	private static func distance(_ a: MKMapPoint, _ b: MKMapPoint) -> Double {
		hypot(b.x - a.x, b.y - a.y)
	}

	/// Keeps items in order, dropping any closer than `minDistance` map points to one already kept.
	private static func thinned<T>(_ items: [T], coordinate: KeyPath<T, CLLocationCoordinate2D>, minDistance: Double) -> [T] {
		var kept: [T] = []
		var keptPoints: [MKMapPoint] = []
		for item in items {
			let point = MKMapPoint(item[keyPath: coordinate])
			if keptPoints.allSatisfy({ Self.distance($0, point) >= minDistance }) {
				kept.append(item)
				keptPoints.append(point)
			}
		}
		return kept
	}
}
