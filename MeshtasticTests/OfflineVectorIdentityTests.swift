//
//  OfflineVectorIdentityTests.swift
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

@Suite("Offline basemap feature identity")
struct OfflineVectorIdentityTests {

	/// Two side-by-side z14 tiles over Seattle; the shared edge is tile A's east side.
	private let tileA = OfflineVectorTileProvider.TileID(z: 14, x: 2624, y: 5722)
	private let tileB = OfflineVectorTileProvider.TileID(z: 14, x: 2625, y: 5722)

	private var boundsA: GeoBounds { TerrainStore.tileBounds(z: tileA.z, x: tileA.x, y: tileA.y) }
	private var region: GeoBounds {
		let b = TerrainStore.tileBounds(z: tileB.z, x: tileB.x, y: tileB.y)
		return GeoBounds(minLon: boundsA.minLon, minLat: boundsA.minLat, maxLon: b.maxLon, maxLat: b.maxLat)
	}

	/// A point at fractions of tile A's width east of its west edge and of its height north of
	/// its south edge (past 1 is in tile B).
	private func point(_ east: Double, _ north: Double) -> GISTools.Coordinate3D {
		let a = boundsA
		return GISTools.Coordinate3D(latitude: a.minLat + north * (a.maxLat - a.minLat), longitude: a.minLon + east * (a.maxLon - a.minLon))
	}

	private func ring(_ west: Double, _ south: Double, _ east: Double, _ north: Double) -> [GISTools.Coordinate3D] {
		[point(west, south), point(east, south), point(east, north), point(west, north), point(west, south)]
	}

	private func lake(_ rings: [[GISTools.Coordinate3D]], id: UInt64?) throws -> GISTools.Feature {
		let made: GISTools.Polygon? = GISTools.Polygon(rings)
		let polygon = try #require(made)
		return GISTools.Feature(polygon, id: id.map { .uint(.init($0)) }, properties: ["kind": "lake"])
	}

	/// The archive both tiles are written to, each with a buffer the way Protomaps writes them, so a
	/// feature near the shared edge is in both.
	private func archive() throws -> URL {
		let wholeNearEdge = try lake([ring(0.95, 0.40, 0.98, 0.45)], id: 1001)   // in A, inside B's buffer
		let acrossEdge = try lake([ring(0.97, 0.60, 1.03, 0.65)], id: 1002)      // cut by the edge
		let noID = try lake([ring(0.50, 0.50, 0.55, 0.55)], id: nil)
		// A hole winds the other way from its outer ring; that is how MVT tells them apart.
		let island = try lake([ring(0.10, 0.10, 0.40, 0.40), ring(0.20, 0.20, 0.30, 0.30).reversed()], id: 1003)
		let line: GISTools.LineString? = GISTools.LineString([point(0.5, 0.8), point(0.9, 0.8), point(1.2, 0.8), point(1.5, 0.8)])
		let roadLine = try #require(line)
		let road = GISTools.Feature(roadLine, id: .uint(3001), properties: ["kind": "minor_road"])

		var payloads: [(id: UInt64, data: Data)] = []
		for tile in [tileA, tileB] {
			var vector = try #require(VectorTile(x: tile.x, y: tile.y, z: tile.z))
			vector.setFeatures([wholeNearEdge, acrossEdge, noID, island], for: "water")
			vector.setFeatures([road], for: "roads")
			let data = try #require(vector.data(options: .init(bufferSize: .pixel(16))))
			payloads.append((PMTilesArchive.zxyToTileID(z: UInt8(tile.z), x: UInt32(tile.x), y: UInt32(tile.y)), data))
		}
		payloads.sort { $0.id < $1.id }
		var tileData = Data()
		var entries: [PMTilesArchive.Entry] = []
		for payload in payloads {
			entries.append(.init(tileID: payload.id, offset: UInt64(tileData.count), length: UInt32(payload.data.count), runLength: 1))
			tileData.append(payload.data)
		}
		let root = PMTilesExtractor.serializeDirectory(entries)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count),
			metadataOffset: UInt64(127 + root.count), metadataLength: 0,
			tileDataOffset: UInt64(127 + root.count), tileDataLength: UInt64(tileData.count),
			numTiles: UInt64(entries.count), bounds: region, minZoom: 14, maxZoom: 14,
			tileType: .mvt, tileCompression: .none
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try (header + root + tileData).write(to: url)
		return url
	}

	private func build(_ url: URL) throws -> BuildResult {
		let source = try #require(PMTilesArchive(url: url))
		return OfflineVectorTileProvider.build(source: source, bounds: region, tiles: [tileA, tileB], minFillMeters: 0, minRoadMeters: 0)
	}

	@Test func featureWholeInOneTileIsKeptOnce() throws {
		let url = try archive()
		defer { try? FileManager.default.removeItem(at: url) }
		let ids = try build(url).polygons.map(\.id).filter { $0.hasPrefix("water/1001/") }
		#expect(ids == ["water/1001/0"])
	}

	@Test func featureCutByTheEdgeKeepsEachTilesPiece() throws {
		let url = try archive()
		defer { try? FileManager.default.removeItem(at: url) }
		let ids = try build(url).polygons.map(\.id).filter { $0.hasPrefix("water/1002/") }
		#expect(Set(ids) == ["water/1002/\(tileA.key)/0", "water/1002/\(tileB.key)/0"])
	}

	@Test func featureWithoutAnIDKeepsTheTileCounter() throws {
		let url = try archive()
		defer { try? FileManager.default.removeItem(at: url) }
		let ids = try build(url).polygons.map(\.id)
		#expect(ids.contains { $0.hasPrefix("\(tileA.key)/") })
		#expect(ids.allSatisfy { $0.hasPrefix("water/") || $0.hasPrefix("14/") })
	}

	@Test func roadIDComesFromItsFeature() throws {
		let url = try archive()
		defer { try? FileManager.default.removeItem(at: url) }
		let ids = try build(url).polylines.map(\.id)
		#expect(ids.contains("minorRoad/3001"))
		#expect(ids.allSatisfy { $0.hasPrefix("minorRoad/3001") })
	}

	@Test func rebuildingGivesTheSameIDs() throws {
		let url = try archive()
		defer { try? FileManager.default.removeItem(at: url) }
		let first = try build(url)
		let second = try build(url)
		#expect(first.polygons.map(\.id) == second.polygons.map(\.id))
		#expect(first.polylines.map(\.id) == second.polylines.map(\.id))
		#expect(Set(first.polygons.map(\.id)).count == first.polygons.count)
		#expect(Set(first.polylines.map(\.id)).count == first.polylines.count)
	}

	@MainActor
	@Test func providerKeepsHolesWhenItMergesRegions() async throws {
		let url = try archive()
		defer { try? FileManager.default.removeItem(at: url) }
		let provider = OfflineVectorTileProvider(bindings: [OfflineVectorSourceBinding(url: url)])
		let before = provider.revision
		provider.updateIfNeeded()
		for _ in 0..<100 where provider.revision == before {
			try await Task.sleep(for: .milliseconds(50))
		}
		// The build keeps the hole; the merge into the provider must too.
		let built = try #require(try build(url).polygons.first { $0.id == "water/1003/0" })
		#expect(built.interiorRings.count == 1)
		let island = try #require(provider.polygons.first { $0.id.hasSuffix("water/1003/0") })
		#expect(island.interiorRings.count == 1)
	}
}
