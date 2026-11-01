//
//  OfflineZoomBandTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import CoreLocation
import Foundation
import GISTools
import MVTTools
import Testing

@testable import Meshtastic

@Suite("Offline basemap zoom bands")
struct OfflineZoomBandTests {

	private let tile = OfflineVectorTileProvider.TileID(z: 14, x: 2624, y: 5722)
	private var bounds: GeoBounds { TerrainStore.tileBounds(z: tile.z, x: tile.x, y: tile.y) }

	/// A point at fractions of the tile's width east and height north of its south-west corner.
	private func point(_ east: Double, _ north: Double) -> GISTools.Coordinate3D {
		GISTools.Coordinate3D(latitude: bounds.minLat + north * (bounds.maxLat - bounds.minLat), longitude: bounds.minLon + east * (bounds.maxLon - bounds.minLon))
	}

	private func line(from: Double, to: Double, north: Double, id: UInt, properties: [String: Sendable]) throws -> GISTools.Feature {
		let made: GISTools.LineString? = GISTools.LineString([point(from, north), point(to, north)])
		return GISTools.Feature(try #require(made), id: .uint(.init(id)), properties: properties)
	}

	private func build() throws -> BuildResult {
		var vector = try #require(VectorTile(x: tile.x, y: tile.y, z: tile.z))
		vector.setFeatures([
			try line(from: 0.1, to: 0.9, north: 0.2, id: 1, properties: ["kind": "river", "min_zoom": 8.0]),
			try line(from: 0.1, to: 0.9, north: 0.4, id: 2, properties: ["kind": "stream", "pmap:min_zoom": 13.0])
		], for: "water")
		// Two rail lines that meet end to end, one in each band.
		vector.setFeatures([
			try line(from: 0.1, to: 0.5, north: 0.7, id: 10, properties: ["kind": "rail", "min_zoom": 7.0]),
			try line(from: 0.5, to: 0.9, north: 0.7, id: 11, properties: ["kind": "rail", "min_zoom": 15.0])
		], for: "roads")
		let payload = try #require(vector.data())
		let entries = [PMTilesArchive.Entry(tileID: PMTilesArchive.zxyToTileID(z: UInt8(tile.z), x: UInt32(tile.x), y: UInt32(tile.y)), offset: 0, length: UInt32(payload.count), runLength: 1)]
		let root = PMTilesExtractor.serializeDirectory(entries)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count),
			metadataOffset: UInt64(127 + root.count), metadataLength: 0,
			tileDataOffset: UInt64(127 + root.count), tileDataLength: UInt64(payload.count),
			numTiles: 1, bounds: bounds, minZoom: 14, maxZoom: 14, tileType: .mvt, tileCompression: .none
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try (header + root + payload).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }
		let source = try #require(PMTilesArchive(url: url))
		return OfflineVectorTileProvider.build(source: source, bounds: bounds, tiles: [tile], minFillMeters: 0, minRoadMeters: 0)
	}

	@Test func theBandEndsAtZoomEleven() {
		#expect(OfflineVectorTileProvider.isFar(minZoom: 0))
		#expect(OfflineVectorTileProvider.isFar(minZoom: 11))
		#expect(!OfflineVectorTileProvider.isFar(minZoom: 11.5))
		#expect(!OfflineVectorTileProvider.isFar(minZoom: 14))
	}

	@Test func waterwaysKeepTheirMinZoomIncludingTheOlderKey() throws {
		let byID = Dictionary(uniqueKeysWithValues: try build().polylines.map { ($0.id, $0.minZoom) })
		#expect(byID["river/1"] == 8)
		#expect(byID["river/2"] == 13)
	}

	@Test func linesInDifferentBandsAreNotStitchedTogether() throws {
		let rail = try build().polylines.filter { $0.role == .rail }
		#expect(Set(rail.map(\.id)) == ["rail/10", "rail/11"])
		#expect(rail.first { $0.id == "rail/10" }?.minZoom == 7)
		#expect(rail.first { $0.id == "rail/11" }?.minZoom == 15)
	}
}
