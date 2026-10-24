import SwiftUI
import MapKit
import OSLog

/// What the enabled layers draw, ready for the map.
struct GeoJSONLayerContent: @unchecked Sendable {
	struct Ground {
		let id: String
		let overlay: GroundImageOverlay
	}

	let features: [GeoJSONStyledFeature]
	let grounds: [Ground]
	/// Point icons already decoded, by the path of their image file, so drawing a marker never
	/// reads a file on the main thread.
	let icons: [String: UIImage]

	static let empty = GeoJSONLayerContent(features: [], grounds: [], icons: [:])
}

/// Manager for loading and managing raw GeoJSON feature collections with embedded styling
class GeoJSONOverlayManager {
	static let shared = GeoJSONOverlayManager()
	private init() {}

	private var featureCollection: GeoJSONFeatureCollection?
	// Cache the last styled-features result keyed by the enabled-configs set.
	// GeoJSONStyledFeature instances have stable UUIDs once created, so SwiftUI's
	// ForEach diffing correctly skips unchanged overlays between renders.
	private var styledFeaturesCache: (configs: Set<UUID>, features: [GeoJSONStyledFeature])?
	private var groundOverlaysCache: (configs: Set<UUID>, overlays: [ImportedGroundOverlay])?
	private var layerContentCache: (configs: Set<UUID>, content: GeoJSONLayerContent)?

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

	/// Everything the enabled layers draw: their shapes and markers, and their ground images. The
	/// reading, parsing and building of map shapes happen off the main thread, because a layer can
	/// be tens of megabytes and the map must keep scrolling while it loads. The result is cached
	/// per set of enabled layers.
	@MainActor
	func loadLayerContent(_ enabledConfigs: Set<UUID>) async -> GeoJSONLayerContent {
		if let cache = layerContentCache, cache.configs == enabledConfigs { return cache.content }
		let files = MapDataManager.shared.getUploadedFiles().filter { enabledConfigs.contains($0.id) }
		let groundOverlays = MapDataManager.shared.groundOverlays(for: files)
		let content = await Task.detached(priority: .userInitiated) { () -> GeoJSONLayerContent in
			var features: [GeoJSONStyledFeature] = []
			var icons: [String: UIImage] = [:]
			if !files.isEmpty, let collection = MapDataManager.shared.loadFeatureCollectionForFiles(files) {
				for feature in collection.features where feature.isVisible {
					features.append(GeoJSONStyledFeature(feature: feature, overlayId: feature.layerId ?? "default"))
					if let path = feature.importedIconPath, icons[path] == nil,
					   let icon = ImportedImageCache.shared.icon(atPath: path) {
						icons[path] = icon
					}
				}
			}
			let grounds = groundOverlays.compactMap { ground in
				ground.makeOverlay().map { GeoJSONLayerContent.Ground(id: ground.id, overlay: $0) }
			}
			return GeoJSONLayerContent(features: features, grounds: grounds, icons: icons)
		}.value
		layerContentCache = (configs: enabledConfigs, content: content)
		return content
	}

	/// The ground overlays (images on the map) of the enabled layers, cached like the features.
	func loadGroundOverlaysForConfigs(_ enabledConfigs: Set<UUID>) -> [ImportedGroundOverlay] {
		if let cache = groundOverlaysCache, cache.configs == enabledConfigs {
			return cache.overlays
		}
		let enabledFiles = MapDataManager.shared.getUploadedFiles().filter { enabledConfigs.contains($0.id) }
		let overlays = MapDataManager.shared.groundOverlays(for: enabledFiles)
		groundOverlaysCache = (configs: enabledConfigs, overlays: overlays)
		return overlays
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
		groundOverlaysCache = nil
		layerContentCache = nil
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

	/// Set the active state of an uploaded file explicitly (persisted).
	func setFileActive(_ fileId: UUID, _ isActive: Bool) {
		MapDataManager.shared.setFileActive(fileId, isActive)
		clearCache()
	}
}
