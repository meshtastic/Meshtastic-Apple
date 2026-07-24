//
//  OfflineOverlayBuildPerfTests.swift
//  MeshtasticTests
//
//  Performance evidence for the offline-map-freeze fix (see DIAGNOSIS-offline-maps-freeze.md at the
//  repo root). The fix moved `MeshMapMK`'s offline-basemap overlay construction from one synchronous
//  pass into `MeshMapMK.offlineVectorOverlayGroups`, an `AsyncStream` that yields to the run loop
//  between each role group (earth fill, each polygon-fill role, each road pass, rail/boundary).
//
//  This uses synthetic decode output rather than a real `.pmtiles` archive on purpose: overlay
//  construction only consumes already-decoded `OfflineMapPolygon`/`OfflineMapPolyline` value types
//  (see `OfflineVectorTileProvider.build` in PMTilesMapView.swift), so the fix under test is fully
//  exercised without needing a downloaded region fixture.

import Testing
import MapKit
import CoreLocation
@testable import Meshtastic

// Perf evidence is emitted via a print call (see `chunkedBuildBoundsWorstSpan`), same convention as
// the existing `OfflineVectorPerfTests` benchmark in MapDataModelTests.swift.
// swiftlint:disable disable_print

@MainActor
@Suite("Offline overlay build perf (post-fix)")
struct OfflineOverlayBuildPerfTests {

	/// Seconds as a `Double`, for ratio math the `Duration` API doesn't offer directly.
	private static func seconds(_ duration: Duration) -> Double {
		let parts = duration.components
		return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
	}

	/// Synthetic decode output sized like a dense urban "High detail" (z15) archive's full street
	/// grid -- the same shape of input `rebuildOfflineVectorOverlays` receives from
	/// `OfflineVectorTileProvider` after a real decode, just fabricated instead of PMTiles-derived.
	private static func syntheticDecode(roadSegments: Int, fills: Int) -> (polygons: [OfflineMapPolygon], roads: [OfflineMapPolyline]) {
		func wiggle(_ seed: Int, _ base: Double) -> Double { base + Double(seed % 97) * 0.00001 }

		let fillRoles: [OfflineFeatureRole] = [.park, .green, .water]
		var polygons: [OfflineMapPolygon] = []
		polygons.reserveCapacity(fills)
		for index in 0..<fills {
			let role = fillRoles[index % fillRoles.count]
			let lat = wiggle(index, 47.6)
			let lon = wiggle(index * 7, -122.2)
			polygons.append(OfflineMapPolygon(id: "fill-\(index)", role: role, coordinates: [
				CLLocationCoordinate2D(latitude: lat, longitude: lon),
				CLLocationCoordinate2D(latitude: lat + 0.001, longitude: lon),
				CLLocationCoordinate2D(latitude: lat + 0.001, longitude: lon + 0.001),
				CLLocationCoordinate2D(latitude: lat, longitude: lon + 0.001)
			]))
		}

		// Every road role the palette recognizes, so every casing/fill/line group actually builds.
		let roadRoles: [OfflineFeatureRole] = [.minorRoad, .mediumRoad, .majorRoad, .rail, .boundary]
		var roads: [OfflineMapPolyline] = []
		roads.reserveCapacity(roadSegments)
		for index in 0..<roadSegments {
			let role = roadRoles[index % roadRoles.count]
			let lat = wiggle(index, 47.6)
			let lon = wiggle(index * 13, -122.2)
			roads.append(OfflineMapPolyline(id: "road-\(index)", role: role, coordinates: [
				CLLocationCoordinate2D(latitude: lat, longitude: lon),
				CLLocationCoordinate2D(latitude: lat + 0.0005, longitude: lon + 0.0003),
				CLLocationCoordinate2D(latitude: lat + 0.0009, longitude: lon + 0.0007)
			]))
		}
		return (polygons, roads)
	}

	@Test("chunked build yields once per role group and bounds the worst single main-thread span")
	func chunkedBuildBoundsWorstSpan() async throws {
		let coverageAreas = [GeoBounds(minLon: -122.4, minLat: 47.5, maxLon: -122.0, maxLat: 47.7)]
		let (polygons, roads) = Self.syntheticDecode(roadSegments: 24_000, fills: 3_000)

		let clock = ContinuousClock()
		let start = clock.now
		var chunkStart = start
		var worstChunk = Duration.zero
		var chunkDurations: [Duration] = []
		var overlays: [ClusterMapOverlay] = []

		for await group in MeshMapMK.offlineVectorOverlayGroups(coverageAreas: coverageAreas, polygons: polygons, roads: roads, dark: false) {
			overlays += group
			let now = clock.now
			let chunkDuration = chunkStart.duration(to: now)
			chunkDurations.append(chunkDuration)
			worstChunk = max(worstChunk, chunkDuration)
			chunkStart = now
		}
		let total = start.duration(to: clock.now)

		// 1 earth fill + 3 polygon-fill roles (park/green/water) + 3 road-casing roles (light mode) +
		// 3 road-fill roles + 2 line roles (rail/boundary) = 12 yielded groups for this synthetic input.
		#expect(chunkDurations.count == 12)
		#expect(!overlays.isEmpty)

		// The whole point of the fix: before it, the entire build was ONE synchronous span == `total`.
		// After it, no single yielded chunk should be anywhere near the full build -- the run loop gets
		// `chunkDurations.count - 1` extra chances to service touches (and the force-quit gesture)
		// during a build that used to be one uninterrupted block.
		#expect(worstChunk < total)

		let totalSeconds = Self.seconds(total)
		let worstSeconds = Self.seconds(worstChunk)
		let reduction = worstSeconds > 0 ? totalSeconds / worstSeconds : .infinity
		// Perf evidence for PR review (also printed so it lands in CI/local test logs verbatim).
		// `Duration.formatted()` rounds to whole seconds by default, which hides everything at this
		// scale -- print millisecond precision instead.
		print("""
		OFFLINE-OVERLAY-PERF: \(chunkDurations.count) groups / \(overlays.count) overlays over \
		\(polygons.count) fills + \(roads.count) road segments
		  total build time (== worst-case main-thread block BEFORE this fix): \(String(format: "%.2f ms", totalSeconds * 1000))
		  worst single yielded chunk (== worst-case main-thread block AFTER this fix): \(String(format: "%.2f ms", worstSeconds * 1000))
		  max-single-block reduction: \(String(format: "%.1fx", reduction))
		  per-chunk breakdown (ms): \(chunkDurations.map { String(format: "%.2f", Self.seconds($0) * 1000) }.joined(separator: ", "))
		""")
	}

	@Test("empty/disabled inputs still finish the stream with no groups")
	func emptyInputsProduceNoGroups() async throws {
		var groupCount = 0
		for await _ in MeshMapMK.offlineVectorOverlayGroups(coverageAreas: [], polygons: [], roads: [], dark: false) {
			groupCount += 1
		}
		#expect(groupCount == 0)
	}

	@Test("dark mode skips the light-only road-casing pass (9 groups, not 12)")
	func darkModeSkipsCasingGroups() async throws {
		// `offlineRoadCasingColor` returns nil for every role when `dark == true` ("Casing pass (light
		// mode only)" in MeshMapMK.swift), so the 3 casing groups (minor/medium/major) never yield --
		// leaving earth(1) + fills(3) + road-fill(3) + rail/boundary(2) = 9, not light mode's 12. Pins
		// that role-skip behavior so a regression there (e.g. casing leaking into dark mode, or a real
		// group silently dropping) shows up as a count mismatch instead of passing unnoticed.
		let coverageAreas = [GeoBounds(minLon: -122.4, minLat: 47.5, maxLon: -122.0, maxLat: 47.7)]
		let (polygons, roads) = Self.syntheticDecode(roadSegments: 2_000, fills: 300)

		var groupCount = 0
		var overlays: [ClusterMapOverlay] = []
		for await group in MeshMapMK.offlineVectorOverlayGroups(coverageAreas: coverageAreas, polygons: polygons, roads: roads, dark: true) {
			overlays += group
			groupCount += 1
		}

		#expect(groupCount == 9)
		#expect(!overlays.contains { ($0.id as? String)?.hasPrefix("offline-road-casing-") == true })
	}
}

// swiftlint:enable disable_print
