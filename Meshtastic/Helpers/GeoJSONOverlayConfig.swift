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
            return fillColor ?? effectiveStrokeColor
        }
        return "#000000"
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
    
    /// Create MKOverlay from this styled feature
    func createOverlay() -> MKOverlay? {
        do {
            // Convert feature to standard GeoJSON format for MKGeoJSONDecoder
            let featureDict: [String: Any] = [
                "type": feature.type,
                "geometry": [
                    "type": feature.geometry.type,
                    "coordinates": feature.geometry.coordinates.toAnyObject()
                ],
                "properties": feature.properties?.mapValues { $0.toAnyObject() } ?? [:]
            ]
            
            // Creating overlay for geometry
            
            let geojsonData = try JSONSerialization.data(withJSONObject: featureDict)
            let mkFeatures = try MKGeoJSONDecoder().decode(geojsonData)
            
            // MKGeoJSONDecoder processing
            
            if let mkFeature = mkFeatures.first as? MKGeoJSONFeature {
                // Processing geometry objects
                if let geometry = mkFeature.geometry.first as? MKOverlay {
                    // Successfully created overlay
                    return geometry
                }
            }
        } catch {
            Logger.services.error("🗺️ GeoJSONStyledFeature: Failed to convert feature to overlay: \(error.localizedDescription)")
        }
        return nil
    }
    
    /// Get stroke style for this feature
    var strokeStyle: StrokeStyle {
        let dashArray = feature.lineDashArray
        if let dashArray = dashArray, !dashArray.isEmpty {
            return StrokeStyle(
                lineWidth: feature.strokeWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: dashArray.map { CGFloat($0) }
            )
        } else {
            return StrokeStyle(
                lineWidth: feature.strokeWidth,
                lineCap: .round,
                lineJoin: .round
            )
        }
    }
    
    /// Get stroke color with opacity
    var strokeColor: Color {
        return Color(hex: feature.effectiveStrokeColor).opacity(feature.strokeOpacity)
    }
    
    /// Get fill color with opacity
    var fillColor: Color {
        return Color(hex: feature.effectiveFillColor).opacity(feature.fillOpacity)
    }
}

struct GeoJSONGeometry: Codable {
    let type: String // "Point", "LineString", "Polygon", etc.
    let coordinates: AnyCodableValue // Flexible coordinate structure
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
}
