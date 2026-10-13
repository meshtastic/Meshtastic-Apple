//
//  SpatialVolumeFit.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import Foundation
import simd

/// How the round map sits in the volume: centered on the baseplate and filling its footprint,
/// less a margin around the rim for the bezel and its handles. Resizing the volume resizes the map.
struct SpatialVolumeFit: Equatable, Sendable {
	/// Room left between the disk and the volume's side, in meters, for the bezel and handles.
	static let rimMargin: Float = 0.07
	/// The disk keeps at least this radius in meters, however small the volume is.
	static let minimumDiskRadius: Float = 0.1
	/// Volume sizes the window opens at and allows, in meters (width, height, depth).
	static let defaultSize = SIMD3<Double>(1.1, 0.7, 1.1)
	static let minimumSize = SIMD3<Double>(0.6, 0.45, 0.6)
	static let maximumSize = SIMD3<Double>(2.0, 1.3, 2.0)

	/// Radius of the disk in meters.
	let diskRadius: Float
	/// Meters per model unit, so a model disk of the given radius comes out `diskRadius` across.
	let scale: Float

	init(volumeWidth: Float, volumeDepth: Float, modelDiskRadius: Float) {
		let side = min(volumeWidth, volumeDepth)
		let radius = side.isFinite ? side / 2 - Self.rimMargin : 0
		diskRadius = max(radius, Self.minimumDiskRadius)
		scale = modelDiskRadius > 0 && modelDiskRadius.isFinite ? diskRadius / modelDiskRadius : 1
	}
}
