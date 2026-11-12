//
//  RooftopSites.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import CoreLocation
import Foundation
import simd

/// The rooftops the cinema's city rooftop can stand on: the tallest buildings in the downloaded
/// basemaps. Outside the visionOS-only code so it can be tested.
enum RooftopSites {
	struct Rooftop: Equatable {
		/// A point on the roof, inside the outline even when it's concave.
		let coordinate: CLLocationCoordinate2D
		/// How tall the building is to its roof, in meters.
		let height: Double
		/// The roof's outline, for hanging a sky deck off one of its faces.
		var outline: [CLLocationCoordinate2D] = []

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
				kept.append(Rooftop(coordinate: point, height: candidate.height, outline: candidate.footprint.outline))
			}
		}
		return kept
	}

	/// How far out from its tower's face the sky deck's seat is, in meters, as its image has it.
	static let deckOverhang = 2.2
	/// A face shorter than this, in meters, is a corner or a notch, too narrow to hang a deck off.
	static let shortestFace = 8.0
	/// Other towers this far from a face count against the view out from it, in meters.
	static let viewReach = 1_500.0

	/// Where a sky deck hangs off `rooftop`'s tower, and the true bearing it looks out along: out
	/// from the middle of the face whose view the other tall towers in `others` block least, nearer
	/// and taller ones the most, `deckOverhang` out from it. Buildings under half the tower's height
	/// are below the deck and don't count, which also leaves out the tower's own podium. Nil when
	/// the roof has no outline or no face wide enough.
	static func deck(on rooftop: Rooftop, among others: [Rooftop]) -> (coordinate: CLLocationCoordinate2D, facing: Double)? {
		guard rooftop.outline.count >= 3 else { return nil }
		let origin = rooftop.coordinate
		let metersPerDegreeLatitude = SpatialFrame.metersPerDegreeLatitude
		let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
		func local(_ c: CLLocationCoordinate2D) -> SIMD2<Double> {
			SIMD2((c.longitude - origin.longitude) * metersPerDegreeLongitude, (c.latitude - origin.latitude) * metersPerDegreeLatitude)
		}
		var points = rooftop.outline.map(local)
		if let first = points.first, let last = points.last, simd_distance(first, last) < 0.01 { points.removeLast() }
		guard points.count >= 3 else { return nil }
		// Counterclockwise, so each face's outward side is to the right of its direction.
		var area = 0.0
		for i in points.indices {
			let p = points[i], q = points[(i + 1) % points.count]
			area += p.x * q.y - q.x * p.y
		}
		if area < 0 { points.reverse() }
		let towers = others.filter { simd_length(local($0.coordinate)) > 30 && $0.height >= rooftop.height / 2 }.map { (place: local($0.coordinate), height: $0.height) }
		struct Face {
			let score: Double
			let length: Double
			let middle: SIMD2<Double>
			let outward: SIMD2<Double>
		}
		var best: Face?
		for i in points.indices {
			let p = points[i], q = points[(i + 1) % points.count]
			let length = simd_distance(p, q)
			guard length >= shortestFace else { continue }
			let along = (q - p) / length
			let outward = SIMD2(along.y, -along.x)
			let middle = (p + q) / 2
			var score = 0.0
			for tower in towers {
				let toward = tower.place - middle
				let distance = simd_length(toward)
				guard distance <= viewReach else { continue }
				score += max(0, simd_dot(outward, toward / distance)) * tower.height / max(distance, 50)
			}
			let face = Face(score: score, length: length, middle: middle, outward: outward)
			if let current = best {
				if score < current.score - 1e-9 || (abs(score - current.score) < 1e-9 && length > current.length) { best = face }
			} else {
				best = face
			}
		}
		guard let best else { return nil }
		let seat = best.middle + best.outward * deckOverhang
		let coordinate = CLLocationCoordinate2D(latitude: origin.latitude + seat.y / metersPerDegreeLatitude, longitude: origin.longitude + seat.x / metersPerDegreeLongitude)
		let facing = (atan2(best.outward.x, best.outward.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
		return (coordinate, facing)
	}

	/// The point on the tower's face behind a sky deck's seat, `deckOverhang` back along its bearing.
	static func face(behind deck: CLLocationCoordinate2D, facing: Double) -> CLLocationCoordinate2D {
		offset(deck, back: deckOverhang, facing: facing)
	}

	/// The point `deckOverhang` and a little more back from a sky deck's seat along its bearing:
	/// inside the tower it hangs off, so the city round it can leave that tower out.
	static func tower(behind deck: CLLocationCoordinate2D, facing: Double) -> CLLocationCoordinate2D {
		offset(deck, back: deckOverhang + 1.5, facing: facing)
	}

	private static func offset(_ deck: CLLocationCoordinate2D, back: Double, facing: Double) -> CLLocationCoordinate2D {
		let bearing = facing * .pi / 180
		let metersPerDegreeLatitude = SpatialFrame.metersPerDegreeLatitude
		let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(deck.latitude * .pi / 180)
		return CLLocationCoordinate2D(latitude: deck.latitude - back * cos(bearing) / metersPerDegreeLatitude, longitude: deck.longitude - back * sin(bearing) / metersPerDegreeLongitude)
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
		searchWithNeighbors(in: box, maxTiles: maxTiles, decode: decode)?.tallest
	}

	/// Up to this many tall buildings are kept to score a sky deck's faces against.
	static let neighborCount = 150
	/// Buildings closer together than this, in meters, count as one when scoring a face.
	static let neighborSpacing = 30.0

	/// `search`'s rooftops, and the tall buildings round them before the picker's limit and
	/// spacing apply: a tower 70 m from another is left out of the picker, but still blocks the view.
	static func searchWithNeighbors(in box: GeoBounds, maxTiles: Int, decode: (GeoBounds, Int) -> [SpatialBuildingFootprint]?) -> (tallest: [Rooftop], neighbors: [Rooftop])? {
		guard var footprints = decode(box, maxTiles) else { return nil }
		for refine in refineBoxes(around: tallest(footprints), within: box) {
			guard let fine = decode(refine, refineTiles) else { return nil }
			footprints += fine
		}
		return (tallest(footprints), tallest(footprints, count: neighborCount, spacing: neighborSpacing))
	}

	/// A box `radius` round each rooftop, kept inside `box`, with boxes that overlap joined into one,
	/// so no tile is read twice for neighboring towers. A rooftop outside `box` gets none: the first
	/// pass reads whole tiles, which reach past the box, and its box cut to `box` would be inside out.
	static func refineBoxes(around rooftops: [Rooftop], within box: GeoBounds, radius: Double = refineRadius) -> [GeoBounds] {
		let inside = rooftops.filter {
			(box.minLat...box.maxLat).contains($0.coordinate.latitude) && (box.minLon...box.maxLon).contains($0.coordinate.longitude)
		}
		var boxes: [GeoBounds] = inside.map { rooftop in
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
