import SwiftUI
import MapKit

/// Enum for supported static overlays
enum StaticGeoJSONOverlay: String, CaseIterable {
    case streetOutlines = "Street_Outlines"
    case toilets = "Toilets"
    case trashFence = "Trash_Fence"

    var filename: String { self.rawValue + ".geojson" }
}

/// Manager for loading and adding GeoJSON overlays
class GeoJSONOverlayManager {
    static let shared = GeoJSONOverlayManager()
    private init() {}

    private var overlays: [StaticGeoJSONOverlay: [MKOverlay]] = [:]

    /// Load overlays for a given type (from bundle)
    func loadOverlays(for type: StaticGeoJSONOverlay) -> [MKOverlay] {
        print("GeoJSONOverlayManager: Attempting to load overlays for \(type.rawValue)")
        if let cached = overlays[type] {
            print("GeoJSONOverlayManager: Returning cached overlays for \(type.rawValue), count: \(cached.count)")
            return cached
        }
        guard let url = Bundle.main.url(forResource: type.rawValue, withExtension: "geojson") else {
            print("GeoJSONOverlayManager: No file found for \(type.rawValue).geojson")
            return []
        }
        print("GeoJSONOverlayManager: Found file at: \(url)")
        do {
            let data = try Data(contentsOf: url)
            print("GeoJSONOverlayManager: Loaded data size: \(data.count) bytes")
            let features = try MKGeoJSONDecoder().decode(data)
            print("GeoJSONOverlayManager: Decoded \(features.count) features for \(type.rawValue)")

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

            print("GeoJSONOverlayManager: Created \(allOverlays.count) total overlays for \(type.rawValue)")
            overlays[type] = allOverlays
            return allOverlays
        } catch {
            print("Failed to load GeoJSON overlay: \(type) error: \(error)")
            return []
        }
    }

    /// Add overlays to the map
    func addOverlays(_ type: StaticGeoJSONOverlay, to mapView: MKMapView) {
        let overlays = loadOverlays(for: type)
        mapView.addOverlays(overlays, level: .aboveLabels)
    }
    /// Remove overlays from the map
    func removeOverlays(_ type: StaticGeoJSONOverlay, from mapView: MKMapView) {
        let overlays = self.overlays[type] ?? []
        mapView.removeOverlays(overlays)
    }
}