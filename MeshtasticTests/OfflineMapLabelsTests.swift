//
//  OfflineMapLabelsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import CoreLocation
import Foundation
import GISTools
import MapKit
import MVTTools
import Testing

@testable import Meshtastic

@Suite("Offline map place labels")
struct OfflineMapLabelsTests {

	/// A 1° × 1.6° view: each grid cell is 0.2° × 0.2°.
	private let region = MKCoordinateRegion(
		center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
		span: MKCoordinateSpan(latitudeDelta: 1.6, longitudeDelta: 1.0)
	)

	private func label(_ name: String, _ kind: OfflineMapLabel.Kind, lat: Double = 47.6, lon: Double = -122.3, minZoom: Double = 8, rank: Int = 5) -> OfflineMapLabel {
		OfflineMapLabel(name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), kind: kind, minZoom: minZoom, rank: rank)
	}

	@Test func rankedByMinZoomThenPopulationThenKind() {
		let ranked = OfflineMapLabel.ranked([
			label("Lake", .water, minZoom: 8, rank: 0),
			label("Small city", .city, minZoom: 8, rank: 4),
			label("Big town", .town, minZoom: 8, rank: 9),
			label("Town", .town, minZoom: 8, rank: 4),
			label("Capital", .city, minZoom: 6)
		])
		#expect(ranked.map(\.name) == ["Capital", "Big town", "Small city", "Town", "Lake"])
	}

	@Test func aViewAcrossTheAntimeridianKeepsTheFarSide() {
		let pacific = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -17, longitude: 179.8), span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
		let ranked = OfflineMapLabel.ranked([label("West", .town, lat: -17, lon: 179.6), label("East", .town, lat: -17, lon: -179.8)])
		#expect(Set(OfflineMapLabels.visible(ranked, in: pacific, zoom: 10).map(\.name)) == ["West", "East"])
	}

	@Test func aLabelWaitsForItsZoom() {
		let ranked = OfflineMapLabel.ranked([label("City", .city, minZoom: 6), label("Hood", .neighborhood, lon: -122.0, minZoom: 13)])
		#expect(OfflineMapLabels.visible(ranked, in: region, zoom: 10).map(\.name) == ["City"])
		#expect(OfflineMapLabels.visible(ranked, in: region, zoom: 13).map(\.name) == ["City", "Hood"])
	}

	@Test func onlyLabelsInTheViewShow() {
		let ranked = OfflineMapLabel.ranked([label("Here", .city), label("Away", .city, lat: 45.5, lon: -122.7)])
		#expect(OfflineMapLabels.visible(ranked, in: region, zoom: 10).map(\.name) == ["Here"])
	}

	@Test func theMoreImportantNameWinsItsCell() {
		// Both in the same 0.2° cell.
		let ranked = OfflineMapLabel.ranked([label("Town", .town, lat: 47.61, lon: -122.31, rank: 3), label("City", .city, lat: 47.62, lon: -122.32, rank: 8)])
		#expect(OfflineMapLabels.visible(ranked, in: region, zoom: 10).map(\.name) == ["City"])
	}

	@Test func atMostOnePerCell() {
		// A 20 × 20 grid of towns over the view: more than the cells.
		var labels: [OfflineMapLabel] = []
		for i in 0..<20 {
			for j in 0..<20 {
				labels.append(label("T\(i)-\(j)", .town, lat: 46.81 + Double(i) * 0.08, lon: -122.79 + Double(j) * 0.05))
			}
		}
		let shown = OfflineMapLabels.visible(OfflineMapLabel.ranked(labels), in: region, zoom: 10)
		#expect(shown.count == OfflineMapLabels.rows * OfflineMapLabels.columns)
	}

	/// A one-tile archive holding Seattle (a city) and Smallville (a town), written `count` times.
	private func placesArchives(count: Int) throws -> [URL] {
		let tile = OfflineVectorTileProvider.TileID(z: 14, x: 2624, y: 5722)
		let bounds = GeoBounds.tile(z: tile.z, x: tile.x, y: tile.y)
		let middle = GISTools.Coordinate3D(latitude: (bounds.minLat + bounds.maxLat) / 2, longitude: (bounds.minLon + bounds.maxLon) / 2)
		let corner = GISTools.Coordinate3D(latitude: bounds.minLat + 0.1 * (bounds.maxLat - bounds.minLat), longitude: bounds.minLon + 0.1 * (bounds.maxLon - bounds.minLon))
		var vector = try #require(VectorTile(x: tile.x, y: tile.y, z: tile.z))
		vector.setFeatures([
			GISTools.Feature(GISTools.Point(corner), properties: ["kind": "locality", "kind_detail": "town", "name": "Smallville", "min_zoom": 10.0]),
			GISTools.Feature(GISTools.Point(middle), properties: ["kind": "locality", "kind_detail": "city", "name": "Seattle", "min_zoom": 4.0])
		], for: "places")
		let payload = try #require(vector.data())
		let entries = [PMTilesArchive.Entry(tileID: PMTilesArchive.zxyToTileID(z: UInt8(tile.z), x: UInt32(tile.x), y: UInt32(tile.y)), offset: 0, length: UInt32(payload.count), runLength: 1)]
		let root = PMTilesExtractor.serializeDirectory(entries)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count),
			metadataOffset: UInt64(127 + root.count), metadataLength: 0,
			tileDataOffset: UInt64(127 + root.count), tileDataLength: UInt64(payload.count),
			numTiles: 1, bounds: bounds, minZoom: 14, maxZoom: 14, tileType: .mvt, tileCompression: .none
		)
		var urls: [URL] = []
		for _ in 0..<count {
			let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
			try (header + root + payload).write(to: url)
			urls.append(url)
		}
		return urls
	}

	@MainActor
	@Test func providerPublishesRankedLabelsOnceAcrossOverlappingRegions() async throws {
		// Two downloaded regions over the same ground.
		let urls = try placesArchives(count: 2)
		defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

		let provider = OfflineVectorTileProvider(bindings: urls.map { OfflineVectorSourceBinding(url: $0) })
		let before = provider.revision
		provider.updateIfNeeded()
		for _ in 0..<100 where provider.revision == before {
			try await Task.sleep(for: .milliseconds(50))
		}
		#expect(provider.labels.map(\.name) == ["Seattle", "Smallville"])
	}

	@MainActor
	@Test func aDecodeOvertakenByAReloadDoesNotPublish() async throws {
		let urls = try placesArchives(count: 1)
		defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
		let provider = OfflineVectorTileProvider(bindings: urls.map { OfflineVectorSourceBinding(url: $0) })
		provider.updateIfNeeded()
		// The region goes away before the decode finishes.
		provider.reload(bindings: [])
		try await Task.sleep(for: .seconds(1))
		#expect(provider.labels.isEmpty)
		#expect(provider.polygons.isEmpty && provider.roads.isEmpty)
	}
}
