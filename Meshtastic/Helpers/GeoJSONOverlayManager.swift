import SwiftUI
import MapKit
import OSLog

/// Manager for loading and managing raw GeoJSON feature collections with embedded styling
class GeoJSONOverlayManager {
	static let shared = GeoJSONOverlayManager()
	private init() {}

	private var featureCollection: GeoJSONFeatureCollection?
	// Cache the last styled-features result keyed by the enabled-configs set.
	// GeoJSONStyledFeature instances have stable UUIDs once created, so SwiftUI's
	// ForEach diffing correctly skips unchanged overlays between renders.
	private var styledFeaturesCache: (configs: Set<UUID>, features: [GeoJSONStyledFeature])?

	/// Load raw GeoJSON feature collection from user uploads
	func loadFeatureCollection() -> GeoJSONFeatureCollection? {
		if let cached = featureCollection {
			return cached
		}

		// Load user-uploaded feature collection
		if let userFeatures = MapDataManager.shared.loadFeatureCollection() {
			featureCollection = userFeatures
			return userFeatures
		}

		return nil
	}

	/// Load styled features for specific enabled configs.
	/// Results are cached per unique `enabledConfigs` set — file I/O and JSON decoding
	/// only happen when the set changes, not on every map render.
	func loadStyledFeaturesForConfigs(_ enabledConfigs: Set<UUID>) -> [GeoJSONStyledFeature] {
		if let cache = styledFeaturesCache, cache.configs == enabledConfigs {
			return cache.features
		}

		let enabledFiles = MapDataManager.shared.getUploadedFiles().filter { enabledConfigs.contains($0.id) }
		guard !enabledFiles.isEmpty else {
			styledFeaturesCache = (configs: enabledConfigs, features: [])
			return []
		}

		guard let collection = MapDataManager.shared.loadFeatureCollectionForFiles(enabledFiles) else {
			styledFeaturesCache = (configs: enabledConfigs, features: [])
			return []
		}

		var styledFeatures: [GeoJSONStyledFeature] = []
		for feature in collection.features {
			guard feature.isVisible else { continue }
			styledFeatures.append(GeoJSONStyledFeature(
				feature: feature,
				overlayId: feature.layerId ?? "default"
			))
		}

		styledFeaturesCache = (configs: enabledConfigs, features: styledFeatures)
		return styledFeatures
	}

	/// Load styled features for direct rendering (legacy method)
	func loadStyledFeatures() -> [GeoJSONStyledFeature] {
		guard let collection = loadFeatureCollection() else {
			return []
		}

		var styledFeatures: [GeoJSONStyledFeature] = []

		for feature in collection.features {
			// Skip invisible features
			guard feature.isVisible else {
				continue
			}

			let layerId = feature.layerId ?? "default"
			let styledFeature = GeoJSONStyledFeature(
				feature: feature,
				overlayId: layerId
			)
			styledFeatures.append(styledFeature)
		}

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

	/// Clear cached data (called when files are added, deleted, or toggled).
	func clearCache() {
		featureCollection = nil
		styledFeaturesCache = nil
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
		MapDataManager.shared.toggleFileActive(fileId)
		// Clear cache to force reload with new file states
		clearCache()
	}
}
