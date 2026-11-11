//
//  LookoutSiteCache.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
import Foundation
import OSLog

/// What the fire lookout's summits are found in, as a string to compare: each download's terrain
/// and basemap files that are on disk now, and when its terrain was fetched. Renaming a download
/// doesn't change it. Outside the visionOS-only cache so it can be tested.
enum LookoutSiteCacheKey {
	/// - Parameters:
	///   - terrainFiles: names of the terrain files the summit search reads, the ones on disk.
	///   - basemapFiles: names of the basemap files the peak names are read from, the ones on disk.
	static func maps(in regions: [OfflineMapRegion], terrainFiles: Set<String>, basemapFiles: Set<String>) -> String {
		regions
			.map { region in
				let terrain = region.terrain.flatMap { terrainFiles.contains($0.fileName) ? $0 : nil }
				return [
					region.id.uuidString,
					region.hasBasemap && basemapFiles.contains(region.fileName) ? region.fileName : "",
					region.sourceBuild,
					terrain?.fileName ?? "",
					(terrain?.regionalFiles.map(\.fileName).filter(terrainFiles.contains) ?? []).joined(separator: ","),
					terrain.map { String($0.downloadedAt.timeIntervalSince1970) } ?? ""
				].joined(separator: "|")
			}
			.sorted()
			.joined(separator: "\n")
	}
}

#if os(visionOS)
/// The fire lookout's summits, and the lighthouse's headlands, kept on disk so they're found once
/// per set of downloads rather than each time the cinema opens. They're found again when a download is added, removed or
/// refreshed, since that's what they're found in.
enum LookoutSiteCache {
	/// Bump when a site search or naming changes, so lists found the old way are found again.
	private static let version = 3

	private struct Entry: Codable {
		let version: Int
		let maps: String
		let sites: [LookoutSite]
	}

	/// The sites of `kind` found in `maps`, if they were found before.
	static func sites(for maps: String, kind: LookoutSiteKind = .summit) -> [LookoutSite]? {
		guard let url = fileURL(kind), let data = try? Data(contentsOf: url),
			  let entry = try? JSONDecoder().decode(Entry.self, from: data),
			  entry.version == version, entry.maps == maps else { return nil }
		return entry.sites
	}

	static func store(_ sites: [LookoutSite], for maps: String, kind: LookoutSiteKind = .summit) {
		guard let url = fileURL(kind) else { return }
		do {
			let data = try JSONEncoder().encode(Entry(version: version, maps: maps, sites: sites))
			try data.write(to: url, options: .atomic)
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't keep the lookout summits: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Forgets the kept sites, so the next search runs again.
	static func clear() {
		for kind in LookoutSiteKind.allCases {
			guard let url = fileURL(kind) else { continue }
			try? FileManager.default.removeItem(at: url)
		}
	}

	private static func fileURL(_ kind: LookoutSiteKind) -> URL? {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
			.appendingPathComponent(kind.cacheFileName)
	}
}
#endif
