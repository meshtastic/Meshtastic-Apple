//
//  TerrainElevationLookupTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/16/26.
//

import CoreLocation
import Foundation
import Testing

@testable import Meshtastic

@Suite("Terrain elevation lookup")
struct TerrainElevationLookupTests {

	// MARK: - tilePixel

	@Test func tilePixelRoundTripsIntoTileBounds() {
		let coordinates = [
			CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),  // Seattle
			CLLocationCoordinate2D(latitude: 46.6863, longitude: 7.8632),     // Interlaken
			CLLocationCoordinate2D(latitude: -41.2866, longitude: 174.7756)   // Wellington
		]
		for coordinate in coordinates {
			let pixel = TerrainStore.tilePixel(latitude: coordinate.latitude, longitude: coordinate.longitude, z: 12, size: 256)
			let bounds = TerrainStore.tileBounds(z: 12, x: pixel.x, y: pixel.y)
			#expect(coordinate.longitude >= bounds.minLon && coordinate.longitude <= bounds.maxLon)
			#expect(coordinate.latitude >= bounds.minLat && coordinate.latitude <= bounds.maxLat)
			// Sample-centered pixel positions stay within the tile's grid span.
			#expect(pixel.px >= -0.5 && pixel.px <= 255.5)
			#expect(pixel.py >= -0.5 && pixel.py <= 255.5)
		}
	}

	@Test func tilePixelCentersTheTileMidpoint() {
		// Longitude is linear in Web-Mercator x, so the bounds midpoint must land
		// exactly mid-grid (sample-centered: size/2 - 0.5).
		let bounds = TerrainStore.tileBounds(z: 12, x: 655, y: 1428)
		let midLon = (bounds.minLon + bounds.maxLon) / 2
		let midLat = (bounds.minLat + bounds.maxLat) / 2
		let pixel = TerrainStore.tilePixel(latitude: midLat, longitude: midLon, z: 12, size: 256)
		#expect(pixel.x == 655)
		#expect(pixel.y == 1428)
		#expect(abs(pixel.px - 127.5) < 0.001)
	}

	// MARK: - sample

	private func makeTile(_ elevations: [Float]) -> ElevationTile {
		ElevationTile(z: 12, x: 0, y: 0, size: 2, margin: 0, elevations: elevations)
	}

	@Test func sampleInterpolatesBilinearly() {
		let tile = makeTile([0, 10, 20, 30])
		#expect(TerrainStore.sample(tile, px: 0, py: 0) == 0)
		#expect(TerrainStore.sample(tile, px: 1, py: 0) == 10)
		#expect(TerrainStore.sample(tile, px: 0, py: 1) == 20)
		#expect(TerrainStore.sample(tile, px: 0.5, py: 0.5) == 15)
		#expect(TerrainStore.sample(tile, px: 0.5, py: 0) == 5)
	}

	@Test func sampleClampsOutsideTheGrid() {
		let tile = makeTile([0, 10, 20, 30])
		#expect(TerrainStore.sample(tile, px: -3, py: -3) == 0)
		#expect(TerrainStore.sample(tile, px: 5, py: 5) == 30)
	}

	// MARK: - elevation(at:)

	@Test func elevationIsNilWithoutSources() async {
		let store = TerrainStore()
		let elevation = await store.elevation(at: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321))
		#expect(elevation == nil)
	}
}
