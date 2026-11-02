//
//  LookoutMarkerGrouping.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
import Foundation

/// Where the markers for the nodes out the lookout's windows go, by where each node is in the
/// view. Kept apart from the lookout's visionOS code so it can be tested.
enum LookoutMarkerGrouping {
	/// How wide a node's marker is in degrees of the view, whatever its distance.
	static let markerWidthDegrees = 2.4
	/// How far a marker's stem reaches down from the marker toward its node, in degrees: about a
	/// marker's height, so the marker stands clear of the ridge its node is on.
	static let stemDegrees = 2.5
	/// The lowest a marker's stem reaches. The sill is about 6.6° below level from the seat, so a
	/// node down in the valley still shows, its marker standing at the bottom of the view.
	static let lowestMarkerDegrees = -4.0
	/// How close two markers' centers can come, in degrees, before they're taken to cover each
	/// other. A little under a marker's width, so neighbors may just touch.
	static let clearanceDegrees = markerWidthDegrees * 0.9
	/// How many heights a marker can stand at: its own, then on a taller stem a marker's width
	/// higher each time, to clear the markers beside it.
	static let levels = 3

	/// A marker: the nodes it stands for, as indexes, the first being the one it stands over, and
	/// its center in degrees above level.
	struct Marker: Equatable {
		var members: [Int]
		let center: Double
	}

	/// The lowest a marker over a node `elevation` degrees above level stands.
	static func center(elevation: Double) -> Double {
		max(elevation, lowestMarkerDegrees) + stemDegrees + markerWidthDegrees / 2
	}

	/// Where the stem under a marker over a node `elevation` degrees above level ends.
	static func stemFoot(elevation: Double) -> Double {
		max(elevation, lowestMarkerDegrees)
	}

	/// The markers for the nodes at `points` (azimuth and elevation in degrees, nearest node
	/// first). Each node gets a marker of its own, raised on a taller stem when one already placed
	/// is in the way; only when every height is taken does it join the marker nearest where its
	/// own would have stood.
	static func markers(_ points: [(azimuth: Double, elevation: Double)]) -> [Marker] {
		var markers: [Marker] = []
		var azimuths: [Double] = []
		for (index, point) in points.enumerated() {
			let base = center(elevation: point.elevation)
			func covers(_ marker: Int, at center: Double) -> Bool {
				azimuthGap(point.azimuth, azimuths[marker]) < clearanceDegrees
					&& abs(center - markers[marker].center) < clearanceDegrees
			}
			let heights = (0..<levels).map { base + Double($0) * markerWidthDegrees }
			if let free = heights.first(where: { height in !markers.indices.contains { covers($0, at: height) } }) {
				markers.append(Marker(members: [index], center: free))
				azimuths.append(point.azimuth)
				continue
			}
			// Every height is taken, the lowest among them, so some marker covers that one.
			let blocking = markers.indices.filter { covers($0, at: base) }
			if let nearest = blocking.min(by: { abs(markers[$0].center - base) < abs(markers[$1].center - base) }) {
				markers[nearest].members.append(index)
			}
		}
		return markers
	}

	static func azimuthGap(_ a: Double, _ b: Double) -> Double {
		let gap = abs(a - b).truncatingRemainder(dividingBy: 360)
		return min(gap, 360 - gap)
	}
}
