//
//  RooftopSites.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import CoreLocation
import Foundation

/// The rooftops the cinema's city rooftop can stand on: the tallest buildings in the downloaded
/// basemaps. Outside the visionOS-only code so it can be tested.
enum RooftopSites {
	struct Rooftop: Equatable {
		/// A point on the roof, inside the outline even when it's concave.
		let coordinate: CLLocationCoordinate2D
		/// How tall the building is to its roof, in meters.
		let height: Double

		static func == (lhs: Rooftop, rhs: Rooftop) -> Bool {
			lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude && lhs.height == rhs.height
		}
	}

	/// Enough rooftops to choose from.
	static let count = 12
	/// A rooftop this close to a taller one is the same tower: its podium or another of its parts.
	static let spacing = 150.0
	/// A roof smaller than this, in square meters, is a spire or a mast, not somewhere to stand.
	static let minimumRoof = 200.0

	/// The tallest buildings whose height is in the data, tallest first, each at least `spacing`
	/// from every taller one kept. Buildings with no height in the data are left out: they're drawn
	/// at a guessed two floors, never the tallest.
	static func tallest(_ footprints: [SpatialBuildingFootprint], count: Int = count, spacing: Double = spacing, minimumRoof: Double = minimumRoof) -> [Rooftop] {
		let candidates = footprints
			.compactMap { footprint -> (footprint: SpatialBuildingFootprint, height: Double)? in
				guard let height = footprint.height, height > 0, roofArea(footprint.outline) >= minimumRoof else { return nil }
				return (footprint, height)
			}
			.sorted { $0.height > $1.height }
		var kept: [Rooftop] = []
		for candidate in candidates {
			guard kept.count < count else { break }
			guard let point = SpatialBuildings.interiorPoint(candidate.footprint.outline) else { continue }
			let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
			let clear = kept.allSatisfy { location.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) >= spacing }
			if clear {
				kept.append(Rooftop(coordinate: point, height: candidate.height))
			}
		}
		return kept
	}

	/// The outline's area in square meters, close enough over a building's few tens of meters.
	static func roofArea(_ outline: [CLLocationCoordinate2D]) -> Double {
		guard let origin = outline.first, outline.count >= 3 else { return 0 }
		let metersPerDegreeLatitude = SpatialFrame.metersPerDegreeLatitude
		let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
		let points = outline.map { SIMD2(($0.longitude - origin.longitude) * metersPerDegreeLongitude, ($0.latitude - origin.latitude) * metersPerDegreeLatitude) }
		var sum = 0.0
		for i in points.indices {
			let p = points[i], q = points[(i + 1) % points.count]
			sum += p.x * q.y - q.x * p.y
		}
		return abs(sum) / 2
	}
}
