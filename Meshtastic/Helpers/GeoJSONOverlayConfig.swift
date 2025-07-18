import Foundation
import MapKit

// MARK: - Configuration Models

struct GeoJSONOverlayConfiguration: Codable {
    let version: String
    let metadata: OverlayMetadata
    let overlays: [OverlayDefinition]
}

struct OverlayMetadata: Codable {
    let name: String
    let description: String
    let generated: String
}

struct OverlayDefinition: Codable {
    let id: String
    let name: String
    let description: String
    let rendering: RenderingProperties
    let geojson: GeoJSONFeatureCollection
}

struct RenderingProperties: Codable {
    let lineColor: String // Hex color (e.g., "#FF0000")
    let lineOpacity: Double // 0.0 to 1.0
    let lineThickness: Double // Line width in points
    let fillOpacity: Double // 0.0 to 1.0
}

struct GeoJSONFeatureCollection: Codable {
    let type: String // Always "FeatureCollection"
    let features: [GeoJSONFeature]
}

struct GeoJSONFeature: Codable {
    let type: String // Always "Feature"
    let id: Int?
    let geometry: GeoJSONGeometry
    let properties: [String: AnyCodableValue]?
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
}