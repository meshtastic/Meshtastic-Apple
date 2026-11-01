//
//  OfflineLandCoverTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import CoreLocation
import Foundation
import GISTools
import MVTTools
import simd
import Testing

@testable import Meshtastic

@Suite("Fire lookout land cover")
struct OfflineLandCoverTests {

	private let box = GeoBounds(minLon: -122.0, minLat: 47.0, maxLon: -121.0, maxLat: 48.0)

	private func square(_ west: Double, _ south: Double, _ size: Double) -> [CLLocationCoordinate2D] {
		[(west, south), (west + size, south), (west + size, south + size), (west, south + size)]
			.map { CLLocationCoordinate2D(latitude: $0.1, longitude: $0.0) }
	}

	@Test func kindsMapToCovers() {
		#expect(OfflineLandCover(layer: "landcover", kind: "forest") == .forest)
		#expect(OfflineLandCover(layer: "landcover", kind: "urban_area") == .urban)
		#expect(OfflineLandCover(layer: "landuse", kind: "wood") == .forest)
		#expect(OfflineLandCover(layer: "landuse", kind: "orchard") == .farmland)
		#expect(OfflineLandCover(layer: "water", kind: "lake") == .water)
		#expect(OfflineLandCover(layer: "landuse", kind: "park") == nil)
		#expect(OfflineLandCover(layer: "landuse", kind: nil) == nil)
	}

	@Test func laterAreasPaintOverEarlierOnesAndHolesStayEmpty() throws {
		let areas = [
			OfflineLandArea(cover: .forest, rings: [square(-122.0, 47.0, 1.0), square(-121.9, 47.1, 0.2)]),
			OfflineLandArea(cover: .water, rings: [square(-121.4, 47.4, 0.3)])
		]
		let map = try #require(OfflineLandCoverMap.paint(areas, bounds: box, size: 512))
		#expect(map.cover(latitude: 47.8, longitude: -121.2) == .forest)
		#expect(map.cover(latitude: 47.55, longitude: -121.25) == .water)
		#expect(map.cover(latitude: 47.2, longitude: -121.8) == nil)   // the forest's hole
		#expect(map.cover(latitude: 49.0, longitude: -121.5) == nil)   // outside the box
	}

	@Test func groundTakesItsCoverAndSnowAboveTheSnowLine() {
		let line = LookoutGroundColor.snowLine(latitude: 47)
		#expect(line > 1_900 && line < 2_300)
		#expect(LookoutGroundColor.color(cover: .forest, elevation: 800, latitude: 47, heightFraction: 0.2) == LookoutGroundColor.forest)
		#expect(LookoutGroundColor.color(cover: .forest, elevation: line + 400, latitude: 47, heightFraction: 0.9) == LookoutGroundColor.snow)
		#expect(LookoutGroundColor.color(cover: .water, elevation: line + 400, latitude: 47, heightFraction: 0.9) == LookoutGroundColor.water)
		#expect(LookoutGroundColor.color(cover: .glacier, elevation: 1_500, latitude: 47, heightFraction: 0.5) == LookoutGroundColor.snow)
		// Without cover, height decides, as before.
		#expect(LookoutGroundColor.color(cover: nil, elevation: 0, latitude: 47, heightFraction: 0) == LookoutGroundColor.water)
		#expect(LookoutGroundColor.color(cover: nil, elevation: 500, latitude: 47, heightFraction: 0.3) == LookoutGroundColor.forest)
	}

	@Test func aTileDecodesItsLandCoverAndWaterInLayerOrder() throws {
		let tile = OfflineVectorTileProvider.TileID(z: 10, x: 163, y: 357)
		let bounds = GeoBounds.tile(z: tile.z, x: tile.x, y: tile.y)
		func ring(_ west: Double, _ south: Double, _ east: Double, _ north: Double) -> [GISTools.Coordinate3D] {
			func point(_ e: Double, _ n: Double) -> GISTools.Coordinate3D {
				GISTools.Coordinate3D(latitude: bounds.minLat + n * (bounds.maxLat - bounds.minLat), longitude: bounds.minLon + e * (bounds.maxLon - bounds.minLon))
			}
			return [point(west, south), point(east, south), point(east, north), point(west, north), point(west, south)]
		}
		let forestShape: GISTools.Polygon? = GISTools.Polygon([ring(0.1, 0.1, 0.6, 0.6)])
		let lakeShape: GISTools.Polygon? = GISTools.Polygon([ring(0.3, 0.3, 0.4, 0.4)])
		let parkShape: GISTools.Polygon? = GISTools.Polygon([ring(0.7, 0.7, 0.8, 0.8)])
		var vector = try #require(VectorTile(x: tile.x, y: tile.y, z: tile.z))
		vector.setFeatures([GISTools.Feature(try #require(forestShape), properties: ["kind": "forest"])], for: "landcover")
		vector.setFeatures([GISTools.Feature(try #require(parkShape), properties: ["kind": "park"])], for: "landuse")
		vector.setFeatures([GISTools.Feature(try #require(lakeShape), properties: ["kind": "lake"])], for: "water")
		let payload = try #require(vector.data())
		let entries = [PMTilesArchive.Entry(tileID: PMTilesArchive.zxyToTileID(z: 10, x: 163, y: 357), offset: 0, length: UInt32(payload.count), runLength: 1)]
		let root = PMTilesExtractor.serializeDirectory(entries)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count), metadataOffset: UInt64(127 + root.count), metadataLength: 0,
			tileDataOffset: UInt64(127 + root.count), tileDataLength: UInt64(payload.count), numTiles: 1,
			bounds: bounds, minZoom: 10, maxZoom: 10, tileType: .mvt, tileCompression: .none
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try (header + root + payload).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }
		let source = try #require(PMTilesArchive(url: url))

		let areas = OfflineVectorTileProvider.landCover(tile: tile, source: source, layers: ["landcover", "landuse", "water"])
		#expect(areas.map(\.cover) == [.forest, .water])   // the park says nothing about the ground
	}
}
