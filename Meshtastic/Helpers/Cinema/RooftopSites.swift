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

	/// How far round each first-pass rooftop the second pass looks, in meters: far enough to take
	/// in the towers standing with it.
	static let refineRadius = 700.0
	/// Tiles the second pass reads for each box round the first-pass rooftops.
	static let refineTiles = 30

	/// The tallest rooftops in `box`, read in two passes. A box as big as a city only fits the tile
	/// cap at a coarse zoom, and a coarse tile keeps whole buildings but drops building parts, so a
	/// tower mapped in parts, like Columbia Center, isn't there at all. Towers stand together, so
	/// the second pass reads the boxes round the first pass's rooftops again at the finest zoom the
	/// basemap has, where the parts are, and chooses from both. `decode` reads the buildings in a
	/// box, using at most the given number of tiles; nil when cancelled.
	static func search(in box: GeoBounds, maxTiles: Int, decode: (GeoBounds, Int) -> [SpatialBuildingFootprint]?) -> [Rooftop]? {
		guard var footprints = decode(box, maxTiles) else { return nil }
		for refine in refineBoxes(around: tallest(footprints), within: box) {
			guard let fine = decode(refine, refineTiles) else { return nil }
			footprints += fine
		}
		return tallest(footprints)
	}

	/// A box `radius` round each rooftop, kept inside `box`, with boxes that overlap joined into one,
	/// so no tile is read twice for neighboring towers.
	static func refineBoxes(around rooftops: [Rooftop], within box: GeoBounds, radius: Double = refineRadius) -> [GeoBounds] {
		var boxes: [GeoBounds] = rooftops.map { rooftop in
			let latitude = radius / SpatialFrame.metersPerDegreeLatitude
			let longitude = latitude / cos(rooftop.coordinate.latitude * .pi / 180)
			return GeoBounds(
				minLon: max(rooftop.coordinate.longitude - longitude, box.minLon),
				minLat: max(rooftop.coordinate.latitude - latitude, box.minLat),
				maxLon: min(rooftop.coordinate.longitude + longitude, box.maxLon),
				maxLat: min(rooftop.coordinate.latitude + latitude, box.maxLat)
			)
		}
		var joined = true
		while joined {
			joined = false
			outer: for i in boxes.indices {
				for j in boxes.indices where j > i && boxes[i].intersects(boxes[j]) {
					let a = boxes[i], b = boxes[j]
					boxes[i] = GeoBounds(minLon: min(a.minLon, b.minLon), minLat: min(a.minLat, b.minLat), maxLon: max(a.maxLon, b.maxLon), maxLat: max(a.maxLat, b.maxLat))
					boxes.remove(at: j)
					joined = true
					break outer
				}
			}
		}
		return boxes
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
