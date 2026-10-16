//
//  SpatialOfflineMapTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Meshtastic

@Suite("Spatial offline map")
struct SpatialOfflineMapTests {
	private let box = GeoBounds(minLon: -122.5, minLat: 47.4, maxLon: -122.1, maxLat: 47.8)

	// MARK: Coverage

	@Test func basemapOverAQuarterHoldingTheCenterCovers() {
		// The north-west quarter and a bit more, reaching just past the center.
		let basemap = GeoBounds(minLon: -123, minLat: 47.58, maxLon: -122.28, maxLat: 48)
		#expect(SpatialOfflineMap.overlapFraction(of: box, with: basemap) >= SpatialOfflineMap.minimumCoverage)
		#expect(SpatialOfflineMap.covers(box, basemaps: [basemap]))
	}

	@Test func smallBasemapAtTheCenterDoesNotCover() {
		// A small town in the middle of a much larger mesh.
		let basemap = GeoBounds(minLon: -122.32, minLat: 47.58, maxLon: -122.28, maxLat: 47.62)
		#expect(!SpatialOfflineMap.covers(box, basemaps: [basemap]))
	}

	@Test func basemapMissingTheCenterDoesNotCover() {
		// The western 45%: a large share, but not under the middle of the map.
		let basemap = GeoBounds(minLon: -123, minLat: 47, maxLon: -122.32, maxLat: 48)
		#expect(SpatialOfflineMap.overlapFraction(of: box, with: basemap) > SpatialOfflineMap.minimumCoverage)
		#expect(!SpatialOfflineMap.covers(box, basemaps: [basemap]))
	}

	@Test func basemapClippingACornerDoesNotCover() {
		let basemap = GeoBounds(minLon: -123, minLat: 47, maxLon: -122.4, maxLat: 47.5)
		#expect(SpatialOfflineMap.overlapFraction(of: box, with: basemap) < SpatialOfflineMap.minimumCoverage)
		#expect(!SpatialOfflineMap.covers(box, basemaps: [basemap]))
	}

	@Test func noBasemapsDoNotCover() {
		#expect(!SpatialOfflineMap.covers(box, basemaps: []))
	}

	@Test func basemapAroundTheBoxIsFullOverlap() {
		let basemap = GeoBounds(minLon: -124, minLat: 46, maxLon: -121, maxLat: 49)
		#expect(abs(SpatialOfflineMap.overlapFraction(of: box, with: basemap) - 1) < 1e-9)
	}

	@Test func terrainOnlyRegionsAreNotBasemaps() {
		var terrainOnly = OfflineMapRegion(name: "Terrain", fileName: "a.pmtiles", bounds: box, minZoom: 0, maxZoom: 12, fileSize: 1, sourceBuild: "x")
		terrainOnly.includesBasemap = false
		let basemap = OfflineMapRegion(name: "Seattle", fileName: "b.pmtiles", bounds: box, minZoom: 0, maxZoom: 15, fileSize: 1, sourceBuild: "x")
		#expect(SpatialOfflineMap.basemapBounds([terrainOnly, basemap]) == [box])
	}

	@Test func importedBasemapsCountOnlyOnceCheckedAsVector() {
		let download = OfflineMapRegion(name: "Seattle", fileName: "a.pmtiles", bounds: box, minZoom: 0, maxZoom: 15, fileSize: 1, sourceBuild: "20260623")
		let imported = OfflineMapRegion(name: "Import", fileName: "b.pmtiles", bounds: box, minZoom: 0, maxZoom: 15, fileSize: 1, sourceBuild: "Imported")
		#expect(SpatialOfflineMap.isVectorBasemap(download, checked: [:]) == true)
		#expect(SpatialOfflineMap.isVectorBasemap(imported, checked: [:]) == nil)
		// Unchecked or raster imports never offer Offline.
		#expect(SpatialOfflineMap.basemapBounds([imported]).isEmpty)
		#expect(SpatialOfflineMap.basemapBounds([imported], checked: [imported.id: false]).isEmpty)
		#expect(SpatialOfflineMap.basemapBounds([imported], checked: [imported.id: true]) == [box])
	}

	// MARK: Layers

	@Test func pickerOffersOfflineOnlyWhenCovered() {
		#expect(SpatialOfflineMap.layers(offlineAvailable: true) == [.standard, .hybrid, .satellite, .offline])
		#expect(SpatialOfflineMap.layers(offlineAvailable: false) == [.standard, .hybrid, .satellite])
	}

	@Test func basemapGenerationOnlyCountsWhenBasemapsAreDrawn() {
		var basemap = OfflineMapRegion(name: "Seattle", fileName: "a.pmtiles", bounds: box, minZoom: 0, maxZoom: 15, fileSize: 1, sourceBuild: "x")
		let before = SpatialOfflineMap.basemapGeneration([basemap], layer: .offline, usedFallback: false)
		#expect(!before.isEmpty)
		#expect(SpatialOfflineMap.basemapGeneration([basemap], layer: .standard, usedFallback: true) == before)
		// Online Apple layers don't rebuild for a basemap change.
		#expect(SpatialOfflineMap.basemapGeneration([basemap], layer: .standard, usedFallback: false).isEmpty)
		// Updating the basemap changes the key.
		basemap.updatedDate = basemap.updatedDate.addingTimeInterval(60)
		#expect(SpatialOfflineMap.basemapGeneration([basemap], layer: .offline, usedFallback: false) != before)
	}

	@Test func storedOfflineBuildsStandardWithoutABasemap() {
		#expect(SpatialOfflineMap.buildLayer(.offline, offlineAvailable: false) == .standard)
		#expect(SpatialOfflineMap.buildLayer(.offline, offlineAvailable: true) == .offline)
		for layer in [MapLayer.standard, .hybrid, .satellite] {
			#expect(SpatialOfflineMap.buildLayer(layer, offlineAvailable: false) == layer)
			#expect(SpatialOfflineMap.buildLayer(layer, offlineAvailable: true) == layer)
		}
	}

	// MARK: Zoom

	@Test func zoomGivesATilePer256To512Texels() {
		// 0.4° of longitude across 2048 texels: 2048 / 256 × 360 / 0.4 = 7200, log2 ≈ 12.8.
		let zoom = SpatialOfflineMap.zoom(bounds: box, width: 2048, minZoom: 0, maxZoom: 15, maxTiles: 1000)
		#expect(zoom == 12)
	}

	@Test func zoomStaysInTheArchiveRange() {
		let small = GeoBounds(minLon: -122.301, minLat: 47.6, maxLon: -122.3, maxLat: 47.601)
		#expect(SpatialOfflineMap.zoom(bounds: small, width: 2048, minZoom: 0, maxZoom: 15) == 15)
		let wide = GeoBounds(minLon: -130, minLat: 40, maxLon: -110, maxLat: 50)
		#expect(SpatialOfflineMap.zoom(bounds: wide, width: 2048, minZoom: 8, maxZoom: 15) == 8)
	}

	@Test func zoomDropsUntilTheTilesFit() {
		let zoom = SpatialOfflineMap.zoom(bounds: box, width: 2048, minZoom: 0, maxZoom: 15, maxTiles: 20)
		#expect(zoom < 12)
		#expect(SpatialOfflineMap.tiles(bounds: box, zoom: zoom).count <= 20)
		#expect(SpatialOfflineMap.tiles(bounds: box, zoom: zoom + 1).count > 20)
	}

	@Test func defaultCapHoldsForATypicalBox() {
		let zoom = SpatialOfflineMap.zoom(bounds: box, width: 2048, minZoom: 0, maxZoom: 15)
		#expect(SpatialOfflineMap.tiles(bounds: box, zoom: zoom).count <= SpatialOfflineMap.maxTiles)
	}

	@Test func tilesInsideADecodedBasemapAreSkipped() {
		let tiles = SpatialOfflineMap.tiles(bounds: box, zoom: 10)
		let world = GeoBounds(minLon: -180, minLat: -85, maxLon: 180, maxLat: 85)
		#expect(SpatialOfflineMap.newTiles(tiles, coverage: world, decoded: []).count == tiles.count)
		#expect(SpatialOfflineMap.newTiles(tiles, coverage: world, decoded: [world]).isEmpty)
		// A decoded basemap over the west half leaves the eastern tiles to decode.
		let west = GeoBounds(minLon: -124, minLat: 46, maxLon: -122.3, maxLat: 49)
		let rest = SpatialOfflineMap.newTiles(tiles, coverage: world, decoded: [west])
		#expect(!rest.isEmpty && rest.count < tiles.count)
		#expect(rest.allSatisfy { TerrainStore.tileBounds(z: $0.z, x: $0.x, y: $0.y).maxLon > -122.3 })
	}

	@Test func tilesCoverTheBox() {
		let tiles = SpatialOfflineMap.tiles(bounds: box, zoom: 10)
		#expect(!tiles.isEmpty)
		#expect(tiles.allSatisfy { $0.z == 10 })
		let tileBounds = tiles.map { TerrainStore.tileBounds(z: $0.z, x: $0.x, y: $0.y) }
		let union = tileBounds.dropFirst().reduce(tileBounds[0]) { $0.union($1) }
		#expect(union.minLon <= box.minLon && union.maxLon >= box.maxLon)
		#expect(union.minLat <= box.minLat && union.maxLat >= box.maxLat)
	}

	// MARK: Styling

	@Test func lightStrokesMatchTheTwoDMap() {
		let strokes = SpatialOfflineMap.strokes(dark: false)
		#expect(strokes.map(\.role) == [.river, .minorRoad, .mediumRoad, .majorRoad, .minorRoad, .mediumRoad, .majorRoad, .rail])
		// Casings come first and are wider than the fills drawn over them.
		#expect(strokes[1].width == OfflineMapPalette.roadCasingWidth(.minorRoad) * SpatialOfflineMap.strokeScale)
		#expect(strokes[6].width == OfflineMapPalette.roadWidth(.majorRoad) * SpatialOfflineMap.strokeScale)
		#expect(strokes[6].color == OfflineMapPalette.roadFill(.majorRoad, dark: false))
		#expect(strokes.last?.dash.isEmpty == false)
	}

	@Test func darkStrokesHaveNoCasing() {
		let strokes = SpatialOfflineMap.strokes(dark: true)
		#expect(strokes.map(\.role) == [.river, .minorRoad, .mediumRoad, .majorRoad, .rail])
		#expect(strokes[3].color == OfflineMapPalette.roadFill(.majorRoad, dark: true))
	}

	@Test func drawPaintsWaterAndRoads() throws {
		let frame = SpatialFrame(bounds: box)
		let size = CGSize(width: 64, height: 64)
		let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
											 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		context.setFillColor(OfflineMapPalette.earth(dark: false).cgColor)
		context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
		// Water over the western half, a major road across the middle of the eastern half.
		let water = OfflineMapPolygon(id: "w", role: .water, coordinates: [
			.init(latitude: 47.4, longitude: -122.5), .init(latitude: 47.8, longitude: -122.5),
			.init(latitude: 47.8, longitude: -122.3), .init(latitude: 47.4, longitude: -122.3)
		])
		let road = OfflineMapPolyline(id: "r", role: .majorRoad, coordinates: [
			.init(latitude: 47.6, longitude: -122.28), .init(latitude: 47.6, longitude: -122.12)
		])
		SpatialOfflineMap.draw(.init(polygons: [water], polylines: [road]), frame: frame, size: size, dark: false, in: context)
		let image = try #require(context.makeImage())
		let pixels = try #require(image.dataProvider?.data as Data?)
		/// Red, green and blue at a pixel.
		func pixel(_ x: Int, _ y: Int) -> [UInt8] {
			let offset = y * image.bytesPerRow + x * 4
			return [pixels[offset], pixels[offset + 1], pixels[offset + 2]]
		}
		// Water is the light blue: blue well above red.
		let west = pixel(10, 32)
		#expect(west[2] > west[0] + 40)
		// The road is white in light mode.
		let roadPixel = pixel(48, 32)
		#expect(roadPixel.allSatisfy { $0 > 250 })
		// Land elsewhere stays the earth color, not white.
		let land = pixel(48, 8)
		#expect(land[2] < 245)
	}
}
