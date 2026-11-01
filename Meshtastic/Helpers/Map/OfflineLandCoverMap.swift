//
//  OfflineLandCoverMap.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import CoreGraphics
import CoreLocation
import Foundation
import OSLog
import simd

/// The downloaded basemap's land cover over a box, painted into a grid of classes so a point's
/// cover is one lookup. The fire lookout colors the terrain out its windows from it.
struct OfflineLandCoverMap: Sendable {
	let bounds: GeoBounds
	let width: Int
	let height: Int
	/// Row-major, row 0 at the north edge; 0 where nothing is known.
	let classes: [UInt8]

	/// Grid cells per side. Over the lookout's 90 km a cell is about 90 m: past the first ring of
	/// hills the cover reads at least that coarse anyway.
	static let size = 2048

	/// The cover at a point, nil outside the box or where the basemap says nothing.
	func cover(latitude: Double, longitude: Double) -> OfflineLandCover? {
		let column = Int(((longitude - bounds.minLon) / (bounds.maxLon - bounds.minLon) * Double(width)).rounded(.down))
		let row = Int(((bounds.maxLat - latitude) / (bounds.maxLat - bounds.minLat) * Double(height)).rounded(.down))
		guard (0..<width).contains(column), (0..<height).contains(row) else { return nil }
		return OfflineLandCover(rawValue: classes[row * width + column])
	}

	/// Paints areas in order, later ones over earlier ones, without anti-aliasing so every cell holds
	/// exactly one class.
	static func paint(_ areas: [OfflineLandArea], bounds: GeoBounds, size: Int = size) -> OfflineLandCoverMap? {
		guard size > 0, bounds.maxLon > bounds.minLon, bounds.maxLat > bounds.minLat,
			  let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
									  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
		context.setShouldAntialias(false)
		context.setFillColor(gray: 0, alpha: 1)
		context.fill(CGRect(x: 0, y: 0, width: size, height: size))
		// The context's y runs up, so the north edge is at the top of the image.
		func point(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
			CGPoint(x: (coordinate.longitude - bounds.minLon) / (bounds.maxLon - bounds.minLon) * Double(size),
					y: (coordinate.latitude - bounds.minLat) / (bounds.maxLat - bounds.minLat) * Double(size))
		}
		for area in areas {
			let path = CGMutablePath()
			for ring in area.rings where ring.count >= 3 {
				path.addLines(between: ring.map(point))
				path.closeSubpath()
			}
			context.setFillColor(gray: CGFloat(area.cover.rawValue) / 255, alpha: 1)
			context.addPath(path)
			context.fillPath(using: .evenOdd)
		}
		guard let data = context.data else { return nil }
		let classes = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: size * size))
		return OfflineLandCoverMap(bounds: bounds, width: size, height: size, classes: classes)
	}

	/// The land cover within `radius` meters of `center` from the downloaded basemaps: the broad
	/// `landcover` classes (the basemap carries them to zoom 7), then the finer `landuse` areas and
	/// the water over them. Nil when no basemap reaches the box.
	static func make(center: CLLocationCoordinate2D, radius: Double, files: [OfflineMapRegionFile]) -> OfflineLandCoverMap? {
		let latitudeSpan = radius / SpatialFrame.metersPerDegreeLatitude
		let longitudeSpan = latitudeSpan / max(0.01, cos(center.latitude * .pi / 180))
		let bounds = GeoBounds(minLon: center.longitude - longitudeSpan, minLat: center.latitude - latitudeSpan,
							   maxLon: center.longitude + longitudeSpan, maxLat: center.latitude + latitudeSpan)
		var broad: [OfflineLandArea] = []
		var fine: [OfflineLandArea] = []
		for file in files where file.region.hasBasemap && file.region.bounds.intersects(bounds) {
			if Task.isCancelled { return nil }
			guard let source = OfflineTileSourceFactory.source(for: file.url), source.isVectorTiles else { continue }
			let minZoom = Int(source.tileMinZoom), maxZoom = Int(source.tileMaxZoom)
			let coverZoom = min(max(7, minZoom), maxZoom)
			for tile in tiles(bounds: bounds, zoom: coverZoom) {
				broad += OfflineVectorTileProvider.landCover(tile: tile, source: source, layers: ["landcover"])
			}
			// The deepest zoom up to 11 whose tiles over the box stay few enough to decode quickly.
			var fineZoom = min(11, maxZoom)
			while fineZoom > max(8, minZoom), tiles(bounds: bounds, zoom: fineZoom).count > maxFineTiles { fineZoom -= 1 }
			for tile in tiles(bounds: bounds, zoom: fineZoom) {
				if Task.isCancelled { return nil }
				fine += OfflineVectorTileProvider.landCover(tile: tile, source: source, layers: ["landuse", "water"])
			}
		}
		guard !broad.isEmpty || !fine.isEmpty else { return nil }
		// Water last, over every land class.
		let ordered = broad + fine.filter { $0.cover != .water } + fine.filter { $0.cover == .water }
		Logger.services.info("🎬 [Cinema] Lookout land cover: \(broad.count, privacy: .public) broad and \(fine.count, privacy: .public) fine areas")
		return paint(ordered, bounds: bounds)
	}

	/// Most tiles decoded for the fine layers.
	static let maxFineTiles = 64

	static func tiles(bounds: GeoBounds, zoom: Int) -> [OfflineVectorTileProvider.TileID] {
		let (x0, y0) = PMTilesExtractor.tileXY(lon: bounds.minLon, lat: bounds.maxLat, z: zoom)
		let (x1, y1) = PMTilesExtractor.tileXY(lon: bounds.maxLon, lat: bounds.minLat, z: zoom)
		var result: [OfflineVectorTileProvider.TileID] = []
		for x in Int(min(x0, x1))...Int(max(x0, x1)) {
			for y in Int(min(y0, y1))...Int(max(y0, y1)) {
				result.append(.init(z: zoom, x: x, y: y))
			}
		}
		return result
	}
}

/// The color of the ground out the fire lookout's windows, before light and haze.
enum LookoutGroundColor {
	static let forest = SIMD3<Double>(0.16, 0.26, 0.15)
	static let grass = SIMD3<Double>(0.40, 0.48, 0.27)
	static let farmland = SIMD3<Double>(0.52, 0.53, 0.33)
	static let scrub = SIMD3<Double>(0.36, 0.40, 0.25)
	static let barren = SIMD3<Double>(0.52, 0.48, 0.42)
	static let snow = SIMD3<Double>(0.90, 0.92, 0.95)
	static let urban = SIMD3<Double>(0.48, 0.47, 0.46)
	static let water = SIMD3<Double>(0.22, 0.33, 0.45)
	/// Mown grass and trees: a little brighter than grassland.
	static let park = SIMD3<Double>(0.30, 0.44, 0.22)
	static let rock = SIMD3<Double>(0.46, 0.40, 0.34)

	/// Roughly where snow lies through summer, in meters: about 2,100 m at 47°, higher toward the
	/// equator.
	static func snowLine(latitude: Double) -> Double {
		max(0, 5_000 - 62 * abs(latitude))
	}

	/// The ground's color: its land cover where the basemap has one, else by height within the view
	/// (`heightFraction`, 0 at the lowest point, 1 at the highest), as before land cover was read.
	/// Above the snow line, land fades to snow over 400 m; water never does.
	static func color(cover: OfflineLandCover?, elevation: Double, latitude: Double, heightFraction t: Double) -> SIMD3<Double> {
		var color: SIMD3<Double>
		switch cover {
		case .forest: color = forest
		case .grass: color = grass
		case .farmland: color = farmland
		case .scrub: color = scrub
		case .barren: color = barren
		case .glacier: return snow
		case .urban: color = urban
		case .park: color = park
		case .water: return water
		case nil:
			if elevation <= 0.5 { return water }
			if t < 0.55 { return forest }
			if t < 0.8 { return simd_mix(forest, rock, SIMD3(repeating: (t - 0.55) / 0.25)) }
			return simd_mix(rock, snow, SIMD3(repeating: min(1, (t - 0.8) / 0.15)))
		}
		let snowed = min(1, max(0, (elevation - snowLine(latitude: latitude)) / 400))
		return simd_mix(color, snow, SIMD3(repeating: snowed))
	}
}
