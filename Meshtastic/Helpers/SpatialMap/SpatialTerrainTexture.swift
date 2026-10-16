//
//  SpatialTerrainTexture.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreGraphics
import CoreLocation
import ImageIO
import MapKit
import OSLog
import UIKit

/// Draws the image draped over the terrain mesh: Apple's map of exactly the box when online,
/// otherwise the downloaded offline map (or just its water) under the hillshade. Both are Web
/// Mercator so the mesh's texture coordinates line up with either.
enum SpatialTextureRenderer {

	/// Pixel size for a box: the Mercator aspect ratio, longest edge `maxEdge`.
	static func pixelSize(for frame: SpatialFrame, maxEdge: Int) -> CGSize {
		let bounds = frame.bounds
		let lonFraction = (bounds.maxLon - bounds.minLon) / 360
		let latFraction = SpatialFrame.mercatorY(bounds.minLat) - SpatialFrame.mercatorY(bounds.maxLat)
		let aspect = max(lonFraction, 1e-9) / max(latFraction, 1e-9)
		let width = aspect >= 1 ? Double(maxEdge) : Double(maxEdge) * aspect
		let height = aspect >= 1 ? Double(maxEdge) / aspect : Double(maxEdge)
		return CGSize(width: max(64, width.rounded()), height: max(64, height.rounded()))
	}

	/// The map image of exactly the box, cropped out of a snapshot; nil offline or on failure.
	static func snapshot(frame: SpatialFrame, pixelSize: CGSize, layer: MapLayer, dark: Bool) async -> CGImage? {
		let bounds = frame.bounds
		let options = MKMapSnapshotter.Options()
		let northWest = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.minLon))
		let southEast = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.maxLon))
		options.mapRect = MKMapRect(x: northWest.x, y: northWest.y, width: southEast.x - northWest.x, height: southEast.y - northWest.y)
		// Half the points at 2x: labels and roads render at the size they do on a Retina screen.
		let displayScale: CGFloat = 2
		options.size = CGSize(width: pixelSize.width / displayScale, height: pixelSize.height / displayScale)
		options.traitCollection = UITraitCollection(traitsFrom: [
			UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
			UITraitCollection(displayScale: displayScale)
		])
		// Flat: a realistic elevation snapshot is a perspective render, no longer Mercator.
		switch layer {
		case .hybrid:
			let configuration = MKHybridMapConfiguration(elevationStyle: .flat)
			configuration.pointOfInterestFilter = .excludingAll
			options.preferredConfiguration = configuration
		case .satellite:
			options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
		case .standard, .offline:
			let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
			configuration.pointOfInterestFilter = .excludingAll
			options.preferredConfiguration = configuration
		}

		let snapshotter = MKMapSnapshotter(options: options)
		let snapshot: MKMapSnapshotter.Snapshot? = await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, error in
					if let error {
						Logger.services.info("🧊 [Spatial] Map snapshot failed: \(error.localizedDescription, privacy: .public)")
					}
					continuation.resume(returning: snapshot)
				}
			}
		} onCancel: {
			snapshotter.cancel()
		}
		guard let snapshot, let image = snapshot.image.cgImage else { return nil }
		// The snapshot can differ from the request by a pixel; crop to where the box really landed.
		let scale = snapshot.traitCollection.displayScale
		let nw = snapshot.point(for: CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.minLon))
		let se = snapshot.point(for: CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.maxLon))
		let crop = cropRect(northWest: nw, southEast: se, scale: scale, imageWidth: image.width, imageHeight: image.height)
		guard crop.width >= 16, crop.height >= 16 else { return image }
		return image.cropping(to: crop) ?? image
	}

	static func cropRect(northWest: CGPoint, southEast: CGPoint, scale: CGFloat, imageWidth: Int, imageHeight: Int) -> CGRect {
		let x0 = max(0, Int((min(northWest.x, southEast.x) * scale).rounded()))
		let y0 = max(0, Int((min(northWest.y, southEast.y) * scale).rounded()))
		let x1 = min(imageWidth, Int((max(northWest.x, southEast.x) * scale).rounded()))
		let y1 = min(imageHeight, Int((max(northWest.y, southEast.y) * scale).rounded()))
		return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
	}

	/// Where a coordinate lands on the texture: x from the longitude fraction, y from the Mercator
	/// fraction, measured from the bottom the way CoreGraphics does.
	static func canvasPoint(_ coordinate: CLLocationCoordinate2D, frame: SpatialFrame, size: CGSize) -> CGPoint {
		let fraction = frame.mercatorFraction(latitude: coordinate.latitude, longitude: coordinate.longitude)
		return CGPoint(x: fraction.x * size.width, y: (1 - fraction.y) * size.height)
	}

	/// Fills water bodies in the basemap's water color. Each polygon is filled on its own with the
	/// even-odd rule: its islands stay land, and neighbors that overlap in the tile buffers do not
	/// cancel each other out.
	static func drawWater(_ polygons: [OfflineMapPolygon], frame: SpatialFrame, size: CGSize, dark: Bool, in context: CGContext) {
		guard !polygons.isEmpty, let color = OfflineMapPalette.fill(.water, dark: dark) else { return }
		context.setFillColor(color.cgColor)
		for polygon in polygons {
			let path = CGMutablePath()
			for ring in [polygon.coordinates] + polygon.interiorRings where ring.count >= 3 {
				path.addLines(between: ring.map { canvasPoint($0, frame: frame, size: size) })
				path.closeSubpath()
			}
			guard !path.isEmpty else { continue }
			context.addPath(path)
			context.fillPath(using: .evenOdd)
		}
	}

	/// Water from the downloaded basemaps that cover the box, decoded at a zoom where one vector
	/// tile is a few hundred texels across. Empty when no basemap covers the box.
	static func offlineWater(frame: SpatialFrame, width: Int, files: [OfflineMapRegionFile] = OfflineMapManager.persistedRegionFiles()) -> [OfflineMapPolygon] {
		let bounds = frame.bounds
		let lonSpan = max(bounds.maxLon - bounds.minLon, 1e-9)
		var polygons: [OfflineMapPolygon] = []
		var tileCount = 0
		for file in files where file.region.hasBasemap && file.region.bounds.intersects(bounds) {
			guard let source = OfflineTileSourceFactory.source(for: file.url), source.isVectorTiles else { continue }
			let coverage = source.geographicBounds ?? file.region.bounds
			guard coverage.intersects(bounds) else { continue }
			// One vector tile per 256–512 texels across the box.
			let wanted = Double(width) / 256 * 360 / lonSpan
			let zoom = min(max(Int(log2(wanted).rounded(.down)), Int(source.tileMinZoom)), Int(source.tileMaxZoom))
			let northWest = TerrainStore.tilePixel(latitude: bounds.maxLat, longitude: bounds.minLon, z: zoom, size: 256)
			let southEast = TerrainStore.tilePixel(latitude: bounds.minLat, longitude: bounds.maxLon, z: zoom, size: 256)
			for y in northWest.y...southEast.y {
				for x in northWest.x...southEast.x {
					if Task.isCancelled { return [] }
					guard TerrainStore.tileBounds(z: zoom, x: x, y: y).intersects(coverage) else { continue }
					tileCount += 1
					polygons += OfflineVectorTileProvider.waterPolygons(tile: .init(z: zoom, x: x, y: y), source: source, clippedTo: bounds)
				}
			}
		}
		if tileCount > 0 {
			Logger.services.info("🧊 [Spatial] Offline water: \(polygons.count) polygons from \(tileCount) tiles")
		}
		return polygons
	}

	/// Flat land color, then the decoded offline map when there is one, else just the water from
	/// the downloaded basemaps, then the hillshade from the downloaded terrain. Nothing is fetched.
	static func offlineComposite(frame: SpatialFrame, pixelSize: CGSize, dark: Bool, basemap: SpatialOfflineMap.Shapes?, source: any ElevationTileSource) async -> CGImage? {
		let width = Int(pixelSize.width), height = Int(pixelSize.height)
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
									  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
		context.setFillColor(OfflineMapPalette.earth(dark: dark).cgColor)
		context.fill(CGRect(x: 0, y: 0, width: width, height: height))
		if let basemap {
			SpatialOfflineMap.draw(basemap, frame: frame, size: pixelSize, dark: dark, in: context)
		} else {
			drawWater(offlineWater(frame: frame, width: width), frame: frame, size: pixelSize, dark: dark, in: context)
		}
		if Task.isCancelled { return nil }

		let bounds = frame.bounds
		let tileSize = TerrainStore.tileSize
		// One hillshade tile per 256-512 texels across the box: shading a tile is the slow part of the
		// build, and the coarser zoom quarters the tile count with no visible loss on a one-meter model.
		let lonSpan = bounds.maxLon - bounds.minLon
		let wanted = Double(width) / Double(tileSize) * 360 / max(lonSpan, 1e-9)
		let zoom = min(max(Int(log2(wanted).rounded(.down)), 0), 16)
		let northWest = TerrainStore.tilePixel(latitude: bounds.maxLat, longitude: bounds.minLon, z: zoom, size: tileSize)
		let southEast = TerrainStore.tilePixel(latitude: bounds.minLat, longitude: bounds.maxLon, z: zoom, size: tileSize)
		let top = SpatialFrame.mercatorY(bounds.maxLat), bottom = SpatialFrame.mercatorY(bounds.minLat)
		let maxAlpha: CGFloat = dark ? 0.42 : 0.32

		for y in northWest.y...southEast.y {
			for x in northWest.x...southEast.x {
				if Task.isCancelled { return nil }
				guard let coverage = await source.coverage(z: zoom, x: x, y: y),
					  let tile = await source.elevationTile(z: zoom, x: x, y: y, margin: 2) else { continue }
				let path = MKTileOverlayPath(x: x, y: y, z: zoom, contentScaleFactor: 1)
				let clip = HillshadeTileOverlay.clipRect(tile: tile, path: path, coverage: coverage)
				let metersPerSample = TerrainStore.metersPerSample(z: zoom, y: y, size: tileSize)
				guard let png = HillshadeTileOverlay.renderShadow(tile: tile, metersPerSample: metersPerSample, maxAlpha: maxAlpha, clip: clip),
					  let imageSource = CGImageSourceCreateWithData(png as CFData, nil),
					  let shade = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { continue }
				let tileBounds = TerrainStore.tileBounds(z: zoom, x: x, y: y)
				// Pixel rect of the tile within the canvas; CoreGraphics measures y from the bottom.
				let left = (tileBounds.minLon - bounds.minLon) / lonSpan * Double(width)
				let right = (tileBounds.maxLon - bounds.minLon) / lonSpan * Double(width)
				let tileTop = (SpatialFrame.mercatorY(tileBounds.maxLat) - top) / (bottom - top) * Double(height)
				let tileBottom = (SpatialFrame.mercatorY(tileBounds.minLat) - top) / (bottom - top) * Double(height)
				let rect = CGRect(x: left, y: Double(height) - tileBottom, width: right - left, height: tileBottom - tileTop)
				context.draw(shade, in: rect)
			}
		}
		return context.makeImage()
	}
}
