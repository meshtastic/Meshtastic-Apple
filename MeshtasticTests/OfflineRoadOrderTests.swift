//
//  OfflineRoadOrderTests.swift
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

@Suite("Offline basemap road order")
struct OfflineRoadOrderTests {

	private let tile = OfflineVectorTileProvider.TileID(z: 14, x: 2624, y: 5722)
	private var bounds: GeoBounds { GeoBounds.tile(z: tile.z, x: tile.x, y: tile.y) }

	/// A point at fractions of the tile's width east and height north of its south-west corner.
	private func point(_ east: Double, _ north: Double) -> GISTools.Coordinate3D {
		GISTools.Coordinate3D(latitude: bounds.minLat + north * (bounds.maxLat - bounds.minLat), longitude: bounds.minLon + east * (bounds.maxLon - bounds.minLon))
	}

	private func road(from: Double, to: Double, north: Double, id: UInt, _ properties: [String: Sendable]) throws -> GISTools.Feature {
		let made: GISTools.LineString? = GISTools.LineString([point(from, north), point(to, north)])
		return GISTools.Feature(try #require(made), id: .uint(.init(id)), properties: properties)
	}

	private func build() throws -> [OfflineMapPolyline] {
		var vector = try #require(VectorTile(x: tile.x, y: tile.y, z: tile.z))
		let primary: [String: Sendable] = ["kind": "major_road", "kind_detail": "primary"]
		vector.setFeatures([
			// Listed high rank first, so the output order comes from sort_rank, not input order.
			try road(from: 0.1, to: 0.9, north: 0.1, id: 1, primary.merging(["sort_rank": 400]) { $1 }),
			try road(from: 0.1, to: 0.9, north: 0.2, id: 2, primary.merging(["sort_rank": 300]) { $1 }),
			try road(from: 0.1, to: 0.9, north: 0.3, id: 3, ["kind": "major_road", "kind_detail": "secondary"]),
			// A road that goes into a tunnel: the two pieces meet end to end.
			try road(from: 0.1, to: 0.5, north: 0.5, id: 4, primary),
			try road(from: 0.5, to: 0.9, north: 0.5, id: 5, primary.merging(["is_tunnel": true]) { $1 }),
			// A bridge in an older basemap's terms.
			try road(from: 0.1, to: 0.9, north: 0.7, id: 6, ["pmap:kind": "major_road", "pmap:level": 1])
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
		return OfflineVectorTileProvider.build(source: source, bounds: bounds, tiles: [tile], minFillMeters: 0, minRoadMeters: 0).polylines
	}

	@Test func secondaryAndTertiaryAreMediumRoads() {
		#expect(OfflineVectorTileProvider.roadRole(kind: "major_road", kindDetail: "secondary") == .mediumRoad)
		#expect(OfflineVectorTileProvider.roadRole(kind: "major_road", kindDetail: "tertiary") == .mediumRoad)
		#expect(OfflineVectorTileProvider.roadRole(kind: "major_road", kindDetail: "primary") == .majorRoad)
		#expect(OfflineVectorTileProvider.roadRole(kind: "medium_road", kindDetail: nil) == .mediumRoad)
	}

	@Test func structureComesFromFlagsOrTheOlderLevel() {
		#expect(OfflineVectorTileProvider.roadStructure(["is_tunnel": true]) == .tunnel)
		#expect(OfflineVectorTileProvider.roadStructure(["is_bridge": Int64(1)]) == .bridge)
		#expect(OfflineVectorTileProvider.roadStructure(["is_bridge": false]) == .surface)
		#expect(OfflineVectorTileProvider.roadStructure(["pmap:level": -1.0]) == .tunnel)
		#expect(OfflineVectorTileProvider.roadStructure(["pmap:level": Int64(1)]) == .bridge)
		#expect(OfflineVectorTileProvider.roadStructure([:]) == .surface)
	}

	@Test func aTunnelIsNotStitchedToTheRoadLeadingIntoIt() throws {
		let roads = try build()
		#expect(roads.first { $0.id == "majorRoad/4" }?.structure == .surface)
		#expect(roads.first { $0.id == "majorRoad/5" }?.structure == .tunnel)
		#expect(roads.first { $0.id == "majorRoad/6" }?.structure == .bridge)
	}

	@Test func roadsComeOutLowestSortRankFirst() throws {
		let roads = try build()
		let ids = roads.map(\.id)
		let low = try #require(ids.firstIndex(of: "majorRoad/2"))
		let high = try #require(ids.firstIndex(of: "majorRoad/1"))
		#expect(low < high)
		#expect(roads.first { $0.id == "majorRoad/1" }?.sortRank == 400)
		#expect(roads.first { $0.id == "mediumRoad/3" }?.role == .mediumRoad)
	}
}
