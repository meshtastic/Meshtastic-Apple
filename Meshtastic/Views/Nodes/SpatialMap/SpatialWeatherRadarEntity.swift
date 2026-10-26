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
/// floats under the coverage overlay, so the Site Planner's colors read over the rain and the two
/// sheets never share a plane.
enum SpatialWeatherRadarEntity {
	static let name = "weatherRadar"
	static let lift = SpatialTerrainGeometry.overlayLift / 2

	@MainActor
	static func make(geometry: SpatialTerrainGeometry, image: CGImage) async throws -> ModelEntity {
		try await SpatialOverlayEntity.make(name: name, lift: lift, geometry: geometry, image: image, opacity: Float(WeatherRadar.opacity))
	}
}
#endif
