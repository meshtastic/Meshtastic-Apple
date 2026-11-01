//
//  LookoutLabelLayout.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
#if os(visionOS)
import Foundation
import simd

/// Where the nodes' markers hang out the lookout's windows.
extension LookoutTerrain {
	static let markerWidthDegrees = LookoutMarkerGrouping.markerWidthDegrees
	static let stemDegrees = LookoutMarkerGrouping.stemDegrees
	static let lowestMarkerDegrees = LookoutMarkerGrouping.lowestMarkerDegrees

	/// One marker out the windows: a node, or, where there's no room, the nodes whose markers would
	/// cover each other, nearest first. The marker stands over the nearest of them. `azimuth` is
	/// degrees clockwise from the cab's front, `elevation` the nearest node's direction above level,
	/// `center` the marker's middle, raised to clear its neighbors, and `depth` how far out it is
	/// drawn.
	struct MarkerSpot {
		let labels: [LookoutLabel]
		let azimuth: Double
		let elevation: Double
		let center: Double
		let depth: Float

		var lead: LookoutLabel { labels[0] }
		/// Where the stem meets the ground, or the bottom of the view for a node below it.
		var stemFoot: Double { LookoutMarkerGrouping.stemFoot(elevation: elevation) }
	}

	/// Markers for `labels`, which come nearest first, seen from a cab facing `heading`.
	static func markers(for labels: [LookoutLabel], heading: Double = frontHeading) -> [MarkerSpot] {
		let points = labels.map { label in
			let azimuth = (label.bearing - heading + 360).truncatingRemainder(dividingBy: 360)
			let drop = label.distance * label.distance / (2 * earthRadius)
			return (azimuth: azimuth, elevation: atan2(label.rise - drop, label.distance) * 180 / .pi)
		}
		return LookoutMarkerGrouping.markers(points).map { marker in
			let lead = points[marker.members[0]]
			// Just in front of the ground at the nearest node's distance, so nearer ridges hide it
			// as they would, and whatever is behind it doesn't.
			return MarkerSpot(
				labels: marker.members.map { labels[$0] },
				azimuth: lead.azimuth,
				elevation: lead.elevation,
				center: marker.center,
				depth: depth(labels[marker.members[0]].distance) - 3
			)
		}
	}

	/// The unit direction `azimuth` degrees clockwise from the cab's front and `elevation` degrees
	/// above level.
	static func direction(azimuth: Double, elevation: Double) -> SIMD3<Float> {
		let around = azimuth * .pi / 180
		let up = elevation * .pi / 180
		return SIMD3(Float(sin(around) * cos(up)), Float(sin(up)), Float(-cos(around) * cos(up)))
	}
}
#endif
