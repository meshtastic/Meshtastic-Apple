//
//  SpatialWeatherRadarEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
#if os(visionOS)
import CoreGraphics
import RealityKit

/// The weather radar overlay: NOAA rain draped over the terrain at the 2D map's strength. It
/// floats under the coverage overlay and is drawn before it, so the Site Planner's colors read
/// over the rain.
enum SpatialWeatherRadarEntity {
	static let layer = SpatialOverlayLayer(name: "weatherRadar", lift: SpatialTerrainGeometry.overlayLift / 2, sortOrder: 0)

	@MainActor
	static func make(geometry: SpatialTerrainGeometry, image: CGImage) async throws -> ModelEntity {
		try await SpatialOverlayEntity.make(layer: layer, geometry: geometry, image: image, opacity: Float(WeatherRadar.opacity))
	}
}
#endif
