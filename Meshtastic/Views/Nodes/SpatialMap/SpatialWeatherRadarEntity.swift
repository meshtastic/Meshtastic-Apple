//
//  SpatialWeatherRadarEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
#if os(visionOS)
import CoreGraphics
import RealityKit

/// The weather radar as cloud: NOAA rain on a few soft sheets floating level over the highest
/// ground, drifting slowly up and down, with a faint shadow of it draped on the terrain. The shadow
/// sits under the coverage overlay and the sheets over it, and each is drawn in that order, so
/// neither hides the other as the viewer moves.
enum SpatialWeatherRadarEntity {
	static let shadowLayer = SpatialOverlayLayer(name: "weatherRadarShadow", lift: SpatialTerrainGeometry.overlayLift / 2, sortOrder: 0)

	/// The sheets, bottom first, drawn after the coverage (sort order 1).
	static func sheetLayer(_ index: Int) -> SpatialOverlayLayer {
		SpatialOverlayLayer(name: "weatherRadarSheet\(index)", lift: 0, sortOrder: Int32(2 + index))
	}

	static let sheetsName = "weatherRadarSheets"
	/// How far the sheets drift up and down, in model units, and how long one rise and fall takes.
	static let drift: Float = 0.004
	static let driftPeriod: Double = 12

	@MainActor
	static func make(geometry: SpatialTerrainGeometry, images: SpatialRainClouds.Images) async throws -> Entity {
		let root = Entity()
		root.name = "weatherRadar"
		let shadow = try await SpatialOverlayEntity.make(layer: shadowLayer, geometry: geometry, image: images.shadow, opacity: SpatialRainClouds.shadowOpacity)
		root.addChild(shadow)

		let sheets = Entity()
		sheets.name = sheetsName
		let deck = geometry.cloudDeckHeight
		for (index, layer) in SpatialRainClouds.layers.enumerated() where index < images.sheets.count {
			let sheet = try await SpatialOverlayEntity.make(
				layer: sheetLayer(index), surface: geometry.deckSurface(height: deck + layer.rise), image: images.sheets[index], opacity: layer.opacity
			)
			sheets.addChild(sheet)
		}
		root.addChild(sheets)
		// The drift is started by the scene, which knows whether Reduce Motion is on.
		return root
	}

	/// Puts a new period's rain on the shadow and every sheet, without rebuilding their meshes.
	@MainActor
	static func setImages(_ images: SpatialRainClouds.Images, on root: Entity) async throws {
		if let shadow = root.findEntity(named: shadowLayer.name) as? ModelEntity {
			SpatialOverlayEntity.setTexture(try await SpatialOverlayEntity.texture(for: images.shadow), on: shadow)
		}
		for (index, image) in images.sheets.enumerated() {
			guard let sheet = root.findEntity(named: sheetLayer(index).name) as? ModelEntity else { continue }
			SpatialOverlayEntity.setTexture(try await SpatialOverlayEntity.texture(for: image), on: sheet)
		}
	}

	/// Starts the sheets' drift, or holds them still with Reduce Motion.
	@MainActor
	static func setReduceMotion(_ reduceMotion: Bool, on root: Entity) {
		guard let sheets = root.findEntity(named: sheetsName) else { return }
		sheets.stopAllAnimations()
		sheets.position = .zero
		if !reduceMotion { startDrift(sheets) }
	}

	@MainActor
	private static func startDrift(_ sheets: Entity) {
		let rise = FromToByAnimation<Transform>(
			from: Transform(translation: [0, -drift / 2, 0]), to: Transform(translation: [0, drift / 2, 0]),
			duration: driftPeriod / 2, timing: .easeInOut, bindTarget: .transform, repeatMode: .autoReverse
		)
		guard let animation = try? AnimationResource.generate(with: rise) else { return }
		sheets.playAnimation(animation)
	}
}
#endif
