//
//  SpatialTerrainContours.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import CoreGraphics
import CoreLocation
import UIKit

/// Contour lines for the spatial map texture, generated from the downloaded terrain with the same
/// marching squares as the 2D map and stroked in the 2D map's colors.
enum SpatialTerrainContours {

	/// The contour lines of one elevation tile, as map coordinates. `clip` is the part of the box
	/// this tile owns (its bounds within the download), so lines that run into a neighbor's margin
	/// are not drawn twice.
	struct Tile: Sendable {
		let clip: GeoBounds
		let minor: [[CLLocationCoordinate2D]]
		let index: [[CLLocationCoordinate2D]]
	}

	/// Minor spacing → index spacing, finest first. Imperial values are round feet in meters.
	private static let metricLadder: [(minor: Double, index: Double)] = [
		(10, 50), (20, 100), (50, 250), (100, 500), (200, 1000), (500, 2500), (1000, 5000)
	]
	private static let imperialLadder: [(minor: Double, index: Double)] = [
		(20, 100), (40, 200), (100, 500), (200, 1000), (500, 2500), (1000, 5000), (2000, 10000)
	].map { ($0.0 * 0.3048, $0.1 * 0.3048) }

	/// The finest spacing that keeps the box's relief to at most `maxMinorLines` minor lines
	/// (about eight index lines), so steep ground stays readable on the texture.
	static func intervals(relief: Double, metric: Bool, maxMinorLines: Double = 40) -> ContourIntervals {
		let ladder = metric ? metricLadder : imperialLadder
		let step = ladder.first { relief / $0.minor <= maxMinorLines } ?? ladder[ladder.count - 1]
		return ContourIntervals(minor: step.minor, index: step.index)
	}

	/// Contours for the box from the downloaded terrain, read at a zoom where one tile is about
	/// 512 texels across, no finer than the data. Decoding tiles is most of the cost, and lines
	/// from one sample per two texels still read smoothly. Empty where nothing is downloaded.
	static func tiles(frame: SpatialFrame, width: Int, dataZoom: Int, intervals: ContourIntervals, source: any ElevationTileSource) async -> [Tile] {
		let bounds = frame.bounds
		let tileSize = TerrainStore.tileSize
		let lonSpan = max(bounds.maxLon - bounds.minLon, 1e-9)
		let wanted = Double(width) / Double(2 * tileSize) * 360 / lonSpan
		let zoom = min(max(Int(log2(wanted).rounded(.down)), 0), dataZoom)
		let northWest = TerrainStore.tilePixel(latitude: bounds.maxLat, longitude: bounds.minLon, z: zoom, size: tileSize)
		let southEast = TerrainStore.tilePixel(latitude: bounds.minLat, longitude: bounds.maxLon, z: zoom, size: tileSize)
		var result: [Tile] = []
		for y in northWest.y...southEast.y {
			for x in northWest.x...southEast.x {
				if Task.isCancelled { return [] }
				guard let coverage = await source.coverage(z: zoom, x: x, y: y),
					  let tile = await source.elevationTile(z: zoom, x: x, y: y, margin: 2) else { continue }
				let tileBounds = TerrainStore.tileBounds(z: zoom, x: x, y: y)
				let clip = GeoBounds(
					minLon: max(tileBounds.minLon, coverage.minLon), minLat: max(tileBounds.minLat, coverage.minLat),
					maxLon: min(tileBounds.maxLon, coverage.maxLon), maxLat: min(tileBounds.maxLat, coverage.maxLat)
				)
				guard clip.maxLon > clip.minLon, clip.maxLat > clip.minLat else { continue }
				var minor: [[CLLocationCoordinate2D]] = []
				var index: [[CLLocationCoordinate2D]] = []
				for line in ContourGenerator.contours(tile: tile, intervals: intervals) where line.points.count >= 2 {
					let coordinates = line.coordinates(z: zoom, x: x, y: y)
					if line.isIndex { index.append(coordinates) } else { minor.append(coordinates) }
				}
				if !minor.isEmpty || !index.isEmpty {
					result.append(Tile(clip: clip, minor: minor, index: index))
				}
			}
		}
		return result
	}

	/// Strokes the contours over the image: white over imagery, brown otherwise, index lines
	/// heavier, like the 2D map. Line widths scale with the image so they read the same at any size.
	static func draw(_ tiles: [Tile], over image: CGImage, frame: SpatialFrame, imagery: Bool) -> CGImage? {
		let width = image.width, height = image.height
		guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
									  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
		let size = CGSize(width: width, height: height)
		context.draw(image, in: CGRect(origin: .zero, size: size))
		let scale = CGFloat(max(width, height)) / 2048
		let minorColor = imagery ? UIColor.white.withAlphaComponent(0.55) : UIColor.brown.withAlphaComponent(0.45)
		let indexColor = imagery ? UIColor.white.withAlphaComponent(0.9) : UIColor.brown.withAlphaComponent(0.8)
		context.setLineJoin(.round)
		context.setLineCap(.round)
		// The slab's sides stretch the texture's edge pixels downward, so lines touching the edge
		// would turn into stripes there. Keep a thin border clear.
		let border = CGRect(origin: .zero, size: size).insetBy(dx: max(2, 4 * scale), dy: max(2, 4 * scale))
		for tile in tiles {
			let topLeft = SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: tile.clip.maxLat, longitude: tile.clip.minLon), frame: frame, size: size)
			let bottomRight = SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: tile.clip.minLat, longitude: tile.clip.maxLon), frame: frame, size: size)
			context.saveGState()
			context.clip(to: CGRect(x: topLeft.x, y: bottomRight.y, width: bottomRight.x - topLeft.x, height: topLeft.y - bottomRight.y).intersection(border))
			// One path per class, so crossings within a tile do not darken where the strokes overlap.
			for (lines, color, lineWidth) in [(tile.minor, minorColor, max(1, 1.5 * scale)), (tile.index, indexColor, max(2, 3 * scale))] where !lines.isEmpty {
				let path = CGMutablePath()
				for line in lines {
					path.addLines(between: line.map { SpatialTextureRenderer.canvasPoint($0, frame: frame, size: size) })
				}
				context.addPath(path)
				context.setStrokeColor(color.cgColor)
				context.setLineWidth(lineWidth)
				context.strokePath()
			}
			context.restoreGState()
		}
		return context.makeImage()
	}
}
