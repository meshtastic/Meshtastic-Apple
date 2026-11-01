//
//  LookoutLabelLayout.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
#if os(visionOS)
import Foundation
import simd

/// Where the nodes' labels hang out the lookout's windows.
extension LookoutTerrain {
	/// How wide a node's label is in degrees of the view, whatever its distance.
	static let labelWidthDegrees = 6.0
	/// The lowest a label's center hangs. The sill is about 6.6° below level from the seat, so a
	/// node down in the valley still shows, on a leader line to where it is.
	static let lowestLabelDegrees = -4.0

	/// Where a node's label hangs: the node's direction from the eye, in degrees clockwise from
	/// the cab's front and above level, the label's center after it was lifted clear of the sill
	/// and of the labels placed before it, and how far out it is drawn.
	struct LabelSpot {
		let azimuth: Double
		let elevation: Double
		let center: Double
		let depth: Float
		var lift: Double { center - elevation }
	}

	/// Spots for `labels` in order, nearest first, lifting each above any earlier label it would
	/// cover. `heightRatio` is a label's height over its width.
	static func spots(for labels: [LookoutLabel], heightRatio: Double, heading: Double = frontHeading) -> [LabelSpot] {
		let halfHeight = labelWidthDegrees * heightRatio / 2
		struct Placed {
			let azimuth: Double
			let bottom: Double
			let top: Double
		}
		var placed: [Placed] = []
		return labels.map { label in
			let azimuth = (label.bearing - heading + 360).truncatingRemainder(dividingBy: 360)
			let drop = label.distance * label.distance / (2 * earthRadius)
			let elevation = atan2(label.rise - drop, label.distance) * 180 / .pi
			var center = max(elevation, lowestLabelDegrees)
			var lifted = true
			while lifted {
				lifted = false
				for other in placed where azimuthGap(azimuth, other.azimuth) < labelWidthDegrees
					&& center - halfHeight < other.top && center + halfHeight > other.bottom {
					center = other.top + halfHeight + 0.3
					lifted = true
				}
			}
			placed.append(Placed(azimuth: azimuth, bottom: center - halfHeight, top: center + halfHeight))
			// Just in front of the ground at the node's distance, so nearer ridges hide it as they
			// would, and whatever is behind it doesn't.
			return LabelSpot(azimuth: azimuth, elevation: elevation, center: center, depth: depth(label.distance) - 3)
		}
	}

	/// The unit direction `azimuth` degrees clockwise from the cab's front and `elevation` degrees
	/// above level.
	static func direction(azimuth: Double, elevation: Double) -> SIMD3<Float> {
		let around = azimuth * .pi / 180
		let up = elevation * .pi / 180
		return SIMD3(Float(sin(around) * cos(up)), Float(sin(up)), Float(-cos(around) * cos(up)))
	}

	private static func azimuthGap(_ a: Double, _ b: Double) -> Double {
		let gap = abs(a - b).truncatingRemainder(dividingBy: 360)
		return min(gap, 360 - gap)
	}
}
#endif
