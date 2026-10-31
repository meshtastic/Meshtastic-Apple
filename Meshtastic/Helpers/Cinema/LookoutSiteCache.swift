//
//  LookoutSiteCache.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
#if os(visionOS)
import Foundation
import OSLog

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

	/// What the summits are found in: each download's basemap and terrain files, and when the
	/// terrain was fetched. Renaming a download doesn't change it.
	static func maps(in regions: [OfflineMapRegion]) -> String {
		regions
			.map { region in
				[
					region.id.uuidString,
					region.hasBasemap ? region.fileName : "",
					region.sourceBuild,
					region.terrain?.fileName ?? "",
					region.terrain?.regionalFileName ?? "",
					region.terrain.map { String($0.downloadedAt.timeIntervalSince1970) } ?? ""
				].joined(separator: "|")
			}
			.sorted()
			.joined(separator: "\n")
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
