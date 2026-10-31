//
//  LookoutSiteCacheKeyTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import Foundation
import Testing
@testable import Meshtastic

@Suite("Fire lookout saved summits")
struct LookoutSiteCacheKeyTests {

	private let bounds = GeoBounds(minLon: -122.5, minLat: 47.4, maxLon: -122.1, maxLat: 47.8)
	private let id = UUID()
	private let fetched = Date(timeIntervalSince1970: 1_800_000_000)

	private func region(name: String = "Seattle", fetched: Date? = nil, regional: Bool = true) -> OfflineMapRegion {
		OfflineMapRegion(
			id: id, name: name, fileName: "map.pmtiles", bounds: bounds,
			minZoom: 0, maxZoom: 15, fileSize: 1, sourceBuild: "20261030",
			terrain: OfflineMapTerrain(
				fileName: "map-terrain.pmtiles",
				regionalFileName: regional ? "map-terrain-hi.pmtiles" : nil,
				byteCount: 1, downloadedAt: fetched ?? self.fetched, maxZoom: 14
			)
		)
	}

	private let allTerrain: Set<String> = ["map-terrain.pmtiles", "map-terrain-hi.pmtiles"]
	private let allBasemaps: Set<String> = ["map.pmtiles"]

	private func key(_ regions: [OfflineMapRegion], terrain: Set<String>? = nil, basemaps: Set<String>? = nil) -> String {
		LookoutSiteCacheKey.maps(in: regions, terrainFiles: terrain ?? allTerrain, basemapFiles: basemaps ?? allBasemaps)
	}

	@Test("Renaming a download keeps the saved summits")
	func renameKeeps() {
		#expect(key([region()]) == key([region(name: "Home")]))
	}

	@Test("Fresh terrain finds the summits again")
	func refreshChanges() {
		#expect(key([region()]) != key([region(fetched: fetched.addingTimeInterval(60))]))
	}

	@Test("Removing a download finds the summits again")
	func removalChanges() {
		#expect(key([region()]) != key([]))
	}

	@Test("A terrain file that's gone finds the summits again")
	func missingTerrainChanges() {
		#expect(key([region()]) != key([region()], terrain: ["map-terrain.pmtiles"]))
		#expect(key([region()]) != key([region()], terrain: []))
	}

	@Test("A basemap that's gone finds the summits again, since the names come from it")
	func missingBasemapChanges() {
		#expect(key([region()]) != key([region()], basemaps: []))
	}

	@Test("The order downloads are listed in doesn't matter")
	func orderIgnored() {
		let other = OfflineMapRegion(name: "Tacoma", fileName: "other.pmtiles", bounds: bounds, minZoom: 0, maxZoom: 15, fileSize: 1, sourceBuild: "20261030")
		let basemaps: Set<String> = ["map.pmtiles", "other.pmtiles"]
		#expect(key([region(), other], basemaps: basemaps) == key([other, region()], basemaps: basemaps))
	}
}
