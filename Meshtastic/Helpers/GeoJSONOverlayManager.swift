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
            return nil
        }

        do {
            let compressedData = try Data(contentsOf: url)
            let decompressedData = try compressedData.zlibDecompressed()
            let config = try JSONDecoder().decode(GeoJSONOverlayConfiguration.self, from: decompressedData)

            configuration = config
            return config
        } catch {
            return nil
        }
    }

    /// Load overlays for a specific overlay ID
    func loadOverlays(for overlayId: String) -> [MKOverlay] {
        if let cached = overlays[overlayId] {
            return cached
        }

        guard let config = loadConfiguration() else {
            return []
        }

        guard let overlayDef = config.overlays.first(where: { $0.id == overlayId }) else {
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
                        ],
                        "properties": [:]
                    ]

                    if let id = feature.id {
                        featureDict["id"] = id
                    }

                    return featureDict
                }
            ]

            let geojsonData = try JSONSerialization.data(withJSONObject: standardGeoJSON)
            let features = try MKGeoJSONDecoder().decode(geojsonData)

            var allOverlays: [MKOverlay] = []
            for (index, feature) in features.enumerated() {
                if let mkFeature = feature as? MKGeoJSONFeature {
                    for (geoIndex, geometry) in mkFeature.geometry.enumerated() {
                        if let overlay = geometry as? MKOverlay {
                            allOverlays.append(overlay)
                        }
                    }
                }
            }

                        overlays[overlayId] = allOverlays
            return allOverlays
        } catch {
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