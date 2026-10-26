//
//  CoverageGeoJSON.swift
//  Meshtastic
//
//  Turns a coverage grid into filled signal bands as simplestyle GeoJSON, the
//  shape the hosted Site Planner exports and the map overlay already draws.
//

import Foundation

extension SitePlannerColorScale {
	/// Evenly spaced anchors sampled from the planner's 256-entry colormaps
	/// (meshtastic-site-planner `src/render/colormaps.ts`), interpolated between.
	var anchors: [UInt32] {
		switch self {
		case .mesh: return [0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759]
		case .plasma: return [0x0D0887, 0x6A00A8, 0xB12A90, 0xE16462, 0xFCA636, 0xF0F921]
		case .viridis: return [0x440154, 0x414487, 0x2A788E, 0x22A884, 0x7AD151, 0xFDE725]
		case .cmrmap: return [0x000000, 0x3B2277, 0xA1417F, 0xE1663A, 0xE6AE3E, 0xD7D7A0, 0xFFFFFF]
		case .cool: return [0x00FFFF, 0xFF00FF]
		case .turbo: return [0x30123B, 0x4145AB, 0x4675ED, 0x39A2FC, 0x1BCFD4, 0x62FC6B, 0xD2E935, 0xFDA007, 0xF05B12, 0x7A0403]
		case .jet: return [0x000080, 0x0000FF, 0x00FFFF, 0x7FFF7F, 0xFFFF00, 0xFF0000, 0x800000]
		}
	}

	/// The ramp sampled at `t` in 0...1, as `#rrggbb`.
	func color(at t: Double) -> String {
		let stops = anchors
		guard stops.count > 1 else { return Self.hex(stops.first ?? 0) }
		let position = min(max(t, 0), 1) * Double(stops.count - 1)
		let lower = min(Int(position), stops.count - 2)
		let fraction = position - Double(lower)
		func channel(_ color: UInt32, _ shift: UInt32) -> Double { Double((color >> shift) & 0xFF) }
		var mixed: UInt32 = 0
		for shift: UInt32 in [16, 8, 0] {
			let value = channel(stops[lower], shift) + (channel(stops[lower + 1], shift) - channel(stops[lower], shift)) * fraction
			mixed |= UInt32(value.rounded()) << shift
		}
		return Self.hex(mixed)
	}

	private static func hex(_ color: UInt32) -> String {
		String(format: "#%06x", color & 0xFFFFFF)
	}
}

/// How a coverage grid is drawn. `minDBm` and `maxDBm` fix the ends of the ramp, so two sites compare.
struct CoverageStyle {
	var colorScale: SitePlannerColorScale = .mesh
	var minDBm: Double = -130
	var maxDBm: Double = -80
	var opacity: Double = 0.5
	var bandCount = 6
}

extension CoverageGrid {
	/// The coverage as non-overlapping signal bands, one MultiPolygon feature per band, traced as smooth
	/// outlines (CoverageBands.swift). The strongest band is open-ended so a sample above `maxDBm` still draws.
	func geoJSON(style: CoverageStyle) -> String {
		let step = (style.maxDBm - style.minDBm) / Double(style.bandCount)
		let floors = (0..<style.bandCount).map { style.minDBm + step * Double($0) }
		let bands = bandPolygons(floors: floors)
		var features: [[String: Any]] = []
		for (index, lower) in floors.enumerated() {
			let polygons = bands[index]
			guard !polygons.isEmpty else { continue }
			// Spread across the band index, not its floor, so the ramp's brightest end appears.
			let color = style.colorScale.color(at: Double(index) / Double(max(style.bandCount - 1, 1)))
			let label = "≥ \(Self.oneDecimal(lower)) dBm"
			features.append([
				"type": "Feature",
				"geometry": ["type": "MultiPolygon", "coordinates": polygons.map { $0.map(Self.shortPositions) }],
				"properties": [
					"title": label,
					"label": label,
					"dbm": (lower * 10).rounded() / 10,
					"fill": color,
					"fill-opacity": style.opacity,
					"color": color,
					"stroke": color,
					"stroke-opacity": 0,
					"stroke-width": 0
				] as [String: Any]
			])
		}
		let collection: [String: Any] = [
			"type": "FeatureCollection",
			"properties": [
				"generator": "meshtastic-kp1812",
				"name": site.name,
				"model": "ITU-R P.1812",
				"palette": style.colorScale.rawValue,
				"min_dbm": style.minDBm,
				"max_dbm": style.maxDBm
			] as [String: Any],
			"features": features
		]
		guard let data = try? JSONSerialization.data(withJSONObject: collection, options: [.sortedKeys]),
			  let text = String(data: data, encoding: .utf8) else { return "{\"type\":\"FeatureCollection\",\"features\":[]}" }
		return text
	}

	/// A ring's positions to a millionth of a degree (about 0.1 m). Decimal numbers serialize without the
	/// 17-digit tails a Double can pick up.
	private static func shortPositions(_ ring: Ring) -> [[NSDecimalNumber]] {
		ring.map { position in
			position.map { value in
				let scaled = (value * 1_000_000).rounded()
				return NSDecimalNumber(mantissa: UInt64(abs(scaled)), exponent: -6, isNegative: scaled < 0)
			}
		}
	}

	private static func oneDecimal(_ value: Double) -> String {
		String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
	}
}
