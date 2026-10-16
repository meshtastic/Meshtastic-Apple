//
//  SpatialTerrainBuilder.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreGraphics
import Foundation
import OSLog

struct SpatialTerrainOptions: Equatable, Sendable {
	var layer: MapLayer = .standard
	var dark = false
	var verticalExaggeration = 1.5
	var maxTriangles = 400_000
	var textureEdge = 2048
	var modelSize: SIMD3<Float> = [1, 0.3, 1]
	var allowNetwork = true
	/// A downloaded basemap covers the box: the Offline layer, and the fallback when the Apple
	/// snapshot fails, draw it.
	var offlineBasemap = false
	/// Stroke contour lines from the downloaded terrain onto the texture.
	var contours = false
	/// Contour spacing in round meters rather than round feet.
	var metric = true
}

enum SpatialTextureSource: Equatable, Sendable {
	case appleMaps(MapLayer)
	/// The downloaded offline map under the hillshade.
	case offlineMap
	/// Land color, basemap water and the hillshade: no offline map covers the box.
	case terrainShading
}

/// A built terrain: the mesh and the image to drape over it.
struct SpatialTerrainModel: @unchecked Sendable {
	let bounds: GeoBounds
	let geometry: SpatialTerrainGeometry
	/// Immutable once made; CGImage is just not marked Sendable.
	let texture: CGImage
	let textureSource: SpatialTextureSource
	/// The Apple snapshot was wanted but could not be made, so the texture is the offline fallback.
	let imageryUnavailable: Bool
}

/// Builds a terrain model for a box off the main actor. The map snapshot and the elevation
/// sampling run at the same time, as does decoding the offline map for the Offline layer. The
/// offline composite is the fallback when there is no snapshot.
final class SpatialTerrainBuilder: Sendable {
	let elevation: any ElevationTileSource

	init(elevation: any ElevationTileSource) {
		self.elevation = elevation
	}

	nonisolated func build(bounds: GeoBounds, options: SpatialTerrainOptions) async throws -> SpatialTerrainModel {
		let started = Date()
		let frame = SpatialFrame(bounds: bounds)
		let pixelSize = SpatialTextureRenderer.pixelSize(for: frame, maxEdge: options.textureEdge)
		let wantsSnapshot = options.layer != .offline && options.allowNetwork
		async let snapshot: CGImage? = wantsSnapshot
			? SpatialTextureRenderer.snapshot(frame: frame, pixelSize: pixelSize, layer: options.layer, dark: options.dark)
			: nil
		let width = Int(pixelSize.width)
		async let offlineShapes: SpatialOfflineMap.Shapes? = options.layer == .offline
			? SpatialOfflineMap.decode(frame: frame, width: width)
			: nil

		let dataZoom = await elevation.finestDataZoom()
		let grid: SpatialHeightGrid
		if let dataZoom {
			let plan = SpatialHeightGrid.plan(frame: frame, maxTriangles: options.maxTriangles, dataMaxZoom: dataZoom)
			grid = try await SpatialHeightGrid.sample(frame: frame, plan: plan, source: elevation).cleaned()
		} else {
			grid = SpatialHeightGrid(columns: 2, rows: 2, heights: [0, 0, 0, 0], covered: [false, false, false, false], baseElevation: 0, maxElevation: 0)
		}
		try Task.checkCancellation()
		let transform = SpatialModelTransform(
			frame: frame, baseElevation: Double(grid.baseElevation), maxElevation: Double(grid.maxElevation),
			verticalExaggeration: options.verticalExaggeration, modelSize: options.modelSize
		)
		let geometry = SpatialTerrainGeometry(grid: grid, transform: transform)

		var textureSource = SpatialTextureSource.appleMaps(options.layer)
		var texture = await snapshot
		var basemap = await offlineShapes
		let imageryUnavailable = texture == nil && wantsSnapshot
		if texture == nil {
			if basemap == nil, options.offlineBasemap, options.layer != .offline {
				basemap = SpatialOfflineMap.decode(frame: frame, width: width)
			}
			try Task.checkCancellation()
			textureSource = basemap == nil ? .terrainShading : .offlineMap
			texture = await SpatialTextureRenderer.offlineComposite(frame: frame, pixelSize: pixelSize, dark: options.dark, basemap: basemap, source: elevation)
		}
		try Task.checkCancellation()
		guard var texture else { throw CancellationError() }
		if options.contours, let dataZoom, grid.hasAnyTerrain {
			let relief = Double(grid.maxElevation) - max(Double(grid.baseElevation), 0)
			let intervals = SpatialTerrainContours.intervals(relief: relief, metric: options.metric)
			let tiles = await SpatialTerrainContours.tiles(frame: frame, width: texture.width, dataZoom: dataZoom, intervals: intervals, source: elevation)
			try Task.checkCancellation()
			let imagery = textureSource == .appleMaps(.satellite) || textureSource == .appleMaps(.hybrid)
			if let contoured = SpatialTerrainContours.draw(tiles, over: texture, frame: frame, imagery: imagery) {
				texture = contoured
			}
		}
		Logger.services.info("🧊 [Spatial] Built terrain \(grid.columns)x\(grid.rows) (\(geometry.surfaceTriangleCount) triangles, terrain: \(grid.hasAnyTerrain), \(String(describing: textureSource), privacy: .public)) in \(String(format: "%.2f", Date().timeIntervalSince(started)), privacy: .public)s")
		return SpatialTerrainModel(bounds: bounds, geometry: geometry, texture: texture, textureSource: textureSource, imageryUnavailable: imageryUnavailable)
	}
}
