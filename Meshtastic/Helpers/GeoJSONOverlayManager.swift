import SwiftUI
import MapKit

/// Manager for loading and managing GeoJSON overlays from consolidated configuration
class GeoJSONOverlayManager {
    static let shared = GeoJSONOverlayManager()
    private init() {}

    private var configuration: GeoJSONOverlayConfiguration?
    private var overlays: [String: [MKOverlay]] = [:]

    /// Load user-uploaded configuration only
    func loadConfiguration() -> GeoJSONOverlayConfiguration? {
        if let cached = configuration {
            return cached
        }

        // Load user-uploaded configuration
        if let userConfig = MapDataManager.shared.loadUserConfiguration() {
            configuration = userConfig
            return userConfig
        }

        // No configuration available
        return nil
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

    /// Check if user-uploaded data is available
    func hasUserData() -> Bool {
        return MapDataManager.shared.getUploadedFiles().contains { $0.isActive }
    }

    /// Get the active data source name
    func getActiveDataSource() -> String {
        if hasUserData() {
            return NSLocalizedString("User Uploaded", comment: "Data source label for user uploaded files")
        } else {
            return NSLocalizedString("No Data", comment: "Data source label when no files are available")
        }
    }
}