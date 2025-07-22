import SwiftUI
import MapKit
import OSLog

/// Manager for loading and managing raw GeoJSON feature collections with embedded styling
class GeoJSONOverlayManager {
    static let shared = GeoJSONOverlayManager()
    private init() {}

    private var featureCollection: GeoJSONFeatureCollection?

    /// Load raw GeoJSON feature collection from user uploads
    func loadFeatureCollection() -> GeoJSONFeatureCollection? {
        Logger.services.debug("🗺️ GeoJSONOverlayManager: loadFeatureCollection() called")
        
        if let cached = featureCollection {
            Logger.services.debug("🗺️ GeoJSONOverlayManager: Returning cached feature collection with \(cached.features.count) features")
            return cached
        }

        // Load user-uploaded feature collection
        Logger.services.debug("🗺️ GeoJSONOverlayManager: Loading feature collection from MapDataManager")
        if let userFeatures = MapDataManager.shared.loadFeatureCollection() {
            Logger.services.info("🗺️ GeoJSONOverlayManager: Loaded feature collection with \(userFeatures.features.count) features")
            featureCollection = userFeatures
            return userFeatures
        }

        // No feature collection available
        Logger.services.debug("🗺️ GeoJSONOverlayManager: No feature collection available")
        return nil
    }

    /// Load styled features for specific enabled configs
    func loadStyledFeaturesForConfigs(_ enabledConfigs: Set<UUID>) -> [GeoJSONStyledFeature] {
        Logger.services.debug("🗺️ GeoJSONOverlayManager: loadStyledFeaturesForConfigs() called with \(enabledConfigs.count) configs")
        
        // Get files that match the enabled configs
        let enabledFiles = MapDataManager.shared.getUploadedFiles().filter { enabledConfigs.contains($0.id) }
        
        guard !enabledFiles.isEmpty else {
            Logger.services.debug("🗺️ GeoJSONOverlayManager: No enabled files found, returning empty array")
            return []
        }
        
        // Load feature collection from enabled files only
        guard let collection = MapDataManager.shared.loadFeatureCollectionForFiles(enabledFiles) else {
            Logger.services.debug("🗺️ GeoJSONOverlayManager: No feature collection available for enabled files, returning empty array")
            return []
        }
        
        var styledFeatures: [GeoJSONStyledFeature] = []
        
        Logger.services.info("🗺️ GeoJSONOverlayManager: Processing \(collection.features.count) features from \(enabledFiles.count) enabled files")
        
        for feature in collection.features {
            // Skip invisible features
            guard feature.isVisible else { 
                Logger.services.debug("🗺️ GeoJSONOverlayManager: Skipping invisible feature")
                continue 
            }
            
            let layerId = feature.layerId ?? "default"
            let styledFeature = GeoJSONStyledFeature(
                feature: feature,
                overlayId: layerId
            )
            styledFeatures.append(styledFeature)
        }
        
        Logger.services.info("🗺️ GeoJSONOverlayManager: Returning \(styledFeatures.count) styled features from enabled configs")
        return styledFeatures
    }

    /// Load styled features for direct rendering (legacy method)
    func loadStyledFeatures() -> [GeoJSONStyledFeature] {
        Logger.services.debug("🗺️ GeoJSONOverlayManager: loadStyledFeatures() called")
        
        guard let collection = loadFeatureCollection() else {
            Logger.services.debug("🗺️ GeoJSONOverlayManager: No feature collection available, returning empty array")
            return []
        }
        
        var styledFeatures: [GeoJSONStyledFeature] = []
        
        Logger.services.info("🗺️ GeoJSONOverlayManager: Processing \(collection.features.count) features")
        
        for feature in collection.features {
            // Skip invisible features
            guard feature.isVisible else { 
                Logger.services.debug("🗺️ GeoJSONOverlayManager: Skipping invisible feature")
                continue 
            }
            
            let layerId = feature.layerId ?? "default"
            let styledFeature = GeoJSONStyledFeature(
                feature: feature,
                overlayId: layerId
            )
            styledFeatures.append(styledFeature)
        }
        
        Logger.services.info("🗺️ GeoJSONOverlayManager: Returning \(styledFeatures.count) styled features")
        return styledFeatures
    }

    /// Get all features grouped by layer ID
    func getFeaturesByLayer() -> [String: [GeoJSONFeature]] {
        guard let collection = loadFeatureCollection() else { return [:] }
        
        var featuresByLayer: [String: [GeoJSONFeature]] = [:]
        
        for feature in collection.features {
            let layerId = feature.layerId ?? "default"
            if featuresByLayer[layerId] == nil {
                featuresByLayer[layerId] = []
            }
            featuresByLayer[layerId]?.append(feature)
        }
        
        return featuresByLayer
    }

    /// Get all available layer IDs from features
    func getAvailableLayerIds() -> [String] {
        guard let collection = loadFeatureCollection() else { return [] }
        let layerIds = Set(collection.features.compactMap { $0.layerId ?? "default" })
        return Array(layerIds).sorted()
    }

    /// Clear cached data (useful for testing or memory management)
    func clearCache() {
        Logger.services.info("🗺️ GeoJSONOverlayManager: Clearing cache")
        featureCollection = nil
    }

    /// Check if user-uploaded data is available (regardless of active state)
    func hasUserData() -> Bool {
        return !MapDataManager.shared.getUploadedFiles().isEmpty
    }
    
    /// Check if there are any active files
    func hasActiveData() -> Bool {
        return MapDataManager.shared.getUploadedFiles().contains { $0.isActive }
    }

    /// Get the active data source name
    func getActiveDataSource() -> String {
        if hasActiveData() {
            return NSLocalizedString("User Uploaded", comment: "Data source label for user uploaded files")
        } else if hasUserData() {
            return NSLocalizedString("Files Available", comment: "Data source label when files exist but none are active")
        } else {
            return NSLocalizedString("No Data", comment: "Data source label when no files are available")
        }
    }
    
    // MARK: - File-based Filtering
    
    /// Get all uploaded files with their active states for UI display
    func getUploadedFilesWithState() -> [MapDataMetadata] {
        return MapDataManager.shared.getUploadedFiles()
    }
    
    /// Toggle the active state of an uploaded file
    func toggleFileActive(_ fileId: UUID) {
        Logger.services.error("🚨 GeoJSONOverlayManager: ENTRY - Toggling active state for file: \(fileId)")
        MapDataManager.shared.toggleFileActive(fileId)
        // Clear cache to force reload with new file states
        clearCache()
        Logger.services.error("🚨 GeoJSONOverlayManager: EXIT - Completed toggle and cache clear for file: \(fileId)")
    }
}