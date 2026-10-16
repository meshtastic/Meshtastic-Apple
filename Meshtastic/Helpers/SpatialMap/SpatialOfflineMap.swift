//
//  SpatialOfflineMap.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
import CoreGraphics
import CoreLocation
import OSLog
import UIKit

/// The spatial map's Offline layer: the downloaded Protomaps basemaps drawn onto the terrain
/// texture with the 2D offline map's decoder and colors.
enum SpatialOfflineMap {
	/// Most vector tiles decoded for one build, across all the basemaps.
	static let maxTiles = 64
	/// Strokes are twice the 2D map's point widths, the same 2x the Apple snapshot is drawn at.
	static let strokeScale: CGFloat = 2

	// MARK: Layer choice

	/// Whether the region's basemap is vector tiles the Offline layer can draw. Downloads are always
	/// Protomaps vector tiles; an imported archive can be raster, so it is nil until its file has
	/// been checked (`checked`, by region ID).
	static func isVectorBasemap(_ region: OfflineMapRegion, checked: [UUID: Bool]) -> Bool? {
		guard region.hasBasemap else { return false }
		guard region.sourceBuild == "Imported" else { return true }
		return checked[region.id]
	}

	/// Vector basemap boxes from the downloaded regions, the user's and the app's own. Imports not
	/// checked yet are left out.
	static func basemapBounds(_ regions: [OfflineMapRegion], checked: [UUID: Bool] = [:]) -> [GeoBounds] {
		regions.filter { isVectorBasemap($0, checked: checked) == true }.map(\.bounds)
	}

	/// Reads each archive's header to see whether it holds vector tiles. Blocking; run off the main thread.
	static func checkVectorTiles(_ files: [OfflineMapRegionFile]) -> [UUID: Bool] {
		var result: [UUID: Bool] = [:]
		for file in files {
			result[file.region.id] = OfflineTileSourceFactory.source(for: file.url)?.isVectorTiles ?? false
		}
		return result
	}

	/// Least share of the box one basemap must cover to offer the Offline layer.
	static let minimumCoverage = 0.25

	/// Whether one basemap covers enough of the box to offer the Offline layer: it holds the box's
	/// center and at least a quarter of its area. (Any box over half covered holds the center, so
	/// the center test alone would let a small town offer Offline for a whole region.)
	static func covers(_ box: GeoBounds, basemaps: [GeoBounds]) -> Bool {
		let center = CLLocationCoordinate2D(latitude: (box.minLat + box.maxLat) / 2, longitude: (box.minLon + box.maxLon) / 2)
		return basemaps.contains { $0.contains(center) && overlapFraction(of: box, with: $0) >= minimumCoverage }
	}

	/// How much of the box, by Mercator area, lies inside `other`.
	static func overlapFraction(of box: GeoBounds, with other: GeoBounds) -> Double {
		let width = box.maxLon - box.minLon
		let height = SpatialFrame.mercatorY(box.minLat) - SpatialFrame.mercatorY(box.maxLat)
		guard width > 0, height > 0 else { return other.contains(CLLocationCoordinate2D(latitude: box.minLat, longitude: box.minLon)) ? 1 : 0 }
		let minLon = max(box.minLon, other.minLon), maxLon = min(box.maxLon, other.maxLon)
		let minLat = max(box.minLat, other.minLat), maxLat = min(box.maxLat, other.maxLat)
		guard maxLon > minLon, maxLat > minLat else { return 0 }
		let overlapWidth = maxLon - minLon
		let overlapHeight = SpatialFrame.mercatorY(minLat) - SpatialFrame.mercatorY(maxLat)
		return overlapWidth * overlapHeight / (width * height)
	}

	/// The layers the picker offers. Offline only when a basemap covers the box.
	static func layers(offlineAvailable: Bool) -> [MapLayer] {
		offlineAvailable ? [.standard, .hybrid, .satellite, .offline] : [.standard, .hybrid, .satellite]
	}

	/// The layer to build with. The setting is shared with the 2D map, so Offline can be stored for
	/// an area no basemap covers; that builds as Standard rather than an empty map.
	static func buildLayer(_ stored: MapLayer, offlineAvailable: Bool) -> MapLayer {
		stored == .offline && !offlineAvailable ? .standard : stored
	}

	/// The basemap part of the terrain build key: each basemap's ID and update date, sorted, so
	/// downloading, updating or replacing one rebuilds the map. Only the Offline layer and a build
	/// that fell back to the offline map without imagery draw basemaps; the Apple layers leave it
	/// empty so a basemap change doesn't rebuild them while online.
	static func basemapGeneration(_ regions: [OfflineMapRegion], layer: MapLayer, usedFallback: Bool) -> String {
		guard layer == .offline || usedFallback else { return "" }
		return regions.filter(\.hasBasemap)
			.map { "\($0.id)\(Int($0.updatedDate.timeIntervalSince1970))" }
			.sorted()
			.joined(separator: ",")
	}

	// MARK: Tiles

	/// The zoom to decode at: one vector tile per 256–512 texels across the box, lowered until the
	/// box needs at most `maxTiles`, and kept inside the archive's zoom range.
	static func zoom(bounds: GeoBounds, width: Int, minZoom: Int, maxZoom: Int, maxTiles: Int = maxTiles) -> Int {
		let lonSpan = max(bounds.maxLon - bounds.minLon, 1e-9)
		let wanted = Double(width) / 256 * 360 / lonSpan
		var zoom = min(max(Int(log2(wanted).rounded(.down)), minZoom), maxZoom)
		while zoom > minZoom, tiles(bounds: bounds, zoom: zoom).count > maxTiles {
			zoom -= 1
		}
		return zoom
	}

	/// The tiles at `zoom` that the box touches.
	static func tiles(bounds: GeoBounds, zoom: Int) -> [OfflineVectorTileProvider.TileID] {
		let northWest = TerrainStore.tilePixel(latitude: bounds.maxLat, longitude: bounds.minLon, z: zoom, size: 256)
		let southEast = TerrainStore.tilePixel(latitude: bounds.minLat, longitude: bounds.maxLon, z: zoom, size: 256)
		var result: [OfflineVectorTileProvider.TileID] = []
		for y in northWest.y...southEast.y {
			for x in northWest.x...southEast.x {
				result.append(.init(z: zoom, x: x, y: y))
			}
		}
		return result
	}

	// MARK: Styling

	/// One stroke pass over the decoded lines of a role.
	struct Stroke: Equatable {
		let role: OfflineFeatureRole
		let color: UIColor
		let width: CGFloat
		let dash: [CGFloat]
		let cap: CGLineCap
	}

	/// Fill order: parks under water, as on the 2D map.
	static let fillOrder: [OfflineFeatureRole] = [.park, .green, .water]

	/// The 2D offline map's line passes in its order: rivers, road casings (light only), road fills,
	/// then dashed rail. Widths are scaled by `strokeScale`.
	static func strokes(dark: Bool) -> [Stroke] {
		var result = [Stroke(role: .river, color: OfflineMapPalette.riverStroke(dark: dark), width: 1.4 * strokeScale, dash: [], cap: .round)]
		let roads: [OfflineFeatureRole] = [.minorRoad, .mediumRoad, .majorRoad]
		for role in roads {
			guard let casing = OfflineMapPalette.roadCasing(role, dark: dark) else { continue }
			result.append(Stroke(role: role, color: casing, width: OfflineMapPalette.roadCasingWidth(role) * strokeScale, dash: [], cap: .round))
		}
		for role in roads {
			guard let fill = OfflineMapPalette.roadFill(role, dark: dark) else { continue }
			result.append(Stroke(role: role, color: fill, width: OfflineMapPalette.roadWidth(role) * strokeScale, dash: [], cap: .round))
		}
		if let rail = OfflineMapPalette.line(.rail, dark: dark) {
			result.append(Stroke(role: .rail, color: rail, width: strokeScale, dash: [2 * strokeScale, 3 * strokeScale], cap: .butt))
		}
		return result
	}

	// MARK: Decode and draw

	/// Decoded basemap features for a box. Immutable once made; the coordinate arrays are just
	/// not marked Sendable.
	struct Shapes: @unchecked Sendable {
		let polygons: [OfflineMapPolygon]
		let polylines: [OfflineMapPolyline]
	}

	/// Decodes the downloaded basemaps that touch the box. Nil when none do, or when cancelled.
	/// `maxTiles` is shared by all the basemaps, and a tile already inside a decoded basemap is not
	/// decoded again from an overlapping one.
	static func decode(frame: SpatialFrame, width: Int, files: [OfflineMapRegionFile] = OfflineMapManager.persistedRegionFiles()) -> Shapes? {
		let bounds = frame.bounds
		var polygons: [OfflineMapPolygon] = []
		var polylines: [OfflineMapPolyline] = []
		var tileCount = 0
		var decoded: [GeoBounds] = []
		let started = Date()
		for file in files where file.region.hasBasemap && file.region.bounds.intersects(bounds) {
			if Task.isCancelled { return nil }
			let remaining = maxTiles - tileCount
			guard remaining > 0 else { break }
			guard let source = OfflineTileSourceFactory.source(for: file.url), source.isVectorTiles else { continue }
			let coverage = source.geographicBounds ?? file.region.bounds
			guard coverage.intersects(bounds) else { continue }
			let zoom = zoom(bounds: bounds, width: width, minZoom: Int(source.tileMinZoom), maxZoom: Int(source.tileMaxZoom), maxTiles: remaining)
			let tiles = newTiles(tiles(bounds: bounds, zoom: zoom), coverage: coverage, decoded: decoded).prefix(remaining)
			guard !tiles.isEmpty else { continue }
			let result = OfflineVectorTileProvider.build(source: source, bounds: bounds, tiles: Array(tiles), shouldStop: { Task.isCancelled })
			if Task.isCancelled { return nil }
			tileCount += tiles.count
			decoded.append(coverage)
			polygons += result.polygons
			polylines += result.polylines
		}
		guard tileCount > 0 else { return nil }
		Logger.services.info("🧊 [Spatial] Offline map: \(polygons.count) fills, \(polylines.count) lines from \(tileCount) tiles in \(String(format: "%.2f", Date().timeIntervalSince(started)), privacy: .public)s")
		return Shapes(polygons: polygons, polylines: polylines)
	}

	/// The tiles that touch this basemap's coverage and are not wholly inside a basemap already decoded.
	static func newTiles(_ tiles: [OfflineVectorTileProvider.TileID], coverage: GeoBounds, decoded: [GeoBounds]) -> [OfflineVectorTileProvider.TileID] {
		tiles.filter { tile in
			let tileBounds = TerrainStore.tileBounds(z: tile.z, x: tile.x, y: tile.y)
			return tileBounds.intersects(coverage) && !decoded.contains { $0.contains(tileBounds) }
		}
	}

	/// Paints the fills and lines over whatever the context holds (the land color).
	static func draw(_ shapes: Shapes, frame: SpatialFrame, size: CGSize, dark: Bool, in context: CGContext) {
		let fills = Dictionary(grouping: shapes.polygons, by: \.role)
		for role in fillOrder {
			guard let polygons = fills[role], let color = OfflineMapPalette.fill(role, dark: dark) else { continue }
			context.setFillColor(color.cgColor)
			// Each polygon on its own with even-odd, so holes stay open and overlapping
			// neighbors from the tile buffers don't cancel out.
			for polygon in polygons {
				let path = CGMutablePath()
				for ring in [polygon.coordinates] + polygon.interiorRings where ring.count >= 3 {
					path.addLines(between: ring.map { SpatialTextureRenderer.canvasPoint($0, frame: frame, size: size) })
					path.closeSubpath()
				}
				guard !path.isEmpty else { continue }
				context.addPath(path)
				context.fillPath(using: .evenOdd)
			}
		}

		let lines = Dictionary(grouping: shapes.polylines, by: \.role)
		var paths: [OfflineFeatureRole: CGPath] = [:]
		func path(_ role: OfflineFeatureRole) -> CGPath? {
			if let cached = paths[role] { return cached }
			guard let roleLines = lines[role] else { return nil }
			let path = CGMutablePath()
			for line in roleLines where line.coordinates.count >= 2 {
				path.addLines(between: line.coordinates.map { SpatialTextureRenderer.canvasPoint($0, frame: frame, size: size) })
			}
			paths[role] = path
			return path
		}
		context.setLineJoin(.round)
		for stroke in strokes(dark: dark) {
			guard let path = path(stroke.role), !path.isEmpty else { continue }
			context.setStrokeColor(stroke.color.cgColor)
			context.setLineWidth(stroke.width)
			context.setLineCap(stroke.cap)
			context.setLineDash(phase: 0, lengths: stroke.dash)
			context.addPath(path)
			context.strokePath()
		}
		context.setLineDash(phase: 0, lengths: [])
	}
}
