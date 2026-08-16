//
//  OfflineMapManager.swift
//  Meshtastic
//
//  Owns the on-disk store of downloaded offline map regions: the `OfflineMaps`
//  directory in Documents, the `offline_maps.json` manifest, and the extracted
//  `.pmtiles` archives. Mirrors the file-backed `MapDataManager` pattern.
//

import Foundation
import OSLog
import SwiftUI

/// How much zoom detail to extract. Higher detail means much larger files.
enum OfflineMapDetailLevel: String, CaseIterable, Identifiable {
	case standard
	case high

	var id: String { rawValue }

	/// Always start at the world zoom so zoomed-out context is available offline.
	var minZoom: Int { 0 }

	/// Protomaps daily builds top out at z15.
	var maxZoom: Int {
		switch self {
		case .standard: return 13
		case .high: return 15
		}
	}

	var label: String {
		switch self {
		case .standard: return String(localized: "Standard")
		case .high: return String(localized: "High detail")
		}
	}
}

/// Live state of an in-flight region download, surfaced to the UI.
struct OfflineMapDownloadProgress: Identifiable, Equatable {
	enum State: Equatable {
		case preparing
		case downloading
		case writing
		case failed(String)
	}

	let id: UUID
	var name: String
	var state: State = .preparing
	/// 0...1, or `nil` while indeterminate (e.g. preparing).
	var fractionCompleted: Double?
	var bytesWritten: Int64 = 0
	var estimatedBytes: Int64 = 0
}

struct OfflineMapDownloadLifecycle {
	private(set) var activeID: UUID?

	var isDownloading: Bool { activeID != nil }

	mutating func begin(id: UUID) -> Bool {
		guard activeID == nil else { return false }
		activeID = id
		return true
	}

	mutating func end(id: UUID) -> Bool {
		guard activeID == id else { return false }
		activeID = nil
		return true
	}

	func isCurrent(_ id: UUID) -> Bool {
		activeID == id
	}
}

/// Reasons a download can't proceed (surfaced to the user).
enum OfflineMapError: LocalizedError {
	case exceedsPerMapLimit(Int64)
	case storageLimit(String)

	var errorDescription: String? {
		switch self {
		case .exceedsPerMapLimit(let limit):
			let formatted = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
			return "This map is larger than the \(formatted) per-map limit. Zoom in or lower the detail level."
		case .storageLimit(let message):
			return message
		}
	}
}

enum OfflineMapStorageLimits {
	static let maxRegionBytes: Int64 = 512 * 1024 * 1024
	static let maxRegions = 10
	static let maxTotalBytes: Int64 = 3 * 1024 * 1024 * 1024
}

@MainActor
final class OfflineMapManager: ObservableObject {

	static let shared = OfflineMapManager()

	// MARK: - Limits
	/// Maximum size of a single downloaded map.
	static let maxRegionBytes = OfflineMapStorageLimits.maxRegionBytes // 0.5 GB
	/// Maximum number of downloaded maps kept at once.
	static let maxRegions = OfflineMapStorageLimits.maxRegions
	/// Maximum combined size of all downloaded maps.
	static let maxTotalBytes = OfflineMapStorageLimits.maxTotalBytes // 3 GB

	/// Completed, persisted regions, newest first.
	@Published private(set) var regions: [OfflineMapRegion] = []
	/// The currently downloading region, if any (one at a time).
	@Published var activeDownload: OfflineMapDownloadProgress?
	@Published private(set) var isImporting = false

	static let directoryName = "OfflineMaps"
	static let manifestName = "offline_maps.json"
	private var loaded = false
	private var downloadTask: Task<Void, Never>?
	private var downloadLifecycle = OfflineMapDownloadLifecycle()
	private var downloadCompletion: ((OfflineMapRegion?) -> Void)?

	private init() {}

	// MARK: - Downloading

	/// Whether a download is in flight (one region at a time).
	var isDownloading: Bool { downloadLifecycle.isDownloading }
	var isBusy: Bool { isDownloading || isImporting }

	/// The first existing region whose extent intersects `bounds` (ignoring `excluding`), or nil.
	/// Downloads must not overlap — avoids duplicate coverage.
	func overlappingRegion(with bounds: GeoBounds, excluding: OfflineMapRegion? = nil) -> OfflineMapRegion? {
		regions.first { region in
			region.id != excluding?.id &&
			region.bounds.minLon <= bounds.maxLon && region.bounds.maxLon >= bounds.minLon &&
			region.bounds.minLat <= bounds.maxLat && region.bounds.maxLat >= bounds.minLat
		}
	}

	/// Why a download of `estimatedBytes` (replacing `replacing`) can't proceed against the limits, or
	/// nil if it can. Drives the Download button's disabled state + reason message, and is a backstop.
	func downloadBlockReason(estimatedBytes: Int64, replacing: OfflineMapRegion?) -> String? {
		let effectiveCount = regions.count - (replacing != nil ? 1 : 0)
		if effectiveCount >= Self.maxRegions {
			return String(localized: "You can keep up to \(Self.maxRegions) offline maps. Remove one to download another.")
		}
		if estimatedBytes > Self.maxRegionBytes {
			let limit = ByteCountFormatter.string(fromByteCount: Self.maxRegionBytes, countStyle: .file)
			return String(localized: "This map is larger than the \(limit) per-map limit. Zoom in or lower the detail.")
		}
		let otherTotal = totalSize - (replacing.map { $0.fileSize + ($0.terrain?.byteCount ?? 0) } ?? 0)
		if otherTotal + estimatedBytes > Self.maxTotalBytes {
			let limit = ByteCountFormatter.string(fromByteCount: Self.maxTotalBytes, countStyle: .file)
			return String(localized: "This would exceed the \(limit) total offline storage limit. Remove a map first.")
		}
		return nil
	}

	func startDownload(
		name: String,
		bounds: GeoBounds,
		detail: OfflineMapDetailLevel,
		replacing: OfflineMapRegion? = nil,
		onCompletion: ((OfflineMapRegion?) -> Void)? = nil
	) {
		guard !isBusy, let archive = newArchiveURL() else {
			onCompletion?(nil)
			return
		}
		// Avoid duplicate coverage and preserve the storage ceiling even if the caller bypasses the UI.
		guard overlappingRegion(with: bounds, excluding: replacing) == nil else {
			onCompletion?(nil)
			return
		}
		guard regions.count - (replacing != nil ? 1 : 0) < Self.maxRegions else {
			onCompletion?(nil)
			return
		}
		let regionID = UUID()
		guard downloadLifecycle.begin(id: regionID) else {
			onCompletion?(nil)
			return
		}
		let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
		let finalName = trimmedName.isEmpty ? String(localized: "Offline Map") : trimmedName
		activeDownload = OfflineMapDownloadProgress(id: regionID, name: finalName, state: .preparing, fractionCompleted: nil)
		downloadCompletion = onCompletion

		downloadTask = Task { [weak self] in
			guard let self else { return }
			let extractor = PMTilesExtractor()
			do {
				guard let build = await extractor.latestBuild() else { throw PMTilesExtractorError.noBuildAvailable }
				let plan = try await extractor.makePlan(
					sourceURL: build.url, sourceBuild: build.build,
					bounds: bounds, minZoom: detail.minZoom, maxZoom: detail.maxZoom
				)
				guard plan.payloadBytes <= Self.maxRegionBytes else { throw OfflineMapError.exceedsPerMapLimit(Self.maxRegionBytes) }
				if let reason = self.downloadBlockReason(estimatedBytes: plan.payloadBytes, replacing: replacing) {
					throw OfflineMapError.storageLimit(reason)
				}
				await self.markDownloading(id: regionID, estimatedBytes: plan.payloadBytes)
				try await extractor.extract(plan: plan, to: archive.url) { [weak self] written, total in
					Task { @MainActor in self?.updateProgress(id: regionID, written: written, total: total) }
				}
				let hasValidHeader = await Task.detached(priority: .utility) {
					PMTilesArchive.header(url: archive.url) != nil
				}.value
				guard hasValidHeader else { throw PMTilesExtractorError.badHeader }
				let region = OfflineMapRegion(
					id: regionID, name: finalName, fileName: archive.fileName,
					bounds: plan.bounds, minZoom: plan.minZoom, maxZoom: plan.maxZoom,
					fileSize: 0, sourceBuild: build.build
				)
				await self.finishDownload(id: regionID, region: region, removing: replacing)
				// Terrain rides along with every download but is never fatal: the basemap
				// is already saved, and a terrain failure just surfaces as retryable.
				// tvOS skips it — nothing renders terrain there yet, and its cache storage is purgeable.
				#if !os(tvOS)
				await self.downloadTerrain(for: region)
				#endif
			} catch is CancellationError {
				try? FileManager.default.removeItem(at: archive.url)
				await self.clearDownload(id: regionID)
			} catch {
				try? FileManager.default.removeItem(at: archive.url)
				let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
				Logger.services.error("🗺️ [Offline] Download failed: \(message, privacy: .public)")
				await self.failDownload(id: regionID, message: message)
			}
		}
	}

	func cancelDownload() {
		guard let id = downloadLifecycle.activeID else { return }
		downloadTask?.cancel()
		clearDownload(id: id)
	}

	/// Validates and copies an externally supplied PMTiles or MBTiles archive into the managed store.
	/// The caller owns security-scoped access to `sourceURL` when it came from Files or Open In.
	func importOfflineMap(from sourceURL: URL) async throws -> OfflineMapRegion {
		loadIfNeeded()
		guard !isBusy else { throw OfflineMapImportError.operationInProgress }
		isImporting = true
		defer { isImporting = false }

		let existingURLs = regions.compactMap(fileURL(for:))
		let source = try await Task.detached(priority: .userInitiated) {
			try OfflineMapImportWorker.inspectSource(at: sourceURL)
		}.value
		let existingDigests = await Task.detached(priority: .utility) {
			OfflineMapImportWorker.existingDigests(for: existingURLs)
		}.value
		guard !existingDigests.contains(source.digest) else {
			throw OfflineMapImportError.duplicateMap
		}
		guard regions.count < Self.maxRegions else {
			throw OfflineMapImportError.exceedsMapCountLimit
		}
		guard totalSize + source.fileSize <= Self.maxTotalBytes else {
			throw OfflineMapImportError.exceedsTotalStorageLimit
		}

		guard let destination = newArchiveURL(fileExtension: source.format.fileExtension) else {
			throw OfflineMapImportError.unreadableFile
		}
		do {
			let imported = try await Task.detached(priority: .userInitiated) {
				try OfflineMapImportWorker.copyAndValidate(from: sourceURL, to: destination.url)
			}.value
			guard !existingDigests.contains(imported.digest) else {
				throw OfflineMapImportError.duplicateMap
			}
			guard regions.count < Self.maxRegions else {
				throw OfflineMapImportError.exceedsMapCountLimit
			}
			guard totalSize + imported.fileSize <= Self.maxTotalBytes else {
				throw OfflineMapImportError.exceedsTotalStorageLimit
			}
			let region = OfflineMapRegion(
				name: source.fileName.isEmpty ? String(localized: "Imported Offline Map") : source.fileName,
				fileName: destination.fileName,
				bounds: imported.metadata.bounds,
				minZoom: imported.metadata.minZoom,
				maxZoom: imported.metadata.maxZoom,
				fileSize: imported.fileSize,
				sourceBuild: "Imported"
			)
			add(region)
			return region
		} catch {
			try? FileManager.default.removeItem(at: destination.url)
			throw error
		}
	}

	/// Dismisses a failed download banner.
	func dismissDownload() {
		guard case .failed = activeDownload?.state else { return }
		activeDownload = nil
	}

	private func markDownloading(id: UUID, estimatedBytes: Int64) {
		guard downloadLifecycle.isCurrent(id), activeDownload?.id == id else { return }
		activeDownload?.state = .downloading
		activeDownload?.estimatedBytes = estimatedBytes
		activeDownload?.fractionCompleted = 0
	}

	private func updateProgress(id: UUID, written: Int64, total: Int64) {
		guard downloadLifecycle.isCurrent(id), activeDownload?.id == id else { return }
		activeDownload?.bytesWritten = written
		activeDownload?.estimatedBytes = total
		activeDownload?.state = .downloading
		activeDownload?.fractionCompleted = total > 0 ? min(1, Double(written) / Double(total)) : nil
	}

	private func finishDownload(id: UUID, region: OfflineMapRegion, removing: OfflineMapRegion?) {
		guard activeDownload?.id == id, downloadLifecycle.end(id: id) else { return }
		if let removing { remove(removing) }
		add(region)
		downloadTask = nil
		activeDownload = nil
		let completion = downloadCompletion
		downloadCompletion = nil
		completion?(region)
	}

	private func failDownload(id: UUID, message: String) {
		guard activeDownload?.id == id, downloadLifecycle.end(id: id) else { return }
		activeDownload?.state = .failed(message)
		downloadTask = nil
		let completion = downloadCompletion
		downloadCompletion = nil
		completion?(nil)
	}

	private func clearDownload(id: UUID) {
		guard activeDownload?.id == id, downloadLifecycle.end(id: id) else { return }
		downloadTask = nil
		activeDownload = nil
		downloadCompletion = nil
	}

	// MARK: - Locations

	/// `Documents/OfflineMaps`, created on first use. `nil` only if the container is unavailable.
	///
	/// tvOS uses Caches instead: Apple TV apps get no durable Documents storage, and anything
	/// large has to be re-downloadable because the system may purge it under storage pressure.
	/// The TV app re-extracts the region around the mesh when that happens.
	func directoryURL() -> URL? {
		#if os(tvOS)
		let searchPath = FileManager.SearchPathDirectory.cachesDirectory
		#else
		let searchPath = FileManager.SearchPathDirectory.documentDirectory
		#endif
		guard let container = FileManager.default.urls(for: searchPath, in: .userDomainMask).first else {
			Logger.services.error("🗺️ [Offline] Could not access the offline maps container")
			return nil
		}
		let dir = container.appendingPathComponent(Self.directoryName, isDirectory: true)
		if !FileManager.default.fileExists(atPath: dir.path) {
			do {
				try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			} catch {
				Logger.services.error("🗺️ [Offline] Failed to create directory: \(error.localizedDescription, privacy: .public)")
				return nil
			}
		}
		return dir
	}

	func fileURL(for region: OfflineMapRegion) -> URL? {
		directoryURL()?.appendingPathComponent(region.fileName)
	}

	/// A fresh, unused archive file URL plus its file name component.
	func newArchiveURL(fileExtension: String = OfflineMapArchiveFormat.pmtiles.fileExtension) -> (url: URL, fileName: String)? {
		guard let dir = directoryURL() else { return nil }
		let name = "\(UUID().uuidString).\(fileExtension)"
		return (dir.appendingPathComponent(name), name)
	}

	private var manifestURL: URL? {
		directoryURL()?.appendingPathComponent(Self.manifestName)
	}

	/// All persisted regions read straight from the manifest, newest first — filesystem-only, so it can
	/// be read off the main actor (e.g. by the offline tile provider at init).
	nonisolated static func persistedRegions() -> [OfflineMapRegion] {
		guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
		let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
		let manifest = dir.appendingPathComponent(manifestName)
		guard let data = try? Data(contentsOf: manifest),
			  let regions = try? JSONDecoder().decode([OfflineMapRegion].self, from: data) else { return [] }
		return regions.sorted(by: { $0.createdDate > $1.createdDate })
	}

	/// Existing archive files paired with their persisted region metadata (newest first).
	nonisolated static func persistedRegionFiles() -> [OfflineMapRegionFile] {
		guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
		let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
		return persistedRegions().compactMap { region in
			let url = dir.appendingPathComponent(region.fileName)
			return FileManager.default.fileExists(atPath: url.path) ? OfflineMapRegionFile(region: region, url: url) : nil
		}
	}

	/// Archive URLs for every downloaded region whose file exists on disk (newest first).
	nonisolated static func allRegionFileURLs() -> [URL] {
		persistedRegionFiles().map(\.url)
	}

	// MARK: - Loading & saving

	/// Loads the manifest once. Prunes entries whose archive file is missing.
	func loadIfNeeded() {
		guard !loaded else { return }
		loaded = true
		load()
	}

	func load() {
		guard let url = manifestURL, FileManager.default.fileExists(atPath: url.path) else {
			regions = []
			return
		}
		do {
			let data = try Data(contentsOf: url)
			let decoded = try JSONDecoder().decode([OfflineMapRegion].self, from: data)
			let existing = decoded.filter { region in
				guard let fileURL = fileURL(for: region) else { return false }
				return FileManager.default.fileExists(atPath: fileURL.path)
			}
			regions = existing.sorted { $0.createdDate > $1.createdDate }
			if existing.count != decoded.count { save() }
		} catch {
			Logger.services.error("🗺️ [Offline] Failed to read manifest: \(error.localizedDescription, privacy: .public)")
			regions = []
		}
	}

	private func save() {
		guard let url = manifestURL else { return }
		do {
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			let data = try encoder.encode(regions)
			try data.write(to: url, options: .atomic)
		} catch {
			Logger.services.error("🗺️ [Offline] Failed to write manifest: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - Mutations

	/// Records a freshly-extracted region. Reads the real file size from disk.
	func add(_ region: OfflineMapRegion) {
		var region = region
		if let fileURL = fileURL(for: region),
		   let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
			region.fileSize = Int64(size)
		}
		regions.removeAll { $0.id == region.id }
		regions.insert(region, at: 0)
		save()
	}

	func remove(_ region: OfflineMapRegion) {
		if let fileURL = fileURL(for: region) {
			try? FileManager.default.removeItem(at: fileURL)
		}
		removeTerrainFiles(for: region)
		regions.removeAll { $0.id == region.id }
		save()
	}

	/// Deletes a region's terrain archives — both the manifest-recorded names and the
	/// derived names, so stray files from an interrupted download are swept too.
	private func removeTerrainFiles(for region: OfflineMapRegion) {
		guard let dir = directoryURL() else { return }
		let derived = Self.terrainFileNames(forBasemap: region.fileName)
		let names = Set([region.terrain?.fileName, region.terrain?.regionalFileName, derived.global, derived.regional].compactMap { $0 })
		for name in names {
			try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
		}
	}

	func rename(_ region: OfflineMapRegion, to name: String) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, let index = regions.firstIndex(where: { $0.id == region.id }) else { return }
		regions[index].name = trimmed
		regions[index].updatedDate = .now
		save()
	}

	// MARK: - Derived

	var totalSize: Int64 {
		regions.reduce(0) { $0 + $1.fileSize + ($1.terrain?.byteCount ?? 0) }
	}

	var formattedTotalSize: String {
		ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
	}
}

// MARK: - Terrain (Mapterhorn elevation extracts)

extension OfflineMapManager {

	/// Mapterhorn's global Terrarium terrain-RGB archive (z0–12).
	static let terrainGlobalArchive = "https://download.mapterhorn.com/planet.pmtiles"
	/// Zoom the global archive tops out at; the recorded max zoom for global-only terrain.
	static let terrainGlobalMaxZoom = 12
	/// Zoom range extracted from a regional high-resolution archive.
	static let terrainRegionalMinZoom = 13
	static let terrainRegionalMaxZoom = 15

	/// The z6 tiles a bounding box intersects. Mapterhorn publishes regional
	/// high-resolution archives named by z6 tile (`6-{x}-{y}.pmtiles`).
	nonisolated static func z6Tiles(intersecting bounds: GeoBounds) -> [(x: UInt32, y: UInt32)] {
		let (x0, y0) = PMTilesExtractor.tileXY(lon: bounds.minLon, lat: bounds.maxLat, z: 6) // top-left
		let (x1, y1) = PMTilesExtractor.tileXY(lon: bounds.maxLon, lat: bounds.minLat, z: 6) // bottom-right
		var tiles: [(x: UInt32, y: UInt32)] = []
		for x in min(x0, x1)...max(x0, x1) {
			for y in min(y0, y1)...max(y0, y1) {
				tiles.append((x, y))
			}
		}
		return tiles
	}

	/// Terrain archive file names derived from the region's basemap archive name,
	/// e.g. `"<uuid>.pmtiles"` → `"<uuid>-terrain.pmtiles"` / `"<uuid>-terrain-hi.pmtiles"`.
	nonisolated static func terrainFileNames(forBasemap fileName: String) -> (global: String, regional: String) {
		let stem = (fileName as NSString).deletingPathExtension
		return ("\(stem)-terrain.pmtiles", "\(stem)-terrain-hi.pmtiles")
	}

	/// Downloads Mapterhorn elevation data for an existing region: a global z0–12
	/// extract of the region's bounds, plus a z13–15 extract when a single regional
	/// high-resolution archive covers the area. Failure never touches the basemap —
	/// the region stays usable and terrain can be retried.
	func downloadTerrain(for region: OfflineMapRegion, onCompletion: ((Bool) -> Void)? = nil) {
		loadIfNeeded()
		guard !isBusy,
			  let current = regions.first(where: { $0.id == region.id }),
			  current.terrain == nil,
			  let dir = directoryURL() else {
			onCompletion?(false)
			return
		}
		guard downloadLifecycle.begin(id: current.id) else {
			onCompletion?(false)
			return
		}
		let names = Self.terrainFileNames(forBasemap: current.fileName)
		let globalURL = dir.appendingPathComponent(names.global)
		let regionalURL = dir.appendingPathComponent(names.regional)
		activeDownload = OfflineMapDownloadProgress(
			id: current.id,
			name: String(localized: "Terrain for \(current.name)"),
			state: .preparing,
			fractionCompleted: nil
		)
		if let onCompletion {
			downloadCompletion = { region in onCompletion(region != nil) }
		}

		downloadTask = Task { [weak self] in
			guard let self else { return }
			let extractor = PMTilesExtractor()
			do {
				guard let source = URL(string: Self.terrainGlobalArchive) else { throw PMTilesExtractorError.badHeader }
				let plan = try await extractor.makePlan(
					sourceURL: source, sourceBuild: "Mapterhorn",
					bounds: current.bounds, minZoom: 0, maxZoom: Self.terrainGlobalMaxZoom
				)
				// The basemap limit check ran before terrain existed — re-check the
				// total ceiling with the terrain plan included so terrain can't push
				// storage past the configured maximum.
				let projected = await MainActor.run { self.totalSize } + plan.payloadBytes
				guard projected <= Self.maxTotalBytes else {
					throw OfflineMapError.storageLimit(String(localized: "Terrain would exceed the offline map storage limit."))
				}
				await self.markDownloading(id: current.id, estimatedBytes: plan.payloadBytes)
				try await extractor.extract(plan: plan, to: globalURL) { [weak self] written, total in
					Task { @MainActor in self?.updateProgress(id: current.id, written: written, total: total) }
				}
				let hasValidHeader = await Task.detached(priority: .utility) {
					PMTilesArchive.header(url: globalURL) != nil
				}.value
				guard hasValidHeader else { throw PMTilesExtractorError.badHeader }

				let regionalMaxZoom = try await self.extractRegionalTerrain(
					extractor: extractor, bounds: current.bounds, to: regionalURL
				)
				await self.finishTerrainDownload(
					id: current.id,
					globalName: names.global,
					regionalName: regionalMaxZoom != nil ? names.regional : nil,
					maxZoom: regionalMaxZoom ?? Self.terrainGlobalMaxZoom
				)
			} catch is CancellationError {
				try? FileManager.default.removeItem(at: globalURL)
				try? FileManager.default.removeItem(at: regionalURL)
				await self.clearDownload(id: current.id)
			} catch {
				try? FileManager.default.removeItem(at: globalURL)
				try? FileManager.default.removeItem(at: regionalURL)
				let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
				Logger.services.error("🗺️ [Terrain] Download failed: \(message, privacy: .public)")
				await self.failDownload(id: current.id, message: message)
			}
		}
	}

	/// Attempts the optional high-resolution regional extract. Returns the extract's
	/// max zoom on success, or nil when the bounds span multiple z6 archives, no
	/// archive exists, or the extract fails — global-only terrain is normal, never an
	/// error. Only cancellation propagates.
	private func extractRegionalTerrain(extractor: PMTilesExtractor, bounds: GeoBounds, to destination: URL) async throws -> Int? {
		let tiles = Self.z6Tiles(intersecting: bounds)
		guard tiles.count == 1, let tile = tiles.first,
			  let source = URL(string: "https://download.mapterhorn.com/6-\(tile.x)-\(tile.y).pmtiles"),
			  await extractor.archiveExists(source) else { return nil }
		do {
			let plan = try await extractor.makePlan(
				sourceURL: source, sourceBuild: "Mapterhorn",
				bounds: bounds, minZoom: Self.terrainRegionalMinZoom, maxZoom: Self.terrainRegionalMaxZoom
			)
			// Same storage ceiling as the global extract (the global file is on
			// disk by now, so totalSize already includes it).
			let projected = await MainActor.run { self.totalSize } + plan.payloadBytes
			guard projected <= Self.maxTotalBytes else { return nil }
			try await extractor.extract(plan: plan, to: destination)
			let hasValidHeader = await Task.detached(priority: .utility) {
				PMTilesArchive.header(url: destination) != nil
			}.value
			guard hasValidHeader else {
				try? FileManager.default.removeItem(at: destination)
				return nil
			}
			return plan.maxZoom
		} catch is CancellationError {
			throw CancellationError()
		} catch PMTilesExtractorError.cancelled {
			throw CancellationError()
		} catch {
			try? FileManager.default.removeItem(at: destination)
			Logger.services.info("🗺️ [Terrain] Regional extract skipped: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	/// Records the finished terrain extract on its region and saves the manifest.
	private func finishTerrainDownload(id: UUID, globalName: String, regionalName: String?, maxZoom: Int) {
		guard activeDownload?.id == id, downloadLifecycle.end(id: id) else { return }
		downloadTask = nil
		activeDownload = nil
		let completion = downloadCompletion
		downloadCompletion = nil
		guard let dir = directoryURL() else {
			completion?(nil)
			return
		}
		guard let index = regions.firstIndex(where: { $0.id == id }) else {
			// The region disappeared mid-download; don't leave orphaned archives.
			try? FileManager.default.removeItem(at: dir.appendingPathComponent(globalName))
			if let regionalName {
				try? FileManager.default.removeItem(at: dir.appendingPathComponent(regionalName))
			}
			completion?(nil)
			return
		}
		var byteCount: Int64 = 0
		for name in [globalName, regionalName].compactMap({ $0 }) {
			let url = dir.appendingPathComponent(name)
			if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
				byteCount += Int64(size)
			}
		}
		regions[index].terrain = OfflineMapTerrain(
			fileName: globalName,
			regionalFileName: regionalName,
			byteCount: byteCount,
			downloadedAt: .now,
			maxZoom: maxZoom
		)
		save()
		completion?(regions[index])
	}

	// The TV target compiles this file but not TerrainStore.swift; terrain rendering
	// on tvOS is an explicit follow-on.
	#if !os(tvOS)
	/// A `TerrainSource` for every region with downloaded terrain, resolving file
	/// URLs — the hook map rendering uses to feed `TerrainStore`.
	/// Directory for locally rendered hillshade tiles, wiped whenever the terrain
	/// generation (the set of terrain downloadedAt stamps) changes — a re-download
	/// or region delete invalidates every cached tile. One subdirectory per
	/// appearance so light and dark shading never mix.
	func terrainHillshadeCacheDirectory(dark: Bool) -> URL? {
		guard let root = directoryURL()?.appendingPathComponent("terrain-cache", isDirectory: true) else { return nil }
		let generation = regions
			.compactMap { $0.terrain.map { String(Int($0.downloadedAt.timeIntervalSince1970)) } }
			.sorted()
			.joined(separator: ",")
		let marker = root.appendingPathComponent("generation.txt")
		if (try? String(contentsOf: marker, encoding: .utf8)) != generation {
			try? FileManager.default.removeItem(at: root)
			try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
			try? generation.write(to: marker, atomically: true, encoding: .utf8)
		}
		let sub = root.appendingPathComponent(dark ? "dark" : "light", isDirectory: true)
		try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
		return sub
	}

	func terrainSources() -> [TerrainSource] {
		loadIfNeeded()
		guard let dir = directoryURL() else { return [] }
		return regions.compactMap { region in
			guard let terrain = region.terrain else { return nil }
			let globalURL = dir.appendingPathComponent(terrain.fileName)
			guard FileManager.default.fileExists(atPath: globalURL.path) else { return nil }
			let regionalURL = terrain.regionalFileName
				.map { dir.appendingPathComponent($0) }
				.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
			return TerrainSource(globalURL: globalURL, regionalURL: regionalURL, bounds: region.bounds)
		}
	}
	#endif
}
