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

@MainActor
final class OfflineMapManager: ObservableObject {

	static let shared = OfflineMapManager()

	/// Completed, persisted regions, newest first.
	@Published private(set) var regions: [OfflineMapRegion] = []
	/// The currently downloading region, if any (one at a time).
	@Published var activeDownload: OfflineMapDownloadProgress?

	static let directoryName = "OfflineMaps"
	static let manifestName = "offline_maps.json"
	private var loaded = false
	private var downloadTask: Task<Void, Never>?

	private init() {}

	// MARK: - Downloading

	/// Whether a download is in flight (one region at a time).
	var isDownloading: Bool { activeDownload != nil }

	/// Begins extracting a region in the background, publishing progress to `activeDownload`.
	/// On success the region is persisted and `activeDownload` is cleared.
	func startDownload(name: String, bounds: GeoBounds, detail: OfflineMapDetailLevel, replacing: OfflineMapRegion? = nil) {
		guard activeDownload == nil, let archive = newArchiveURL() else { return }
		let regionID = UUID()
		let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
		let finalName = trimmedName.isEmpty ? String(localized: "Offline Map") : trimmedName
		activeDownload = OfflineMapDownloadProgress(id: regionID, name: finalName, state: .preparing, fractionCompleted: nil)

		downloadTask = Task { [weak self] in
			let extractor = PMTilesExtractor()
			do {
				guard let build = await extractor.latestBuild() else { throw PMTilesExtractorError.noBuildAvailable }
				let plan = try await extractor.makePlan(
					sourceURL: build.url, sourceBuild: build.build,
					bounds: bounds, minZoom: detail.minZoom, maxZoom: detail.maxZoom
				)
				await self?.markDownloading(estimatedBytes: plan.payloadBytes)
				try await extractor.extract(plan: plan, to: archive.url) { written, total in
					Task { @MainActor [weak self] in self?.updateProgress(written: written, total: total) }
				}
				let region = OfflineMapRegion(
					id: regionID, name: finalName, fileName: archive.fileName,
					bounds: plan.bounds, minZoom: plan.minZoom, maxZoom: plan.maxZoom,
					fileSize: 0, sourceBuild: build.build
				)
				await self?.finishDownload(region: region, removing: replacing)
			} catch is CancellationError {
				try? FileManager.default.removeItem(at: archive.url)
				await self?.clearDownload()
			} catch {
				try? FileManager.default.removeItem(at: archive.url)
				let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
				Logger.services.error("🗺️ [Offline] Download failed: \(message, privacy: .public)")
				await self?.failDownload(message: message)
			}
		}
	}

	func cancelDownload() {
		downloadTask?.cancel()
		downloadTask = nil
		activeDownload = nil
	}

	/// Dismisses a failed download banner.
	func dismissDownload() {
		guard case .failed = activeDownload?.state else { return }
		activeDownload = nil
	}

	private func markDownloading(estimatedBytes: Int64) {
		activeDownload?.state = .downloading
		activeDownload?.estimatedBytes = estimatedBytes
		activeDownload?.fractionCompleted = 0
	}

	private func updateProgress(written: Int64, total: Int64) {
		guard activeDownload != nil else { return }
		activeDownload?.bytesWritten = written
		activeDownload?.estimatedBytes = total
		activeDownload?.state = .downloading
		activeDownload?.fractionCompleted = total > 0 ? min(1, Double(written) / Double(total)) : nil
	}

	private func finishDownload(region: OfflineMapRegion, removing: OfflineMapRegion?) {
		if let removing { remove(removing) }
		add(region)
		downloadTask = nil
		activeDownload = nil
	}

	private func failDownload(message: String) {
		activeDownload?.state = .failed(message)
		downloadTask = nil
	}

	private func clearDownload() {
		downloadTask = nil
		activeDownload = nil
	}

	// MARK: - Locations

	/// `Documents/OfflineMaps`, created on first use. `nil` only if Documents is unavailable.
	func directoryURL() -> URL? {
		guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
			Logger.services.error("🗺️ [Offline] Could not access documents directory")
			return nil
		}
		let dir = documents.appendingPathComponent(Self.directoryName, isDirectory: true)
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
	func newArchiveURL() -> (url: URL, fileName: String)? {
		guard let dir = directoryURL() else { return nil }
		let name = "\(UUID().uuidString).pmtiles"
		return (dir.appendingPathComponent(name), name)
	}

	private var manifestURL: URL? {
		directoryURL()?.appendingPathComponent(Self.manifestName)
	}

	/// Newest downloaded region's archive URL — filesystem-only, so it can be read off the
	/// main actor (e.g. by the offline tile provider). Returns `nil` when nothing is downloaded.
	nonisolated static func newestRegionFileURL() -> URL? {
		guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
		let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
		let manifest = dir.appendingPathComponent(manifestName)
		guard let data = try? Data(contentsOf: manifest),
			  let regions = try? JSONDecoder().decode([OfflineMapRegion].self, from: data) else { return nil }
		for region in regions.sorted(by: { $0.createdDate > $1.createdDate }) {
			let url = dir.appendingPathComponent(region.fileName)
			if FileManager.default.fileExists(atPath: url.path) { return url }
		}
		return nil
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
		regions.removeAll { $0.id == region.id }
		save()
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
		regions.reduce(0) { $0 + $1.fileSize }
	}

	var formattedTotalSize: String {
		ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
	}

	/// Archive URLs for every downloaded region, for rendering offline coverage.
	var regionFileURLs: [URL] {
		regions.compactMap { fileURL(for: $0) }
	}
}
