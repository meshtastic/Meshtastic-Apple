//
//  SpatialRouteLayout.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import CoreLocation
import Foundation
import simd

/// What the spatial map draws for a trace route: the legs, which of them are dashed or shared by
/// both directions, the endpoints, and the numbered relays. Built from the same `TraceRouteMapLayout`
/// as the 2D map, so the two agree on which legs and badges there are.
struct SpatialRouteLayout: Equatable, Sendable {

	/// One drawn leg between two stops that both have a position.
	struct Segment: Equatable, Sendable, Identifiable {
		let id: String
		let isBack: Bool
		let fromNum: Int64
		let toNum: Int64
		/// SNR the arriving stop heard the leg at; nil when unknown.
		let snr: Float?
		/// The other direction uses the same two nodes, so the two lines sit side by side.
		let sharesLeg: Bool

		/// Return legs are dashed, and so is a forward leg whose SNR wasn't reported.
		var isDashed: Bool { isBack || snr == nil }

		/// Where the SNR pill sits along the leg. On a shared leg each direction's pill moves toward
		/// its own start so the two don't land on the same spot.
		var pillFraction: Float { sharesLeg ? Float(TraceRouteMapLayout.sharedSegmentLabelFraction) : 0.5 }
	}

	/// A numbered relay, numbered from 1 in its direction like the hop timeline.
	struct Badge: Equatable, Sendable, Identifiable {
		let id: String
		let isBack: Bool
		let number: Int
		let num: Int64
	}

	let originNum: Int64?
	let targetNum: Int64?
	let segments: [Segment]
	let badges: [Badge]

	static let empty = SpatialRouteLayout(originNum: nil, targetNum: nil, segments: [], badges: [])

	init(originNum: Int64?, targetNum: Int64?, segments: [Segment], badges: [Badge]) {
		self.originNum = originNum
		self.targetNum = targetNum
		self.segments = segments
		self.badges = badges
	}

	init(legs: TraceRouteLegs, positions: [Int64: CLLocationCoordinate2D]) {
		let map = TraceRouteMapLayout(legs: legs, positions: positions)
		segments = map.segments.map { segment in
			let shared = map.segments.contains { $0.isBack != segment.isBack && $0.fromNum == segment.toNum && $0.toNum == segment.fromNum }
			return Segment(id: segment.id, isBack: segment.isBack, fromNum: segment.fromNum, toNum: segment.toNum, snr: segment.snr, sharesLeg: shared)
		}
		badges = map.badges.compactMap { badge in
			let stops = badge.isBack ? legs.back : legs.forward
			guard stops.indices.contains(badge.number) else { return nil }
			return Badge(id: badge.id, isBack: badge.isBack, number: badge.number, num: stops[badge.number].num)
		}
		originNum = legs.forward.first.flatMap { positions[$0.num] != nil ? $0.num : nil }
		targetNum = legs.forward.last.flatMap { positions[$0.num] != nil ? $0.num : nil }
	}
}

/// Sizes and placement for the route lines in the volume. Lengths are in meters in the room; the
/// scene multiplies them by its counter-scale to get model units.
enum SpatialRouteGeometry {
	static let forwardWidth: Float = 0.0032
	static let backWidth: Float = 0.0028
	/// How much wider the dark edge is than the line.
	static let casingExtra: Float = 0.0014
	/// How far each direction of a shared leg moves to its own side.
	static let sharedOffset: Float = 0.0032
	static let dashLength: Float = 0.007
	static let dashGap: Float = 0.004
	/// Unknown-SNR forward legs get shorter dashes, like the 2D map.
	static let shortDashLength: Float = 0.003
	static let shortDashGap: Float = 0.004
	static let chevronSpacing: Float = 0.04
	/// Chevrons stay this far from either end of a leg so they don't sit on the pins.
	static let chevronMargin: Float = 0.012
	/// Meters per second the chevrons drift along their leg.
	static let chevronDrift: Float = 0.008
	/// SNR pills keep this far apart.
	static let pillMinSeparation: Float = 0.05
	/// A pill keeps this far from a node on the route so it doesn't cover the pin or its badges.
	static let pillNodeClearance: Float = 0.05
	/// A leg shorter than this in the room has no SNR pill.
	static let pillMinLegLength: Float = 0.04

	/// The unit vector to the right of travel from `from` to `to`, level with the ground. Zero for a
	/// leg that goes straight up or has no length.
	static func rightSide(from: SIMD3<Float>, to: SIMD3<Float>) -> SIMD3<Float> {
		let flat = SIMD3<Float>(to.x - from.x, 0, to.z - from.z)
		let length = simd_length(flat)
		guard length > 1e-6 else { return .zero }
		// Up is +y, so right of the travel direction d is d × up.
		return simd_cross(flat / length, [0, 1, 0])
	}

	/// The dashes along a line `length` long, as start and end distances. The pattern is centered so
	/// both ends get the same partial dash; a line shorter than one dash is one dash.
	static func dashes(length: Float, dash: Float, gap: Float) -> [SIMD2<Float>] {
		guard length > 0 else { return [] }
		guard dash > 0, gap >= 0, length > dash else { return [SIMD2(0, length)] }
		let period = dash + gap
		// A little slack so a length that fits a whole number of dashes isn't short one to rounding.
		let count = Int(((length + gap) / period + 1e-4).rounded(.down))
		let used = Float(count) * period - gap
		let start = (length - used) / 2
		return (0..<count).map { i in
			let a = start + Float(i) * period
			return SIMD2(a, min(a + dash, length))
		}
	}

	/// Distances along a leg `length` long for chevrons `spacing` apart, kept `margin` from both
	/// ends and moved on by `phase` so they can drift, wrapping round. At least one, in the
	/// middle, when the leg is too short for the margins.
	static func marks(length: Float, spacing: Float, margin: Float, phase: Float = 0) -> [Float] {
		guard length > 0, spacing > 0 else { return [] }
		let usable = length - 2 * margin
		guard usable > 0 else { return [length / 2] }
		let count = max(Int((usable / spacing).rounded(.down)), 1)
		// Evenly spread over the usable stretch; a mark pushed past its end comes back at the start.
		let step = usable / Float(count)
		let offset = phase.truncatingRemainder(dividingBy: usable)
		let wrapped = offset < 0 ? offset + usable : offset
		return (0..<count).map { i in
			var distance = (Float(i) + 0.5) * step + wrapped
			if distance >= usable { distance -= usable }
			return margin + distance
		}.sorted()
	}

	/// Where along a leg its pill may go, best first: its usual spot, then further along either
	/// way, so a pill that would cover a node or another pill can move instead of disappearing.
	static func pillFractions(preferred: Float) -> [Float] {
		[0, 0.15, -0.15, 0.3, -0.3, 0.45, -0.45].map { preferred + $0 }.filter { $0 > 0.1 && $0 < 0.9 }
	}

	/// For each item's candidate points (best first), the index of the first one at least
	/// `minDistance` from every point already chosen and `clearance` from every obstacle; nil when
	/// none fits. Items are placed in order, so earlier ones win.
	static func choose(_ candidates: [[SIMD3<Float>]], minDistance: Float, obstacles: [SIMD3<Float>] = [], clearance: Float = 0) -> [Int?] {
		var chosen: [SIMD3<Float>] = []
		return candidates.map { points in
			let index = points.firstIndex { point in
				obstacles.allSatisfy { simd_distance($0, point) >= clearance }
					&& chosen.allSatisfy { simd_distance($0, point) >= minDistance }
			}
			if let index { chosen.append(points[index]) }
			return index
		}
	}
}

/// The round edge of the table, for cutting a leg that runs past it. Points are mapped the way the
/// zoom preview shows them (`scale`, then `translation`) before testing against `radius`.
struct SpatialRouteClip: Equatable {
	let scale: Float
	let translation: SIMD2<Float>
	let radius: Float

	func isInside(_ point: SIMD3<Float>) -> Bool {
		let p = SIMD2(point.x, point.z) * scale + translation
		return simd_length_squared(p) <= radius * radius * 1.0001
	}

	/// The part of the line from `a` to `b` on the table, as the start and end fractions along
	/// it; nil when none of it is.
	func range(from a: SIMD3<Float>, to b: SIMD3<Float>) -> SIMD2<Float>? {
		let p = SIMD2(a.x, a.z) * scale + translation
		let d = SIMD2(b.x - a.x, b.z - a.z) * scale
		let qa = simd_length_squared(d)
		let qc = simd_length_squared(p) - radius * radius
		guard qa > 1e-12 else { return qc <= 0 ? SIMD2(0, 1) : nil }
		let qb = 2 * simd_dot(p, d)
		let discriminant = qb * qb - 4 * qa * qc
		guard discriminant > 0 else { return nil }
		let root = discriminant.squareRoot()
		let t0 = max((-qb - root) / (2 * qa), 0), t1 = min((-qb + root) / (2 * qa), 1)
		return t0 < t1 ? SIMD2(t0, t1) : nil
	}
}

extension SpatialMeshData {
	/// A closed square bar from `a` to `b`, `width` across, with its two ends capped so a short
	/// dash doesn't look hollow end on.
	mutating func addCappedBar(from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float) {
		guard simd_distance(a, b) > 1e-6 else { return }
		let axis = simd_normalize(b - a)
		addStrut(from: a, to: b, width: width)
		// addStrut's corners: 4 at `a`, then 4 at `b`.
		let corners = positions.suffix(8)
		let atA = Array(corners.prefix(4)), atB = Array(corners.suffix(4))
		for (end, normal, reversed) in [(atA, -axis, true), (atB, axis, false)] {
			let first = UInt32(positions.count)
			positions += end
			normals += Array(repeating: normal, count: 4)
			indices += reversed
				? [first, first + 2, first + 1, first, first + 3, first + 2]
				: [first, first + 1, first + 2, first, first + 2, first + 3]
		}
	}

	/// Capped bars along `from` → `to` for each dash, given as start and end distances.
	mutating func addDashes(from a: SIMD3<Float>, to b: SIMD3<Float>, dashes: [SIMD2<Float>], width: Float) {
		let length = simd_distance(a, b)
		guard length > 1e-6 else { return }
		let direction = (b - a) / length
		for dash in dashes {
			addCappedBar(from: a + direction * dash.x, to: a + direction * dash.y, width: width)
		}
	}
}
