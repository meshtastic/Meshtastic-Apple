// LocalCoverageTests.swift
// MeshtasticTests
//
// The on-device coverage engine: kp1812 predictions over a terrain profile, the polar sweep,
// its resampling onto a grid, and the GeoJSON bands the map draws.

import Testing
import Foundation
@testable import Meshtastic

@Suite("LocalCoverage")
struct LocalCoverageTests {

	private func site(radiusKm: Double = 10, txPowerDBm: Double = 22) -> CoverageSite {
		CoverageSite(
			name: "Test", latitude: 47.6, longitude: -122.3, frequencyMHz: 906.875,
			txPowerDBm: txPowerDBm, txGainDBi: 2, txHeightMeters: 2, radiusKm: radiusKm
		)
	}

	private let flat: @Sendable (Double, Double) -> Double = { _, _ in 100 }

	@Test func signalWeakensWithDistanceOverFlatGround() async throws {
		let polar = try await LocalCoverage.sweepPolar(site: site(), radials: 8, rings: 8, profileStepKm: 0.1, elevation: flat)
		let ring = (0..<polar.rings).map { polar.at(0, $0) }
		#expect(ring.allSatisfy { $0.isFinite })
		#expect(zip(ring, ring.dropFirst()).allSatisfy { $0 >= $1 })
	}

	@Test func flatGroundIsTheSameOnEveryBearing() async throws {
		let polar = try await LocalCoverage.sweepPolar(site: site(), radials: 8, rings: 6, profileStepKm: 0.1, elevation: flat)
		for ring in 0..<polar.rings {
			let values = (0..<polar.radials).map { polar.at($0, ring) }
			#expect((values.max()! - values.min()!) < 0.01)
		}
	}

	@Test func ridgeShadowsTheFarSide() async throws {
		let base = site()
		// A 400 m ridge from 4.5 to 5.5 km north of the site; flat everywhere else.
		let ridged: @Sendable (Double, Double) -> Double = { latitude, _ in
			let northKm = (latitude - base.latitude) * 111.0
			return (4.5...5.5).contains(northKm) ? 400 : 0
		}
		let polar = try await LocalCoverage.sweepPolar(site: base, radials: 8, rings: 8, profileStepKm: 0.1, elevation: ridged)
		let last = polar.rings - 1
		let north = polar.at(0, last)
		let south = polar.at(4, last)
		#expect(north < south, "past the ridge \(north) dBm should be weaker than flat \(south) dBm")
	}

	@Test func morePowerReachesAtLeastAsFar() async throws {
		let weak = try await LocalCoverage.sweepPolar(site: site(txPowerDBm: 10), radials: 8, rings: 6, profileStepKm: 0.1, elevation: flat)
		let strong = try await LocalCoverage.sweepPolar(site: site(txPowerDBm: 30), radials: 8, rings: 6, profileStepKm: 0.1, elevation: flat)
		for index in weak.dbm.indices {
			#expect(abs((strong.dbm[index] - weak.dbm[index]) - 20) < 0.01)
		}
	}

	@Test func receivedPowerMatchesTheITUReference() {
		// The expected value is from the ITU reference implementation, github.com/eeveetza/Py1812 at 6c9061dd (the
		// commit kp1812's own fixtures are pinned to): P1812.bt_loss for 906.875 MHz, p 50%, 10 km of flat 100 m
		// ground at 50 m steps, 1 m clutter, inland zone, tx 2 m, rx 1 m, vertical, DN 45, N0 325, 500 km to the
		// coast, gives Lb 156.4627 dB. Received power is 22 dBm + 2 dBi - Lb.
		let receiverLatitude = 47.6 + 10 / 6371 * 180 / .pi
		let heights = [Double](repeating: 100, count: 201)
		let dbm = LocalCoverage.predict(site: site(), heights: heights, receiverLatitude: receiverLatitude, stepKm: 0.05, end: 200)
		#expect(abs(dbm - -132.4627) < 0.1, "got \(dbm) dBm")
	}

	@Test func aHigherReceiverHearsMore() {
		let receiverLatitude = 47.6 + 10 / 6371 * 180 / .pi
		let heights = [Double](repeating: 100, count: 201)
		var raised = site()
		raised.rxHeightMeters = 10
		let handheld = LocalCoverage.predict(site: site(), heights: heights, receiverLatitude: receiverLatitude, stepKm: 0.05, end: 200)
		let rooftop = LocalCoverage.predict(site: raised, heights: heights, receiverLatitude: receiverLatitude, stepKm: 0.05, end: 200)
		#expect(rooftop > handheld + 3, "handheld \(handheld) dBm, rooftop \(rooftop) dBm")
	}

	@Test func rejectsAFrequencyOutsideP1812() async {
		var outOfRange = site()
		outOfRange.frequencyMHz = 7000
		await #expect(throws: LocalCoverageError.self) {
			_ = try await LocalCoverage.sweepPolar(site: outOfRange, radials: 8, rings: 4, profileStepKm: 0.1, elevation: flat)
		}
	}

	@Test func gridCoversOnlyTheDisc() async throws {
		let polar = try await LocalCoverage.sweepPolar(site: site(), radials: 8, rings: 6, profileStepKm: 0.1, elevation: flat)
		let grid = LocalCoverage.grid(from: polar, resolution: 33)
		#expect(grid.at(0, 0).isNaN)
		#expect(grid.at(32, 32).isNaN)
		#expect(!grid.at(16, 16).isNaN)
		#expect(!grid.at(16, 2).isNaN)
	}

	@Test func geoJSONIsBandedSimplestyle() async throws {
		var named = site()
		named.name = "Hill \"Site\""
		let polar = try await LocalCoverage.sweepPolar(site: named, radials: 8, rings: 8, profileStepKm: 0.1, elevation: flat)
		let text = LocalCoverage.grid(from: polar, resolution: 32).geoJSON(style: CoverageStyle(colorScale: .mesh, minDBm: -130, maxDBm: -80))
		let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
		let properties = try #require(root["properties"] as? [String: Any])
		#expect(properties["generator"] as? String == "meshtastic-kp1812")
		#expect(properties["name"] as? String == "Hill \"Site\"")
		let features = try #require(root["features"] as? [[String: Any]])
		#expect(!features.isEmpty && features.count <= 6)
		for feature in features {
			let geometry = try #require(feature["geometry"] as? [String: Any])
			#expect(geometry["type"] as? String == "MultiPolygon")
			let style = try #require(feature["properties"] as? [String: Any])
			#expect((style["fill"] as? String)?.hasPrefix("#") == true)
			#expect(style["fill-opacity"] as? Double == 0.5)
			let dbm = try #require(style["dbm"] as? Double)
			#expect(style["label"] as? String == String(format: "≥ %.1f dBm", locale: Locale(identifier: "en_US_POSIX"), dbm))
		}
		#expect(CoverageEstimateRunner.boundingBox(fromGeoJSON: text) != nil)
	}

	@Test func paletteEndsMatchThePlanner() {
		#expect(SitePlannerColorScale.mesh.color(at: 0) == "#ff3b30")
		#expect(SitePlannerColorScale.mesh.color(at: 1) == "#34c759")
		#expect(SitePlannerColorScale.plasma.color(at: 0) == "#0d0887")
		#expect(SitePlannerColorScale.cool.color(at: 0.5) == "#8080ff")
	}

	@Test func destinationAndDistanceAgree() {
		let point = LocalCoverage.destination(latitude: 47.6, longitude: -122.3, bearing: 73, distanceKm: 12.5)
		#expect(abs(LocalCoverage.haversineKm(47.6, -122.3, point.latitude, point.longitude) - 12.5) < 0.001)
		#expect(abs(LocalCoverage.bearing(47.6, -122.3, point.latitude, point.longitude) - 73) < 0.01)
	}
}

@Suite("CoverageTerrain")
struct CoverageTerrainTests {

	@Test func wideDiscsStepDownAZoomToFitTheTileBudget() {
		#expect(CoverageTerrainLoader.zoom(latitude: 47.6, longitude: -122.3, radiusKm: 30) == 12)
		let wide = CoverageTerrainLoader.zoom(latitude: 47.6, longitude: -122.3, radiusKm: 150)
		#expect(wide < 12)
		#expect(CoverageTerrainLoader.tileKeys(latitude: 47.6, longitude: -122.3, radiusKm: 150, zoom: wide).count <= CoverageTerrainLoader.maxTiles)
	}

	/// Sites where a box sized from a flat 111.32 km per degree and cos(latitude) left out tiles the sweep reads.
	@Test(arguments: [(60.0, 18.87), (60.0, 25.9), (65.0, 34.78), (72.0, 2.96)])
	func theTileBoxHoldsEveryPointTheSweepReaches(latitude: Double, longitude: Double) {
		let radiusKm = 150.0
		let zoom = CoverageTerrainLoader.zoom(latitude: latitude, longitude: longitude, radiusKm: radiusKm)
		let keys = Set(CoverageTerrainLoader.tileKeys(latitude: latitude, longitude: longitude, radiusKm: radiusKm, zoom: zoom))
		var missing = 0
		for index in 0..<LocalCoverage.defaultRadials {
			let bearing = 360 * Double(index) / Double(LocalCoverage.defaultRadials)
			for distanceKm in stride(from: 0, through: radiusKm, by: 2.5) {
				let point = LocalCoverage.destination(latitude: latitude, longitude: longitude, bearing: bearing, distanceKm: distanceKm)
				let probe = TerrainStore.tilePixel(latitude: point.latitude, longitude: CoverageTerrain.wrapped(point.longitude), z: zoom, size: 256)
				if !keys.contains(CoverageTerrain.TileKey(x: probe.x, y: probe.y)) { missing += 1 }
			}
		}
		#expect(missing == 0)
	}

	@Test func longitudesWrapIntoMinus180To180() {
		#expect(CoverageTerrain.wrapped(181) == -179)
		#expect(CoverageTerrain.wrapped(-181) == 179)
		#expect(CoverageTerrain.wrapped(-122.3) == -122.3)
		#expect(CoverageTerrain.wrapped(540) == -180)
	}

	@Test func aDiscOnTheAntimeridianTakesTilesFromBothEdges() {
		// Taveuni, Fiji sits almost on the antimeridian.
		let keys = CoverageTerrainLoader.tileKeys(latitude: -16.8, longitude: 179.95, radiusKm: 20, zoom: 12)
		let columns = Set(keys.map(\.x))
		#expect(columns.contains(0))
		#expect(columns.contains((1 << 12) - 1))
		#expect(columns.count < 20)
	}

	@Test func aPointPastTheAntimeridianReadsTheWrappedTile() {
		let probe = TerrainStore.tilePixel(latitude: -16.8, longitude: -179.95, z: 12, size: 256)
		let key = CoverageTerrain.TileKey(x: probe.x, y: probe.y)
		let terrain = CoverageTerrain(zoom: 12, tiles: [key: CoverageTerrain.Tile(size: 256, elevations: [Float](repeating: 77, count: 256 * 256))])
		#expect(terrain.elevation(latitude: -16.8, longitude: 180.05) == 77)
	}

	@Test func elevationReadsTheTileUnderTheCoordinateAndSeaIsZero() {
		let probe = TerrainStore.tilePixel(latitude: 47.6, longitude: -122.3, z: 12, size: 256)
		let key = CoverageTerrain.TileKey(x: probe.x, y: probe.y)
		let land = CoverageTerrain(zoom: 12, tiles: [key: CoverageTerrain.Tile(size: 256, elevations: [Float](repeating: 321, count: 256 * 256))])
		#expect(land.elevation(latitude: 47.6, longitude: -122.3) == 321)
		let sea = CoverageTerrain(zoom: 12, tiles: [key: nil])
		#expect(sea.elevation(latitude: 47.6, longitude: -122.3) == 0)
	}
}

@MainActor
@Suite("CoverageEstimateRunner")
struct CoverageEstimateRunnerTests {

	@MainActor
	private final class Probe {
		var importStarted: CheckedContinuation<Void, Never>?
		var removed: [UUID] = []
	}

	private var params: SitePlannerParameters {
		var params = SitePlannerParameters()
		params.latitude = 47.6
		params.longitude = -122.3
		return params
	}

	private let metadata = MapDataMetadata(
		filename: "c.geojson", originalName: "c", uploadDate: Date(), fileSize: 1,
		format: "geojson", license: nil, attribution: nil, overlayCount: 1, isActive: true, source: .sitePlanner
	)

	/// Waits up to two seconds for `condition`, polling.
	private func wait(_ condition: () -> Bool) async throws {
		for _ in 0..<200 where !condition() {
			try await Task.sleep(nanoseconds: 10_000_000)
		}
	}

	@Test func cancellingDuringTheImportDropsTheOverlay() async throws {
		let probe = Probe()
		let saved = metadata
		let runner = CoverageEstimateRunner(
			estimate: { _ in "{}" },
			importOverlay: { _, _, _ in
				await withCheckedContinuation { probe.importStarted = $0 }
				return saved
			},
			removeOverlay: { probe.removed.append($0.id) }
		)
		runner.start(params: params)
		try await wait { probe.importStarted != nil }
		runner.cancel()
		probe.importStarted?.resume()
		try await wait { !probe.removed.isEmpty }
		#expect(probe.removed == [saved.id])
		#expect(runner.state == .idle)
		#expect(runner.importedResult == nil)
	}

	@Test func anImportThatFinishesNormallyIsKept() async throws {
		let probe = Probe()
		let saved = metadata
		let runner = CoverageEstimateRunner(
			estimate: { _ in "{}" },
			importOverlay: { _, _, _ in saved },
			removeOverlay: { probe.removed.append($0.id) }
		)
		runner.start(params: params)
		try await wait { runner.state == .imported }
		#expect(runner.state == .imported)
		#expect(runner.importedResult?.metadata.id == saved.id)
		#expect(probe.removed.isEmpty)
	}

	@Test func cancellingDuringTheImportTurnsThePreviousEstimateBackOn() async throws {
		let directory = "MapDataTests-\(UUID().uuidString)"
		let manager = MapDataManager(directoryName: directory)
		defer {
			if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
				try? FileManager.default.removeItem(at: documents.appendingPathComponent(directory))
			}
		}
		let geoJSON = #"{ "type": "FeatureCollection", "features": [{ "type": "Feature", "geometry": { "type": "Polygon", "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 0]]] }, "properties": {} }] }"#
		let node = SitePlannerCoverageInfo(
			nodeNum: 7, latitude: 47.6, longitude: -122.3, maxRangeKm: 30, txHeightMeters: 2, colorScale: "mesh", bounds: nil
		)
		let previous = try await manager.importFromString(geoJSON, name: "Previous", source: .sitePlanner, coverage: node)
		let probe = Probe()
		let runner = CoverageEstimateRunner(
			estimate: { _ in geoJSON },
			importOverlay: { geoJSON, name, _ in
				let metadata = try await manager.importFromString(geoJSON, name: name, source: .sitePlanner, coverage: node)
				await withCheckedContinuation { probe.importStarted = $0 }
				return metadata
			},
			removeOverlay: { metadata in
				try? await manager.discardImport(metadata)
				probe.removed.append(metadata.id)
			}
		)
		runner.start(params: params, nodeNum: 7)
		try await wait { probe.importStarted != nil }
		#expect(manager.getUploadedFiles().first { $0.id == previous.id }?.isActive == false)
		runner.cancel()
		probe.importStarted?.resume()
		try await wait { !probe.removed.isEmpty }
		let files = manager.getUploadedFiles()
		#expect(files.map(\.id) == [previous.id])
		#expect(files.first?.isActive == true)
	}
}
