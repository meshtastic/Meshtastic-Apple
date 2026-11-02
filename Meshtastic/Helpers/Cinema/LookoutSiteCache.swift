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
/// The fire lookout's summits, kept on disk so they're found once per set of downloads rather
/// than each time the cinema opens. They're found again when a download is added, removed or
/// refreshed, since that's what they're found in.
enum LookoutSiteCache {
	/// Bump when the summit search or naming changes, so lists found the old way are found again.
	private static let version = 1

	private struct Entry: Codable {
		let version: Int
		let maps: String
		let sites: [LookoutSite]
	}

	/// The summits found in `maps`, if they were found before.
	static func sites(for maps: String) -> [LookoutSite]? {
		guard let url = fileURL(), let data = try? Data(contentsOf: url),
			  let entry = try? JSONDecoder().decode(Entry.self, from: data),
			  entry.version == version, entry.maps == maps else { return nil }
		return entry.sites
	}

	static func store(_ sites: [LookoutSite], for maps: String) {
		guard let url = fileURL() else { return }
		do {
			let data = try JSONEncoder().encode(Entry(version: version, maps: maps, sites: sites))
			try data.write(to: url, options: .atomic)
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't keep the lookout summits: \(error.localizedDescription, privacy: .public)")
		}
	}

	private static func fileURL() -> URL? {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
			.appendingPathComponent("LookoutSites.json")
	}
}
#endif
