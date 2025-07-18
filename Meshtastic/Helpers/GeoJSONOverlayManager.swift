import SwiftUI
import MapKit

/// Manager for loading and managing GeoJSON overlays from consolidated configuration
class GeoJSONOverlayManager {
    static let shared = GeoJSONOverlayManager()
    private init() {}

    private var configuration: GeoJSONOverlayConfiguration?
    private var overlays: [String: [MKOverlay]] = [:]

    /// Load and decompress the consolidated configuration
    func loadConfiguration() -> GeoJSONOverlayConfiguration? {
        if let cached = configuration {
            return cached
        }

                        guard let url = Bundle.main.url(forResource: "BurningManGeoJSONMapConfig", withExtension: "json.zlib") else {
            print("GeoJSONOverlayManager: No compressed configuration file found")
            return nil
        }

        do {
            let compressedData = try Data(contentsOf: url)
            print("GeoJSONOverlayManager: Loaded compressed data size: \(compressedData.count) bytes")

            let decompressedData = try compressedData.zlibDecompressed()
            print("GeoJSONOverlayManager: Decompressed data size: \(decompressedData.count) bytes")

            // Debug: Check the first few characters of decompressed data
            if let decompressedString = String(data: decompressedData, encoding: .utf8) {
                let firstChars = String(decompressedString.prefix(100))
                print("GeoJSONOverlayManager: First 100 chars of decompressed data: \(firstChars)")
            } else {
                print("GeoJSONOverlayManager: Decompressed data is not valid UTF-8")
                // Show first few bytes as hex
                let firstBytes = decompressedData.prefix(20).map { String(format: "%02x", $0) }.joined()
                print("GeoJSONOverlayManager: First 20 bytes (hex): \(firstBytes)")
            }

            let config = try JSONDecoder().decode(GeoJSONOverlayConfiguration.self, from: decompressedData)
            print("GeoJSONOverlayManager: Loaded configuration with \(config.overlays.count) overlays")

            configuration = config
            return config
        } catch {
            print("GeoJSONOverlayManager: Failed to load configuration: \(error)")
            return nil
        }
    }

    /// Load overlays for a specific overlay ID
    func loadOverlays(for overlayId: String) -> [MKOverlay] {
        print("GeoJSONOverlayManager: Attempting to load overlays for \(overlayId)")

        if let cached = overlays[overlayId] {
            print("GeoJSONOverlayManager: Returning cached overlays for \(overlayId), count: \(cached.count)")
            return cached
        }

        guard let config = loadConfiguration() else {
            print("GeoJSONOverlayManager: Failed to load configuration")
            return []
        }

        guard let overlayDef = config.overlays.first(where: { $0.id == overlayId }) else {
            print("GeoJSONOverlayManager: No overlay found for ID: \(overlayId)")
            return []
        }

        do {
            // Convert our custom GeoJSON structure to the format expected by MKGeoJSONDecoder
            let standardGeoJSON: [String: Any] = [
                "type": overlayDef.geojson.type,
                "features": overlayDef.geojson.features.map { feature in
                    var featureDict: [String: Any] = [
                        "type": feature.type,
                        "geometry": [
                            "type": feature.geometry.type,
                            "coordinates": feature.geometry.coordinates.toAnyObject()
                        ]
                    ]

                    if let id = feature.id {
                        featureDict["id"] = id
                    }

                    if let properties = feature.properties {
                        featureDict["properties"] = properties.mapValues { $0.toAnyObject() }
                    }

                    return featureDict
                }
            ]

            let geojsonData = try JSONSerialization.data(withJSONObject: standardGeoJSON)
            let features = try MKGeoJSONDecoder().decode(geojsonData)
            print("GeoJSONOverlayManager: Decoded \(features.count) features for \(overlayId)")

            var allOverlays: [MKOverlay] = []
            for (index, feature) in features.enumerated() {
                if let mkFeature = feature as? MKGeoJSONFeature {
                    print("GeoJSONOverlayManager: Feature \(index) has \(mkFeature.geometry.count) geometries")
                    for (geoIndex, geometry) in mkFeature.geometry.enumerated() {
                        print("GeoJSONOverlayManager:   Geometry \(geoIndex): \(Swift.type(of: geometry))")
                        if let overlay = geometry as? MKOverlay {
                            allOverlays.append(overlay)
                            print("GeoJSONOverlayManager:     Added as overlay")
                        } else {
                            print("GeoJSONOverlayManager:     Could not cast to MKOverlay")
                        }
                    }
                } else {
                    print("GeoJSONOverlayManager: Feature \(index) could not be cast to MKGeoJSONFeature")
                }
            }

            print("GeoJSONOverlayManager: Created \(allOverlays.count) total overlays for \(overlayId)")
            overlays[overlayId] = allOverlays
            return allOverlays
        } catch {
            print("GeoJSONOverlayManager: Failed to decode overlays for \(overlayId): \(error)")
            return []
        }
    }

    /// Get rendering properties for an overlay
    func getRenderingProperties(for overlayId: String) -> RenderingProperties? {
        guard let config = loadConfiguration() else { return nil }
        return config.overlays.first(where: { $0.id == overlayId })?.rendering
    }

    /// Get all available overlay IDs
    func getAvailableOverlayIds() -> [String] {
        guard let config = loadConfiguration() else { return [] }
        return config.overlays.map { $0.id }
    }

    /// Get overlay definition by ID
    func getOverlayDefinition(for overlayId: String) -> OverlayDefinition? {
        guard let config = loadConfiguration() else { return nil }
        return config.overlays.first(where: { $0.id == overlayId })
    }

    /// Clear cached overlays (useful for testing or memory management)
    func clearCache() {
        overlays.removeAll()
        configuration = nil
    }
}