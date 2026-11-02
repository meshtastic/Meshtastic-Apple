//
//  LookoutCardPlacement.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
import Foundation
import simd

/// Where the card for a marker out the lookout's windows opens: from the viewer's own eye, at
/// reading distance, just to the right of the marker as the viewer sees it, and no lower than a
/// little under level. Placed from the painted image's eye point instead, the card only lined up
/// with its marker for a head sitting exactly there.
enum LookoutCardPlacement {
	/// How far from the eye the card hangs: inside the cab, near enough to read.
	static let distance: Float = 1.4
	/// The card never opens lower than this, in degrees below level, so it stays off the sill.
	static let lowestDegrees: Double = -2
	/// Room between the marker's edge and the card's, in degrees.
	static let gapDegrees: Double = 1

	/// The card's center, with `eye` and `marker` in the same frame, y up.
	static func center(eye: SIMD3<Float>, marker: SIMD3<Float>, markerWidthDegrees: Double, cardHalfWidth: Float) -> SIMD3<Float> {
		let toMarker = marker - eye
		let flat = Double(simd_length(SIMD2(toMarker.x, toMarker.z)))
		let azimuth = atan2(Double(toMarker.x), Double(-toMarker.z)) * 180 / .pi
		let elevation = atan2(Double(toMarker.y), flat) * 180 / .pi
		let cardHalfDegrees = Double(atan(cardHalfWidth / distance)) * 180 / .pi
		let direction = direction(
			azimuth: azimuth + markerWidthDegrees / 2 + gapDegrees + cardHalfDegrees,
			elevation: max(elevation, lowestDegrees)
		)
		return eye + direction * distance
	}

	/// The unit direction at `azimuth` degrees clockwise from straight ahead (-z) and `elevation`
	/// degrees above level.
	static func direction(azimuth: Double, elevation: Double) -> SIMD3<Float> {
		let around = azimuth * .pi / 180
		let up = elevation * .pi / 180
		return SIMD3(Float(sin(around) * cos(up)), Float(sin(up)), Float(-cos(around) * cos(up)))
	}
}
