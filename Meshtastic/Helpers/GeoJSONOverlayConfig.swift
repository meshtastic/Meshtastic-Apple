import Foundation
import MapKit
import SwiftUI
import CoreLocation
import OSLog

// MARK: - Raw GeoJSON Support Only

struct GeoJSONFeatureCollection: Codable {
	let type: String // Always "FeatureCollection"
	let features: [GeoJSONFeature]
}

struct GeoJSONFeature: Codable {
	let type: String // Always "Feature"
	let id: Int?
	let geometry: GeoJSONGeometry
	let properties: [String: AnyCodableValue]?

	// MARK: - GeoJSON Styling Properties

	/// Extract feature name from properties, defaulting to empty string
	var name: String {
		// Check for "NAME" first (uppercase), then "name" (lowercase)
		if case .string(let value) = properties?["NAME"] {
			return value
		}
		if case .string(let value) = properties?["name"] {
			return value
		}
		return ""
	}

	/// Extract layer metadata from properties
	var layerId: String? {
		if case .string(let value) = properties?["layer_id"] {
			return value
		}
		return nil
	}

	var layerName: String? {
		if case .string(let value) = properties?["layer_name"] {
			return value
		}
		return nil
	}

	var layerDescription: String? {
		if case .string(let value) = properties?["description"] {
			return value
		}
		return nil
	}

	var isVisible: Bool {
		if case .bool(let value) = properties?["visible"] {
			return value
		}
		return true // Default to visible
	}

	// MARK: - Point/Marker Styling

	var markerColor: String? {
		if case .string(let value) = properties?["marker-color"] {
			return value
		}
		return nil
	}

	var markerSize: String? {
		if case .string(let value) = properties?["marker-size"] {
			return value
		}
		return "medium" // Default size
	}

	var markerSymbol: String? {
		if case .string(let value) = properties?["marker-symbol"] {
			return value
		}
		return nil
	}

	// MARK: - Stroke/Line Styling

	var strokeColor: String? {
		if case .string(let value) = properties?["stroke"] {
			return value
		}
		return nil
	}

	var strokeWidth: Double {
		if case .double(let value) = properties?["stroke-width"] {
			return value
		} else if case .int(let value) = properties?["stroke-width"] {
			return Double(value)
		}
		return 1.0 // Default width
	}

	var strokeOpacity: Double {
		if case .double(let value) = properties?["stroke-opacity"] {
			return value
		} else if case .int(let value) = properties?["stroke-opacity"] {
			return Double(value)
		}
		return 1.0 // Default opacity
	}

	var lineDashArray: [Double]? {
		if case .array(let values) = properties?["line-dasharray"] {
			return values.compactMap { value in
				switch value {
				case .double(let d): return d
				case .int(let i): return Double(i)
				default: return nil
				}
			}
		}
		return nil
	}

	// MARK: - Fill Styling

	var fillColor: String? {
		if case .string(let value) = properties?["fill"] {
			return value
		}
		return nil
	}

	var rfPredictionColor: String? {
		if case .string(let value) = properties?["color"] {
			return value
		}
		return nil
	}

	var rfPredictionLabel: String? {
		if case .string(let value) = properties?["label"] {
			return value
		}
		return nil
	}

	var dbm: Double? {
		if case .double(let value) = properties?["dbm"] {
			return value
		} else if case .int(let value) = properties?["dbm"] {
			return Double(value)
		}
		return nil
	}

	var fillOpacity: Double {
		if case .double(let value) = properties?["fill-opacity"] {
			return value
		} else if case .int(let value) = properties?["fill-opacity"] {
			return Double(value)
		}
		return 0.0 // Default to no fill
	}

	// MARK: - Computed Rendering Properties

	/// Get effective stroke color (fallback to marker color for points)
	var effectiveStrokeColor: String {
		return strokeColor ?? markerColor ?? "#000000"
	}

	/// Get effective fill color (fallback to stroke color if fill opacity > 0)
	var effectiveFillColor: String {
		if fillOpacity > 0 {
			return fillColor ?? rfPredictionColor ?? effectiveStrokeColor
		}
		return rfPredictionColor ?? "#000000"
	}

	var effectiveFillOpacity: Double {
		if properties?["fill-opacity"] != nil {
			return fillOpacity
		}
		if rfPredictionColor != nil {
			return 0.45
		}
		return fillOpacity
	}

	var effectiveStrokeWidth: Double {
		if properties?["stroke-width"] != nil {
			return strokeWidth
		}
		if rfPredictionColor != nil {
			return 0.5
		}
		return strokeWidth
	}

	var effectiveStrokeOpacity: Double {
		if properties?["stroke-opacity"] != nil {
			return strokeOpacity
		}
		if rfPredictionColor != nil {
			return 0.65
		}
		return strokeOpacity
	}

	/// Convert marker size to point radius
	var markerRadius: CGFloat {
		switch markerSize {
		case "small": return 4.0
		case "medium": return 8.0
		case "large": return 12.0
		default: return 4.0
		}
	}
}

// MARK: - Styled Feature Wrapper

/// Wrapper for a GeoJSON feature with its styling properties and metadata
struct GeoJSONStyledFeature: Identifiable {
	let id = UUID()
	let feature: GeoJSONFeature
	let overlayId: String
	/// MKOverlay pre-computed once at init — avoids repeated JSONSerialization + MKGeoJSONDecoder
	/// calls on every map render pass.
	let precomputedOverlay: MKOverlay?
	let precomputedOverlays: [GeoJSONRenderableOverlay]

	init(feature: GeoJSONFeature, overlayId: String) {
		self.feature = feature
		self.overlayId = overlayId
		let overlays = GeoJSONStyledFeature.makeOverlays(for: feature)
		self.precomputedOverlay = overlays.first
		self.precomputedOverlays = overlays.enumerated().map { index, overlay in
			GeoJSONRenderableOverlay(overlay: overlay, index: index)
		}
	}

	/// Builds an MKOverlay from a GeoJSON feature. Static so it can be called from init.
	private static func makeOverlay(for feature: GeoJSONFeature) -> MKOverlay? {
		makeOverlays(for: feature).first
	}

	private static func makeOverlays(for feature: GeoJSONFeature) -> [MKOverlay] {
		let polygonOverlays = feature.geometry.makePolygonOverlays()
		if !polygonOverlays.isEmpty {
			return polygonOverlays
		}

		let featureDict: [String: Any] = [
			"type": feature.type,
			"geometry": [
				"type": feature.geometry.type,
				"coordinates": feature.geometry.coordinates.toAnyObject()
			],
			"properties": feature.properties?.mapValues { $0.toAnyObject() } ?? [:]
		]

		do {
			let geojsonData = try JSONSerialization.data(withJSONObject: featureDict)
			let mkFeatures = try MKGeoJSONDecoder().decode(geojsonData)
			if let mkFeature = mkFeatures.first as? MKGeoJSONFeature,
			   let geometry = mkFeature.geometry.first as? MKOverlay {
				return [geometry]
			} else {
				Logger.services.error("🗺️ GeoJSONStyledFeature: Failed to create overlay - no valid MKOverlay geometry.")
			}
		} catch {
			Logger.services.error("🗺️ GeoJSONStyledFeature: Failed to build overlay: \(error.localizedDescription)")
		}
		return []
	}

	/// Returns the pre-computed overlay. Retained for API compatibility.
	func createOverlay() -> MKOverlay? { precomputedOverlay }
	func createOverlays() -> [GeoJSONRenderableOverlay] { precomputedOverlays }

	/// Get stroke style for this feature
	var strokeStyle: StrokeStyle {
		let dashArray = feature.lineDashArray
		if let dashArray = dashArray, !dashArray.isEmpty {
			return StrokeStyle(
				lineWidth: feature.effectiveStrokeWidth,
				lineCap: .round,
				lineJoin: .round,
				dash: dashArray.map { CGFloat($0) }
			)
		} else {
			return StrokeStyle(
				lineWidth: feature.effectiveStrokeWidth,
				lineCap: .round,
				lineJoin: .round
			)
		}
	}

	/// Get stroke color with opacity
	var strokeColor: Color {
		strokeColor(opacityMultiplier: GeoJSONOverlayManager.defaultOpacity)
	}

	/// Get fill color with opacity
	var fillColor: Color {
		fillColor(opacityMultiplier: GeoJSONOverlayManager.defaultOpacity)
	}

	func strokeColor(opacityMultiplier: Double) -> Color {
		let opacity = Self.scaledOpacity(feature.effectiveStrokeOpacity, multiplier: opacityMultiplier)
		return Self.color(from: feature.rfPredictionColor ?? feature.effectiveStrokeColor).opacity(opacity)
	}

	func fillColor(opacityMultiplier: Double) -> Color {
		let opacity = Self.scaledOpacity(feature.effectiveFillOpacity, multiplier: opacityMultiplier)
		return Self.color(from: feature.effectiveFillColor).opacity(opacity)
	}

	private static func scaledOpacity(_ opacity: Double, multiplier: Double) -> Double {
		let normalizedMultiplier = GeoJSONOverlayManager.normalizedOpacity(multiplier)
		return min(1.0, max(0.0, opacity * normalizedMultiplier))
	}

	private static func color(from styleValue: String) -> Color {
		let trimmed = styleValue.trimmingCharacters(in: .whitespacesAndNewlines)
		let lowercased = trimmed.lowercased()

		if lowercased.hasPrefix("rgb("), lowercased.hasSuffix(")") {
			let values = lowercased
				.dropFirst(4)
				.dropLast()
				.split(separator: ",")
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
				.compactMap(Double.init)

			if values.count == 3 {
				return Color(
					.sRGB,
					red: min(max(values[0], 0), 255) / 255,
					green: min(max(values[1], 0), 255) / 255,
					blue: min(max(values[2], 0), 255) / 255,
					opacity: 1
				)
			}
		}

		return Color(hex: trimmed)
	}
}

struct GeoJSONRenderableOverlay: Identifiable {
	let id: String
	let overlay: MKOverlay

	init(overlay: MKOverlay, index: Int) {
		self.overlay = overlay
		self.id = "\(ObjectIdentifier(overlay as AnyObject))-\(index)"
	}
}

struct GeoJSONGeometry: Codable {
	let type: String // "Point", "LineString", "Polygon", etc.
	let coordinates: AnyCodableValue // Flexible coordinate structure

	func makePolygonOverlays() -> [MKPolygon] {
		switch type {
		case "Polygon":
			guard let rings = coordinates.polygonRings() else { return [] }
			if let polygon = Self.makePolygon(from: rings) {
				return [polygon]
			}
			return []
		case "MultiPolygon":
			guard let polygons = coordinates.multiPolygonRings() else { return [] }
			return polygons.compactMap { Self.makePolygon(from: $0) }
		default:
			return []
		}
	}

	private static func makePolygon(from rings: [[CLLocationCoordinate2D]]) -> MKPolygon? {
		guard var exterior = rings.first, exterior.count >= 3 else {
			return nil
		}
		let interiorPolygons = rings.dropFirst().compactMap { ring -> MKPolygon? in
			guard ring.count >= 3 else { return nil }
			var interior = ring
			return MKPolygon(coordinates: &interior, count: interior.count)
		}
		return MKPolygon(coordinates: &exterior, count: exterior.count, interiorPolygons: interiorPolygons)
	}
}

// MARK: - Flexible JSON Value Type

enum AnyCodableValue: Codable {
	case string(String)
	case int(Int)
	case double(Double)
	case bool(Bool)
	case array([AnyCodableValue])
	case object([String: AnyCodableValue])
	case null

	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()

		if container.decodeNil() {
			self = .null
		} else if let value = try? container.decode(Bool.self) {
			self = .bool(value)
		} else if let value = try? container.decode(Int.self) {
			self = .int(value)
		} else if let value = try? container.decode(Double.self) {
			self = .double(value)
		} else if let value = try? container.decode(String.self) {
			self = .string(value)
		} else if let value = try? container.decode([AnyCodableValue].self) {
			self = .array(value)
		} else if let value = try? container.decode([String: AnyCodableValue].self) {
			self = .object(value)
		} else {
			throw DecodingError.typeMismatch(AnyCodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode AnyCodableValue"))
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()

		switch self {
		case .null:
			try container.encodeNil()
		case .bool(let value):
			try container.encode(value)
		case .int(let value):
			try container.encode(value)
		case .double(let value):
			try container.encode(value)
		case .string(let value):
			try container.encode(value)
		case .array(let value):
			try container.encode(value)
		case .object(let value):
			try container.encode(value)
		}
	}

	// Helper to convert coordinates to the format expected by MKGeoJSONDecoder
	func toAnyObject() -> Any {
		switch self {
		case .null:
			return NSNull()
		case .bool(let value):
			return value
		case .int(let value):
			return value
		case .double(let value):
			return value
		case .string(let value):
			return value
		case .array(let values):
			return values.map { $0.toAnyObject() }
		case .object(let dict):
			return dict.mapValues { $0.toAnyObject() }
		}
	}

	// Helper to convert Point coordinates to CLLocationCoordinate2D
	func toCoordinate() -> CLLocationCoordinate2D? {
		if case .array(let coords) = self,
		   coords.count >= 2 {
			let lon: Double
			let lat: Double

			switch coords[0] {
			case .double(let d): lon = d
			case .int(let i): lon = Double(i)
			default: return nil
			}

			switch coords[1] {
			case .double(let d): lat = d
			case .int(let i): lat = Double(i)
			default: return nil
			}

			return CLLocationCoordinate2D(latitude: lat, longitude: lon)
		}
		return nil
	}

	func polygonRings() -> [[CLLocationCoordinate2D]]? {
		guard case .array(let rings) = self else { return nil }
		let parsedRings = rings.compactMap { $0.coordinateRing() }
		return parsedRings.isEmpty ? nil : parsedRings
	}

	func multiPolygonRings() -> [[[CLLocationCoordinate2D]]]? {
		guard case .array(let polygons) = self else { return nil }
		let parsedPolygons = polygons.compactMap { $0.polygonRings() }
		return parsedPolygons.isEmpty ? nil : parsedPolygons
	}

	private func coordinateRing() -> [CLLocationCoordinate2D]? {
		guard case .array(let points) = self else { return nil }
		let coordinates = points.compactMap { $0.toCoordinate() }
		return coordinates.count >= 3 ? coordinates : nil
	}
}
