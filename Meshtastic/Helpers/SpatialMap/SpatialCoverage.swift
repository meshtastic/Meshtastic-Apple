//
//  SpatialCoverage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import CoreGraphics
import CoreLocation
import Foundation
import SwiftUI
import UIKit

/// Which Site Planner estimates the spatial map drapes on the terrain.
enum SpatialCoverageMode: String, CaseIterable, Sendable {
	case off
	/// Only the selected node's estimate.
	case selected
	/// Every active estimate in the area.
	case all
}

/// One signal level of an estimate: its polygons in the planner's color for that level.
struct SpatialCoverageBand: Sendable {
	let dbm: Double?
	let label: String?
	/// Straight (not premultiplied) red, green, blue and alpha in 0...1.
	let rgba: SIMD4<Double>
	let polygons: [SpatialCoveragePolygon]
}

/// An outer ring and its holes, as longitude/latitude coordinates.
struct SpatialCoveragePolygon: Sendable {
	let outer: [CLLocationCoordinate2D]
	let holes: [[CLLocationCoordinate2D]]
}

/// A parsed Site Planner estimate, ready to draw.
struct SpatialCoverageEstimate: Sendable, Identifiable {
	/// The map data file's ID.
	let id: UUID
	let nodeNum: Int64?
	let transmitter: CLLocationCoordinate2D
	/// How far the planner computed coverage. Nil for files saved before it was recorded; those
	/// get no "no signal" shading since where the computation stopped is unknown.
	let rangeMeters: Double?
	let bounds: GeoBounds
	let created: Date
	/// Weakest first.
	let bands: [SpatialCoverageBand]
}

enum SpatialCoverageParser {
	/// The estimate in a Site Planner file, or nil when it has no polygons.
	static func estimate(collection: GeoJSONFeatureCollection, metadata: MapDataMetadata) -> SpatialCoverageEstimate? {
		var bands: [SpatialCoverageBand] = []
		for feature in collection.features {
			let polygons = polygons(feature.geometry)
			guard !polygons.isEmpty else { continue }
			let dbm: Double? = switch feature.properties?["dbm"] {
			case .double(let value): value
			case .int(let value): Double(value)
			default: nil
			}
			let label: String? = if case .string(let value) = feature.properties?["label"] { value } else { nil }
			bands.append(SpatialCoverageBand(dbm: dbm, label: label, rgba: rgba(css: feature.effectiveFillColor), polygons: polygons))
		}
		guard !bands.isEmpty else { return nil }
		bands.sort { ($0.dbm ?? -.infinity) < ($1.dbm ?? -.infinity) }

		let info = metadata.coverage
		let bounds = info?.bounds.map { GeoBounds(minLon: $0.minLongitude, minLat: $0.minLatitude, maxLon: $0.maxLongitude, maxLat: $0.maxLatitude) }
			?? extent(bands)
		let transmitter = info.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
			?? CLLocationCoordinate2D(latitude: (bounds.minLat + bounds.maxLat) / 2, longitude: (bounds.minLon + bounds.maxLon) / 2)
		return SpatialCoverageEstimate(
			id: metadata.id, nodeNum: info?.nodeNum, transmitter: transmitter,
			rangeMeters: info.map { $0.maxRangeKm * 1000 }, bounds: bounds, created: metadata.uploadDate, bands: bands
		)
	}

	/// Polygon and MultiPolygon geometry; anything else has no area to draw.
	static func polygons(_ geometry: GeoJSONGeometry) -> [SpatialCoveragePolygon] {
		func polygon(_ value: AnyCodableValue) -> SpatialCoveragePolygon? {
			guard case .array(let rings) = value else { return nil }
			let coordinates = rings.map { $0.toCoordinates() }
			guard let outer = coordinates.first, outer.count >= 3 else { return nil }
			return SpatialCoveragePolygon(outer: outer, holes: coordinates.dropFirst().filter { $0.count >= 3 })
		}
		switch geometry.type.lowercased() {
		case "polygon":
			return polygon(geometry.coordinates).map { [$0] } ?? []
		case "multipolygon":
			guard case .array(let items) = geometry.coordinates else { return [] }
			return items.compactMap(polygon)
		default:
			return []
		}
	}

	/// The feature's color the way the 2D map reads it.
	static func rgba(css: String) -> SIMD4<Double> {
		var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		UIColor(Color(css: css)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		return SIMD4(Double(red), Double(green), Double(blue), Double(alpha))
	}

	private static func extent(_ bands: [SpatialCoverageBand]) -> GeoBounds {
		var minLat = Double.infinity, maxLat = -Double.infinity, minLon = Double.infinity, maxLon = -Double.infinity
		for band in bands {
			for polygon in band.polygons {
				for c in polygon.outer {
					minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
					minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
				}
			}
		}
		return GeoBounds(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
	}
}

enum SpatialCoverageVisibility {
	/// The estimates to drape on an area: none when off, the selected node's in Selected, and every
	/// estimate that reaches the area in All. Estimates with no node only show in All.
	static func visible(_ all: [SpatialCoverageEstimate], mode: SpatialCoverageMode, selected: Int64?, box: GeoBounds) -> [SpatialCoverageEstimate] {
		switch mode {
		case .off:
			return []
		case .selected:
			guard let selected else { return [] }
			return all.filter { $0.nodeNum == selected && $0.bounds.intersects(box) }
		case .all:
			return all.filter { $0.bounds.intersects(box) }
		}
	}
}

struct SpatialCoverageLegendEntry: Equatable, Identifiable, Sendable {
	var id: Double { dbm }
	let dbm: Double
	let label: String
	let rgba: SIMD4<Double>
}

enum SpatialCoverageLegend {
	/// One entry per signal level across the estimates, strongest first. The colors come from the
	/// files themselves, since each run carries the palette it was made with.
	static func entries(_ estimates: [SpatialCoverageEstimate]) -> [SpatialCoverageLegendEntry] {
		var byLevel: [Double: SpatialCoverageLegendEntry] = [:]
		for estimate in estimates {
			for band in estimate.bands {
				guard let dbm = band.dbm, byLevel[dbm] == nil else { continue }
				let label = band.label ?? "≥ \(dbm.formatted(.number.precision(.fractionLength(0)))) dBm"
				byLevel[dbm] = SpatialCoverageLegendEntry(dbm: dbm, label: label, rgba: band.rgba)
			}
		}
		return byLevel.values.sorted { $0.dbm > $1.dbm }
	}
}

/// Draws the estimates into an image laid out like the terrain's map image, so the overlay can
/// use the terrain's own texture coordinates.
enum SpatialCoverageTexture {
	/// The "no signal" shade over the computed range, under the bands. Ground the planner found
	/// no signal for shows through as this dark tint, so a ridge reads as a hole in the color.
	static let shadow = SIMD4<Double>(0, 0, 0, 0.45)
	/// How much darker the outline of the weakest band is than its fill.
	static let outlineShade = 0.6

	/// A closed ring `radiusMeters` around `center`, flat-earth in the same frame the model uses.
	static func rangeRing(center: CLLocationCoordinate2D, radiusMeters: Double, segments: Int = 128) -> [CLLocationCoordinate2D] {
		let metersPerDegreeLongitude = SpatialFrame.metersPerDegreeLatitude * cos(center.latitude * .pi / 180)
		var ring: [CLLocationCoordinate2D] = []
		ring.reserveCapacity(segments + 1)
		for i in 0...segments {
			let angle = Double(i % segments) / Double(segments) * 2 * .pi
			ring.append(CLLocationCoordinate2D(
				latitude: center.latitude + radiusMeters * sin(angle) / SpatialFrame.metersPerDegreeLatitude,
				longitude: center.longitude + radiusMeters * cos(angle) / metersPerDegreeLongitude
			))
		}
		return ring
	}

	/// The overlay image: transparent except where an estimate reaches. Older estimates first, so
	/// the newest is on top where two overlap. Nil when there is nothing to draw.
	static func render(_ estimates: [SpatialCoverageEstimate], frame: SpatialFrame, size: CGSize) -> CGImage? {
		guard !estimates.isEmpty else { return nil }
		let width = Int(size.width), height = Int(size.height)
		guard width > 0, height > 0,
			  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
									  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
		let scale = CGFloat(max(width, height)) / 1024
		context.setLineJoin(.round)
		for estimate in estimates.sorted(by: { $0.created < $1.created }) {
			if let range = estimate.rangeMeters, range > 0 {
				let ring = rangeRing(center: estimate.transmitter, radiusMeters: range)
				fill([SpatialCoveragePolygon(outer: ring, holes: [])], color: shadow, frame: frame, size: size, in: context)
			}
			// Weakest first, so each stronger band paints over the one below it, whether the
			// planner's bands are nested or separate rings.
			for band in estimate.bands {
				fill(band.polygons, color: SIMD4(band.rgba.x, band.rgba.y, band.rgba.z, 1), frame: frame, size: size, in: context)
			}
			if let weakest = estimate.bands.first {
				let path = CGMutablePath()
				for polygon in weakest.polygons {
					path.addLines(between: polygon.outer.map { SpatialTextureRenderer.canvasPoint($0, frame: frame, size: size) })
					path.closeSubpath()
				}
				let c = weakest.rgba * outlineShade
				context.addPath(path)
				context.setStrokeColor(red: c.x, green: c.y, blue: c.z, alpha: 1)
				context.setLineWidth(max(1, scale))
				context.strokePath()
			}
		}
		return context.makeImage()
	}

	/// Each polygon on its own with the even-odd rule, so its holes stay open.
	private static func fill(_ polygons: [SpatialCoveragePolygon], color: SIMD4<Double>, frame: SpatialFrame, size: CGSize, in context: CGContext) {
		context.setFillColor(red: color.x, green: color.y, blue: color.z, alpha: color.w)
		for polygon in polygons {
			let path = CGMutablePath()
			for ring in [polygon.outer] + polygon.holes where ring.count >= 3 {
				path.addLines(between: ring.map { SpatialTextureRenderer.canvasPoint($0, frame: frame, size: size) })
				path.closeSubpath()
			}
			guard !path.isEmpty else { continue }
			context.addPath(path)
			context.fillPath(using: .evenOdd)
		}
	}
}
