//
//  SpatialFlyover.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import Foundation
import simd

/// Moves a marker along a route's legs over the model: a steady cruise, a slow landing at the end
/// of each leg, a short hold, then the next leg. Pure, so the timing is testable.
struct SpatialFlyover: Equatable {
	struct Leg: Equatable {
		let points: [SIMD3<Float>]
		let cumulative: [Float]
		let duration: TimeInterval
		/// Index of this leg in the paths passed in, which can differ when a path was too short.
		let source: Int
		var length: Float { cumulative.last ?? 0 }
	}

	/// Model meters per second at the cruise.
	static let cruiseSpeed: Float = 0.08
	static let minLegDuration: TimeInterval = 2.5
	static let maxLegDuration: TimeInterval = 12
	static let landingHold: TimeInterval = 1.2
	static let landingTail = 0.22

	let legs: [Leg]
	private(set) var legIndex = 0
	private(set) var progress = 0.0
	private(set) var holdRemaining: TimeInterval = 0
	var isFinished: Bool { legIndex >= legs.count }
	var speedMultiplier = 1.0

	init(legs paths: [[SIMD3<Float>]]) {
		legs = paths.enumerated().compactMap { source, points in
			guard points.count >= 2 else { return nil }
			var cumulative: [Float] = [0]
			for i in 1..<points.count { cumulative.append(cumulative[i - 1] + simd_distance(points[i - 1], points[i])) }
			guard let length = cumulative.last, length > 0 else { return nil }
			let duration = min(max(TimeInterval(length / Self.cruiseSpeed), Self.minLegDuration), Self.maxLegDuration)
			return Leg(points: points, cumulative: cumulative, duration: duration, source: source)
		}
	}

	/// The same flight over new positions for its legs, such as after the map zooms: the leg,
	/// progress and hold carry over. Nil when the new paths don't give the same legs.
	func moved(to paths: [[SIMD3<Float>]]) -> SpatialFlyover? {
		var next = SpatialFlyover(legs: paths)
		guard next.legs.map(\.source) == legs.map(\.source) else { return nil }
		next.legIndex = legIndex
		next.progress = progress
		next.holdRemaining = holdRemaining
		next.speedMultiplier = speedMultiplier
		return next
	}

	/// Advances by `dt` seconds and returns the marker position, nil once the route is flown.
	mutating func advance(by dt: TimeInterval) -> SIMD3<Float>? {
		guard legIndex < legs.count else { return nil }
		if holdRemaining > 0 {
			holdRemaining -= dt
			let end = legs[legIndex].points.last
			if holdRemaining <= 0 {
				legIndex += 1
				progress = 0
				holdRemaining = 0
			}
			return end
		}
		let leg = legs[legIndex]
		progress = min(progress + dt * speedMultiplier / leg.duration, 1)
		let position = Self.point(on: leg, at: Float(Self.eased(progress)) * leg.length)
		if progress >= 1 { holdRemaining = Self.landingHold }
		return position
	}

	/// How far along the current leg the marker was `ago` seconds of flight earlier, ignoring the
	/// speed multiplier, clamped to the start of the leg. While holding, it counts the hold first,
	/// so a trail behind the marker catches up with it. Nil once the route is flown.
	func distanceBack(_ ago: TimeInterval) -> Float? {
		guard legIndex < legs.count else { return nil }
		let leg = legs[legIndex]
		var raw = progress
		if holdRemaining > 0 {
			let held = Self.landingHold - holdRemaining
			if ago <= held { return leg.length }
			raw = 1 - (ago - held) / leg.duration
		} else {
			raw -= ago / leg.duration
		}
		return Float(Self.eased(max(raw, 0))) * leg.length
	}

	/// Constant speed, then a smooth deceleration over the last stretch of the leg.
	static func eased(_ raw: Double) -> Double {
		let tail = landingTail
		let cruise = 1 / (1 - tail / 2)
		if raw <= 1 - tail { return cruise * raw }
		let u = (raw - (1 - tail)) / tail
		return min(cruise * ((1 - tail) + tail * (u - u * u / 2)), 1)
	}

	static func point(on leg: Leg, at distance: Float) -> SIMD3<Float> {
		let s = min(max(distance, 0), leg.length)
		var index = 0
		while index < leg.cumulative.count - 2 && leg.cumulative[index + 1] < s { index += 1 }
		let start = leg.cumulative[index]
		let segment = max(leg.cumulative[index + 1] - start, 0.0001)
		let t = min(max((s - start) / segment, 0), 1)
		return simd_mix(leg.points[index], leg.points[index + 1], SIMD3(repeating: t))
	}
}
