//
//  SpatialCoverageEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
#if os(visionOS)
import CoreGraphics
import RealityKit

/// The coverage overlay: the Site Planner image draped over the terrain, as see-through as the
/// Coverage Opacity setting says.
enum SpatialCoverageEntity {
	/// Above the weather radar and drawn after it, so the estimate reads over the rain.
	static let layer = SpatialOverlayLayer(name: "coverage", lift: SpatialTerrainGeometry.overlayLift, sortOrder: 1)

	@MainActor
	static func make(geometry: SpatialTerrainGeometry, image: CGImage, opacity: Float) async throws -> ModelEntity {
		try await SpatialOverlayEntity.make(layer: layer, geometry: geometry, image: image, opacity: opacity)
	}
}
#endif
