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
	static let name = "coverage"

	@MainActor
	static func make(geometry: SpatialTerrainGeometry, image: CGImage, opacity: Float) async throws -> ModelEntity {
		try await SpatialOverlayEntity.make(name: name, lift: SpatialTerrainGeometry.overlayLift, geometry: geometry, image: image, opacity: opacity)
	}
}
#endif
