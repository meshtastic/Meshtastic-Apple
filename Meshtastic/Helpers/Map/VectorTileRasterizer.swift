//
//  VectorTileRasterizer.swift
//  Meshtastic
//
//  A tiny, dependency-free Mapbox Vector Tile (MVT) decoder + Core Graphics renderer.
//  It turns the vector tiles inside a Protomaps `.pmtiles` into raster PNGs on the fly,
//  so MapKit's `MKTileOverlay` can display an offline Protomaps basemap without MapLibre.
//
//  Scope: geometry only (earth / water / landuse / buildings / roads / boundaries) styled
//  by layer name. No labels, fonts, or symbols — those are the hard 80% of a real renderer
//  and aren't attempted here. The result is a clean, plain basemap.
//

import CoreGraphics
import Foundation
import UIKit

// MARK: - Decoded model

private struct VectorTileFeature {
	enum GeometryType: Int { case unknown = 0, point = 1, line = 2, polygon = 3 }
	let type: GeometryType
	/// Rings (polygons) or paths (lines) in tile-local units (0...extent).
	let paths: [[CGPoint]]
}

private struct VectorTileLayer {
	let name: String
	let extent: Int
	let features: [VectorTileFeature]
}

// MARK: - Rasterizer

enum VectorTileRasterizer {

	/// Rendered tiles are cached so panning doesn't re-decode/re-render the same tile.
	private static let cache: NSCache<NSString, NSData> = {
		let cache = NSCache<NSString, NSData>()
		cache.countLimit = 512
		return cache
	}()

	/// Renders one decoded MVT tile to PNG data, or nil if it can't be drawn.
	/// `mvt` must already be decompressed (the PMTiles/MBTiles readers gunzip it).
	static func png(mvt: Data, z: Int, x: Int, y: Int, pixels: CGFloat = 512) -> Data? {
		let key = "\(z)/\(x)/\(y)" as NSString
		if let cached = cache.object(forKey: key) { return cached as Data }

		let layers = decode(mvt)
		guard !layers.isEmpty else { return nil }

		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = true
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format)

		let data = renderer.pngData { context in
			let cg = context.cgContext
			// Base land color so gaps between polygons aren't white.
			cg.setFillColor(Style.earthFill.cgColor)
			cg.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))

			let byName = Dictionary(grouping: layers, by: { $0.name })
			for entry in Style.drawOrder {
				guard let style = Style.layers[entry] else { continue }
				for layer in byName[entry] ?? [] {
					let scale = pixels / CGFloat(layer.extent == 0 ? 4096 : layer.extent)
					draw(layer, style: style, scale: scale, in: cg)
				}
			}
		}

		cache.setObject(data as NSData, forKey: key)
		return data
	}

	// MARK: Drawing

	private static func draw(_ layer: VectorTileLayer, style: LayerStyle, scale: CGFloat, in cg: CGContext) {
		for feature in layer.features where !feature.paths.isEmpty {
			let path = CGMutablePath()
			for ring in feature.paths where ring.count > 1 {
				path.move(to: CGPoint(x: ring[0].x * scale, y: ring[0].y * scale))
				for point in ring.dropFirst() {
					path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
				}
				if feature.type == .polygon { path.closeSubpath() }
			}

			cg.addPath(path)
			if feature.type == .polygon, let fill = style.fill {
				cg.setFillColor(fill.cgColor)
				cg.fillPath(using: .evenOdd) // handles holes well enough for a basemap
			} else if let stroke = style.stroke {
				cg.setStrokeColor(stroke.cgColor)
				cg.setLineWidth(style.lineWidth)
				cg.setLineJoin(.round)
				cg.setLineCap(.round)
				if let dash = style.dash { cg.setLineDash(phase: 0, lengths: dash) } else { cg.setLineDash(phase: 0, lengths: []) }
				cg.strokePath()
			} else {
				cg.beginPath() // clear unused path
			}
		}
	}

	// MARK: - MVT protobuf decode

	private static func decode(_ data: Data) -> [VectorTileLayer] {
		var reader = ProtoReader(data)
		var layers: [VectorTileLayer] = []
		while let field = reader.nextField() {
			if field.number == 3, field.wireType == 2, let bytes = reader.lengthDelimited() {
				if let layer = decodeLayer(bytes) { layers.append(layer) }
			} else {
				reader.skip(field.wireType)
			}
		}
		return layers
	}

	private static func decodeLayer(_ data: Data) -> VectorTileLayer? {
		var reader = ProtoReader(data)
		var name = ""
		var extent = 4096
		var features: [VectorTileFeature] = []
		while let field = reader.nextField() {
			switch (field.number, field.wireType) {
			case (1, 2): name = reader.string() ?? name
			case (5, 0): extent = Int(reader.varint())
			case (2, 2): if let bytes = reader.lengthDelimited(), let feature = decodeFeature(bytes) { features.append(feature) }
			default: reader.skip(field.wireType)
			}
		}
		return name.isEmpty ? nil : VectorTileLayer(name: name, extent: extent, features: features)
	}

	private static func decodeFeature(_ data: Data) -> VectorTileFeature? {
		var reader = ProtoReader(data)
		var type = VectorTileFeature.GeometryType.unknown
		var geometry: [UInt32] = []
		while let field = reader.nextField() {
			switch (field.number, field.wireType) {
			case (3, 0): type = VectorTileFeature.GeometryType(rawValue: Int(reader.varint())) ?? .unknown
			case (4, 2): geometry = reader.packedVarints()
			default: reader.skip(field.wireType)
			}
		}
		guard !geometry.isEmpty else { return nil }
		return VectorTileFeature(type: type, paths: decodeGeometry(geometry, isPolygon: type == .polygon))
	}

	/// Decodes MVT command/parameter integers into rings/paths of points (tile units).
	private static func decodeGeometry(_ commands: [UInt32], isPolygon: Bool) -> [[CGPoint]] {
		var paths: [[CGPoint]] = []
		var current: [CGPoint] = []
		var x = 0, y = 0
		var index = 0
		while index < commands.count {
			let command = commands[index] & 0x7
			let count = Int(commands[index] >> 3)
			index += 1
			switch command {
			case 1: // MoveTo — starts a new path/ring
				for _ in 0..<count where index + 1 < commands.count {
					if !current.isEmpty { paths.append(current); current = [] }
					x += zigzag(commands[index]); y += zigzag(commands[index + 1]); index += 2
					current.append(CGPoint(x: x, y: y))
				}
			case 2: // LineTo
				for _ in 0..<count where index + 1 < commands.count {
					x += zigzag(commands[index]); y += zigzag(commands[index + 1]); index += 2
					current.append(CGPoint(x: x, y: y))
				}
			case 7: // ClosePath
				if isPolygon, let first = current.first { current.append(first) }
			default:
				index = commands.count
			}
		}
		if !current.isEmpty { paths.append(current) }
		return paths
	}

	private static func zigzag(_ value: UInt32) -> Int { Int(Int32(bitPattern: (value >> 1) ^ (~(value & 1) &+ 1))) }
}

// MARK: - Protomaps-ish style

private struct LayerStyle {
	var fill: UIColor?
	var stroke: UIColor?
	var lineWidth: CGFloat = 1
	var dash: [CGFloat]?
}

private enum Style {
	static let earthFill = UIColor(red: 0.92, green: 0.91, blue: 0.88, alpha: 1)

	/// Painter's order — earlier entries draw first (underneath).
	static let drawOrder = ["earth", "landcover", "landuse", "water", "buildings", "roads", "transit", "boundaries"]

	static let layers: [String: LayerStyle] = [
		"earth": LayerStyle(fill: earthFill),
		"landcover": LayerStyle(fill: UIColor(red: 0.85, green: 0.89, blue: 0.82, alpha: 1)),
		"landuse": LayerStyle(fill: UIColor(red: 0.88, green: 0.91, blue: 0.85, alpha: 1)),
		"water": LayerStyle(fill: UIColor(red: 0.61, green: 0.75, blue: 0.91, alpha: 1)),
		"buildings": LayerStyle(fill: UIColor(red: 0.85, green: 0.83, blue: 0.79, alpha: 1)),
		"roads": LayerStyle(stroke: UIColor(white: 1.0, alpha: 1.0), lineWidth: 1.5),
		"transit": LayerStyle(stroke: UIColor(white: 0.7, alpha: 1.0), lineWidth: 0.8, dash: [3, 3]),
		"boundaries": LayerStyle(stroke: UIColor(red: 0.6, green: 0.55, blue: 0.66, alpha: 0.9), lineWidth: 0.8, dash: [4, 2])
	]
}

// MARK: - Minimal protobuf wire reader

private struct ProtoReader {
	private let bytes: [UInt8]
	private var pos = 0

	init(_ data: Data) { bytes = [UInt8](data) }

	struct Field { let number: Int; let wireType: Int }

	mutating func nextField() -> Field? {
		guard pos < bytes.count else { return nil }
		let key = varint()
		return Field(number: Int(key >> 3), wireType: Int(key & 0x7))
	}

	mutating func varint() -> UInt64 {
		var result: UInt64 = 0
		var shift: UInt64 = 0
		while pos < bytes.count {
			let byte = bytes[pos]; pos += 1
			result |= UInt64(byte & 0x7F) << shift
			if byte & 0x80 == 0 { break }
			shift += 7
		}
		return result
	}

	mutating func lengthDelimited() -> Data? {
		let length = Int(varint())
		guard length >= 0, pos + length <= bytes.count else { pos = bytes.count; return nil }
		let slice = Data(bytes[pos..<(pos + length)])
		pos += length
		return slice
	}

	mutating func string() -> String? {
		guard let data = lengthDelimited() else { return nil }
		return String(data: data, encoding: .utf8)
	}

	/// Reads a packed repeated uint32 field (the geometry command stream).
	mutating func packedVarints() -> [UInt32] {
		let length = Int(varint())
		guard length >= 0, pos + length <= bytes.count else { pos = bytes.count; return [] }
		let end = pos + length
		var values: [UInt32] = []
		values.reserveCapacity(length)
		while pos < end {
			var result: UInt32 = 0
			var shift: UInt32 = 0
			while pos < end {
				let byte = bytes[pos]; pos += 1
				result |= UInt32(byte & 0x7F) << shift
				if byte & 0x80 == 0 { break }
				shift += 7
			}
			values.append(result)
		}
		return values
	}

	mutating func skip(_ wireType: Int) {
		switch wireType {
		case 0: _ = varint()
		case 1: pos += 8
		case 2: let length = Int(varint()); pos = min(bytes.count, pos + length)
		case 5: pos += 4
		default: pos = bytes.count
		}
	}
}
