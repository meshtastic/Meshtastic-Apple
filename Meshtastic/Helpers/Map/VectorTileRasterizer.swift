//
//  VectorTileRasterizer.swift
//  Meshtastic
//
//  Renders the vector tiles inside a Protomaps `.pmtiles` to raster PNGs on the fly, so
//  MapKit's `MKTileOverlay` can show an offline Protomaps basemap without MapLibre.
//
//  Decoding uses Outdooractive's mvt-tools (MVTTools + GISTools); drawing is Core Graphics.
//  `.noSRID` keeps coordinates in tile space (0...4096), so no Mercator math is needed.
//
//  Scope: geometry styled by layer + `kind` property (earth / water / landcover / landuse /
//  buildings / roads by class / boundaries / transit). No labels/fonts/symbols yet — those
//  are a separate (large) effort; the result is a clean, plain basemap.
//
//  Requires the SPM packages `mvt-tools` (product MVTTools) and `gis-tools` (product GISTools).
//

import CoreGraphics
import Foundation
import GISTools
import MVTTools
import UIKit

enum VectorTileRasterizer {

	/// mvt-tools `.noSRID` tiles use a 0...4096 coordinate space.
	private static let extent: CGFloat = 4096

	/// Rendered tiles are cached so panning doesn't re-decode/re-render the same tile.
	private static let cache: NSCache<NSString, NSData> = {
		let cache = NSCache<NSString, NSData>()
		cache.countLimit = 512
		return cache
	}()

	/// Renders one MVT tile (already decompressed by the PMTiles/MBTiles reader) to PNG data.
	static func png(mvt: Data, z: Int, x: Int, y: Int, pixels: CGFloat = 512) -> Data? {
		let key = "\(z)/\(x)/\(y)" as NSString
		if let cached = cache.object(forKey: key) { return cached as Data }

		guard let tile = VectorTile(data: mvt, x: x, y: y, z: z, projection: .noSRID) else { return nil }

		let scale = pixels / extent
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = true
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format)

		let data = renderer.pngData { context in
			let cg = context.cgContext
			cg.setFillColor(Style.earth.cgColor)
			cg.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))

			for layerName in Style.drawOrder {
				for feature in tile.features(for: layerName) {
					guard let style = Style.style(layer: layerName, properties: feature.properties) else { continue }
					draw(feature.geometry, style: style, scale: scale, in: cg)
				}
			}
		}

		cache.setObject(data as NSData, forKey: key)
		return data
	}

	// MARK: - Drawing

	private static func draw(_ geometry: GeoJsonGeometry, style: LayerStyle, scale: CGFloat, in cg: CGContext) {
		switch geometry {
		case let polygon as Polygon:
			fill(rings: polygon.rings.map(\.coordinates), style: style, scale: scale, in: cg)
		case let multi as MultiPolygon:
			for polygon in multi.polygons { fill(rings: polygon.rings.map(\.coordinates), style: style, scale: scale, in: cg) }
		case let line as LineString:
			stroke(lines: [line.coordinates], style: style, scale: scale, in: cg)
		case let multi as MultiLineString:
			stroke(lines: multi.lineStrings.map(\.coordinates), style: style, scale: scale, in: cg)
		default:
			break // points → labels, not drawn here
		}
	}

	private static func fill(rings: [[Coordinate3D]], style: LayerStyle, scale: CGFloat, in cg: CGContext) {
		guard let color = style.fill else { return }
		let path = CGMutablePath()
		for ring in rings where ring.count > 1 {
			path.move(to: CGPoint(x: ring[0].x * scale, y: ring[0].y * scale))
			for coordinate in ring.dropFirst() { path.addLine(to: CGPoint(x: coordinate.x * scale, y: coordinate.y * scale)) }
			path.closeSubpath()
		}
		cg.addPath(path)
		cg.setFillColor(color.cgColor)
		cg.fillPath(using: .evenOdd) // exterior + holes
	}

	private static func stroke(lines: [[Coordinate3D]], style: LayerStyle, scale: CGFloat, in cg: CGContext) {
		guard let color = style.stroke else { return }
		let path = CGMutablePath()
		for line in lines where line.count > 1 {
			path.move(to: CGPoint(x: line[0].x * scale, y: line[0].y * scale))
			for coordinate in line.dropFirst() { path.addLine(to: CGPoint(x: coordinate.x * scale, y: coordinate.y * scale)) }
		}
		cg.addPath(path)
		cg.setStrokeColor(color.cgColor)
		cg.setLineWidth(style.lineWidth)
		cg.setLineJoin(.round)
		cg.setLineCap(.round)
		cg.setLineDash(phase: 0, lengths: style.dash ?? [])
		cg.strokePath()
	}
}

// MARK: - Protomaps-ish style (layer + `kind`)

private struct LayerStyle {
	var fill: UIColor?
	var stroke: UIColor?
	var lineWidth: CGFloat = 1
	var dash: [CGFloat]?
}

private enum Style {
	static let earth = UIColor(red: 0.92, green: 0.91, blue: 0.88, alpha: 1)
	private static let water = UIColor(red: 0.61, green: 0.75, blue: 0.91, alpha: 1)
	private static let building = UIColor(red: 0.85, green: 0.83, blue: 0.79, alpha: 1)
	private static let park = UIColor(red: 0.78, green: 0.87, blue: 0.74, alpha: 1)
	private static let green = UIColor(red: 0.85, green: 0.89, blue: 0.81, alpha: 1)
	private static let neutralLand = UIColor(red: 0.90, green: 0.90, blue: 0.86, alpha: 1)
	private static let road = UIColor(white: 1.0, alpha: 1.0)
	private static let majorRoad = UIColor(red: 0.97, green: 0.86, blue: 0.62, alpha: 1)
	private static let path = UIColor(white: 0.72, alpha: 1.0)
	private static let rail = UIColor(white: 0.6, alpha: 1.0)
	private static let boundary = UIColor(red: 0.6, green: 0.55, blue: 0.66, alpha: 0.9)

	/// Painter's order — earlier draws underneath.
	static let drawOrder = ["earth", "landcover", "landuse", "water", "buildings", "roads", "transit", "boundaries"]

	static func style(layer: String, properties: [String: Sendable]) -> LayerStyle? {
		let kind = (properties["kind"] as? String) ?? (properties["pmap:kind"] as? String)
		switch layer {
		case "earth":
			return LayerStyle(fill: earth)
		case "water":
			return LayerStyle(fill: water)
		case "buildings":
			return LayerStyle(fill: building)
		case "landcover":
			return LayerStyle(fill: kind == "forest" || kind == "wood" || kind == "grass" ? green : green)
		case "landuse":
			let isPark = ["park", "garden", "recreation_ground", "pitch", "golf_course", "cemetery", "forest", "wood", "grass", "meadow"].contains(kind ?? "")
			return LayerStyle(fill: isPark ? park : neutralLand)
		case "roads":
			return roadStyle(kind: kind)
		case "transit":
			return LayerStyle(stroke: rail, lineWidth: 0.7, dash: [3, 3])
		case "boundaries":
			return LayerStyle(stroke: boundary, lineWidth: 0.8, dash: [4, 2])
		default:
			return nil // places / pois / other label layers
		}
	}

	private static func roadStyle(kind: String?) -> LayerStyle {
		switch kind {
		case "highway", "motorway", "freeway":
			return LayerStyle(stroke: majorRoad, lineWidth: 2.6)
		case "major_road", "trunk", "primary":
			return LayerStyle(stroke: majorRoad, lineWidth: 2.0)
		case "medium_road", "secondary", "tertiary":
			return LayerStyle(stroke: road, lineWidth: 1.5)
		case "path", "footway", "cycleway", "track":
			return LayerStyle(stroke: path, lineWidth: 0.7, dash: [2, 2])
		case "rail":
			return LayerStyle(stroke: rail, lineWidth: 0.8, dash: [4, 2])
		default: // minor_road, residential, service, unknown
			return LayerStyle(stroke: road, lineWidth: 1.0)
		}
	}
}
