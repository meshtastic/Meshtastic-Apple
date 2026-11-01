//
//  LookoutMarkerGrouping.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
import Foundation

/// Which nodes out the lookout's windows share a marker, by where each is in the view. Kept apart
/// from the lookout's visionOS code so it can be tested.
enum LookoutMarkerGrouping {
	/// How wide a node's marker is in degrees of the view, whatever its distance.
	static let markerWidthDegrees = 2.4
	/// How far a marker's stem reaches down from the marker toward its node, in degrees.
	static let stemDegrees = 1.0
	/// The lowest a marker's stem reaches. The sill is about 6.6° below level from the seat, so a
	/// node down in the valley still shows, its marker standing at the bottom of the view.
	static let lowestMarkerDegrees = -4.0

	/// The middle of the marker over a node `elevation` degrees above level.
	static func center(elevation: Double) -> Double {
		max(elevation, lowestMarkerDegrees) + stemDegrees + markerWidthDegrees / 2
	}

	/// The nodes at `points` (azimuth and elevation in degrees, nearest node first) grouped by
	/// marker, as indexes into `points`. A node whose marker would overlap one already placed
	/// joins it instead of being stacked above it; each group's first node is the one it stands
	/// over.
	static func groups(_ points: [(azimuth: Double, elevation: Double)]) -> [[Int]] {
		var groups: [[Int]] = []
		for (index, point) in points.enumerated() {
			let center = center(elevation: point.elevation)
			if let group = groups.firstIndex(where: {
				let lead = points[$0[0]]
				return azimuthGap(point.azimuth, lead.azimuth) < markerWidthDegrees
					&& abs(center - Self.center(elevation: lead.elevation)) < markerWidthDegrees
			}) {
				groups[group].append(index)
			} else {
				groups.append([index])
			}
		}
		return groups
	}

	static func azimuthGap(_ a: Double, _ b: Double) -> Double {
		let gap = abs(a - b).truncatingRemainder(dividingBy: 360)
		return min(gap, 360 - gap)
	}
}
