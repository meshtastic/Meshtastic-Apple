//
//  SpatialTerrainDownloadTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import Foundation
import Testing
@testable import Meshtastic

@Suite("Spatial map terrain download")
struct SpatialTerrainDownloadTests {
	let box = GeoBounds(minLon: -122.4, minLat: 47.5, maxLon: -122.1, maxLat: 47.7)

	func region(_ bounds: GeoBounds, basemap: Bool = true, terrain: Bool = false) -> OfflineMapRegion {
		OfflineMapRegion(
			name: "Region", fileName: "\(UUID().uuidString).pmtiles", bounds: bounds, minZoom: 0, maxZoom: 13,
			fileSize: 1, sourceBuild: "test", includesBasemap: basemap,
			terrain: terrain ? OfflineMapTerrain(fileName: "t.pmtiles", regionalFileName: nil, byteCount: 1, downloadedAt: .now, maxZoom: 12) : nil
		)
	}

	@Test func nothingNearbyDownloadsANewRegion() {
		let far = region(GeoBounds(minLon: 13, minLat: 52, maxLon: 14, maxLat: 53), terrain: true)
		#expect(SpatialTerrainDownloadPlan.make(box: box, regions: []) == .newRegion)
		#expect(SpatialTerrainDownloadPlan.make(box: box, regions: [far]) == .newRegion)
	}

	@Test func terrainReachingIntoTheBoxEvenPartlyOffersNothing() {
		let partial = region(GeoBounds(minLon: -122.2, minLat: 47.6, maxLon: -121.9, maxLat: 47.8), terrain: true)
		let plan = SpatialTerrainDownloadPlan.make(box: box, regions: [partial])
		#expect(plan == .covered)
		#expect(!plan.canDownload)
	}

	@Test func aBasemapWithoutTerrainGetsTerrainAdded() {
		let basemap = region(GeoBounds(minLon: -122.55, minLat: 47.4, maxLon: -121.9, maxLat: 47.85))
		#expect(SpatialTerrainDownloadPlan.make(box: box, regions: [basemap]) == .addTerrain(regionID: basemap.id))
	}

	@Test func aRegionWithNeitherIsReplaced() {
		let empty = region(GeoBounds(minLon: -122.3, minLat: 47.55, maxLon: -122.2, maxLat: 47.65), basemap: false)
		#expect(SpatialTerrainDownloadPlan.make(box: box, regions: [empty]) == .replace(regionID: empty.id))
		let other = region(GeoBounds(minLon: -122.15, minLat: 47.55, maxLon: -122.05, maxLat: 47.65), basemap: false)
		#expect(SpatialTerrainDownloadPlan.make(box: box, regions: [empty, other]) == .unavailable, "one download cannot replace two regions")
	}

	@Test func touchingEdgesCountAsOverlapping() {
		// The manager refuses a new region whose edge touches an existing one, so the plan must not offer one.
		let touching = region(GeoBounds(minLon: -122.1, minLat: 47.5, maxLon: -121.9, maxLat: 47.7))
		#expect(SpatialTerrainDownloadPlan.make(box: box, regions: [touching]) == .addTerrain(regionID: touching.id))
	}

	@Test func boxSizeInMeters() {
		let size = box.sizeInMeters
		#expect(abs(size.height - 0.2 * 111_320) < 1)
		#expect(abs(size.width - 0.3 * 111_320 * cos(47.6 * .pi / 180)) < 1)
	}
}
