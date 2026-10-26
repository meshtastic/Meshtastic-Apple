//
//  CoverageBandsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
//  The coverage estimate's signal bands as traced outlines: round where the signal is round,
//  no grid staircase, no overlap between bands, and nothing past the disc edge.

import Foundation
import Testing
@testable import Meshtastic

@Suite("CoverageBands")
struct CoverageBandsTests {

	private typealias Band = (dbm: Double, polygons: [[[[Double]]]])

	private let style = CoverageStyle(colorScale: .mesh, minDBm: -130, maxDBm: -80)
	private var floors: [Double] { (0..<6).map { -130 + 50 / 6 * Double($0) } }

	/// A grid laid out like `LocalCoverage.grid`: the site in the middle, NaN past `radiusKm`.
	private func discGrid(
		radiusKm: Double,
		latitude: Double = 47.6,
		longitude: Double = -122.3,
		resolution: Int = LocalCoverage.defaultGridResolution,
		_ dbm: (_ km: Double, _ x: Int, _ y: Int) -> Double
	) -> CoverageGrid {
		let site = CoverageSite(
			name: "Test", latitude: latitude, longitude: longitude, frequencyMHz: 906.875,
			txPowerDBm: 22, txGainDBi: 2, txHeightMeters: 2, radiusKm: radiusKm
		)
		let latitudeSpan = radiusKm / 111.32
		let longitudeSpan = latitudeSpan / cos(latitude * .pi / 180)
		var values = [Double](repeating: .nan, count: resolution * resolution)
		let last = Double(resolution - 1)
		for y in 0..<resolution {
			for x in 0..<resolution {
				let lat = latitude + latitudeSpan - 2 * latitudeSpan * Double(y) / last
				let lon = longitude - longitudeSpan + 2 * longitudeSpan * Double(x) / last
				let km = LocalCoverage.haversineKm(latitude, longitude, lat, lon)
				if km <= radiusKm { values[y * resolution + x] = dbm(km, x, y) }
			}
		}
		return CoverageGrid(
			site: site, width: resolution, height: resolution,
			north: latitude + latitudeSpan, south: latitude - latitudeSpan,
			east: longitude + longitudeSpan, west: longitude - longitudeSpan, dbm: values
		)
	}

	/// Terrain-like: falling off with distance, with ridges and valleys down to a few cells across.
	private func rugged(radiusKm: Double) -> CoverageGrid {
		discGrid(radiusKm: radiusKm) { km, x, y in
			let fx = Double(x) / 255
			let fy = Double(y) / 255
			let ripple = 7 * sin(fx * 23 + fy * 9) * cos(fy * 17 - fx * 5) + 4 * sin(fx * 61) * sin(fy * 47)
			let detail = 2 * sin(fx * 197 + fy * 31) * cos(fy * 173)
			return -72 - 48 * log10(max(km, 0.2) / 0.2) / log10(radiusKm / 0.2) + ripple + detail
		}
	}

	private func bands(_ geoJSON: String) throws -> [Band] {
		let root = try #require(JSONSerialization.jsonObject(with: Data(geoJSON.utf8)) as? [String: Any])
		let features = try #require(root["features"] as? [[String: Any]])
		return try features.map { feature in
			let properties = try #require(feature["properties"] as? [String: Any])
			let geometry = try #require(feature["geometry"] as? [String: Any])
			let polygons = try #require(geometry["coordinates"] as? [[[[Double]]]])
			return (try #require(properties["dbm"] as? Double), polygons)
		}
	}

	private func contains(_ ring: [[Double]], _ lon: Double, _ lat: Double) -> Bool {
		var inside = false
		var j = ring.count - 1
		for i in ring.indices {
			let a = ring[i]
			let b = ring[j]
			if (a[1] > lat) != (b[1] > lat), lon < (b[0] - a[0]) * (lat - a[1]) / (b[1] - a[1]) + a[0] { inside.toggle() }
			j = i
		}
		return inside
	}

	/// Which bands draw over a point, counting each polygon's holes as open.
	private func bandsHolding(_ bands: [Band], _ lon: Double, _ lat: Double) -> [Double] {
		bands.filter { band in
			band.polygons.contains { polygon in polygon.filter { contains($0, lon, lat) }.count % 2 == 1 }
		}.map(\.dbm)
	}

	/// Shoelace area, km², in a flat projection around the site.
	private func areaKm2(_ ring: [[Double]], around grid: CoverageGrid) -> Double {
		let kmPerLon = 111.32 * cos(grid.site.latitude * .pi / 180)
		var sum = 0.0
		for index in 0..<(ring.count - 1) {
			let a = ring[index]
			let b = ring[index + 1]
			sum += (a[0] * kmPerLon) * (b[1] * 111.32) - (b[0] * kmPerLon) * (a[1] * 111.32)
		}
		return sum / 2
	}

	private func signedArea(_ ring: [[Double]]) -> Double {
		zip(ring, ring.dropFirst()).reduce(0) { $0 + $1.0[0] * $1.1[1] - $1.1[0] * $1.0[1] } / 2
	}

	@Test func aRadialFalloffGivesRoundRings() throws {
		// Linear in distance, so each band is an annulus with known radii.
		let radiusKm = 30.0
		let grid = discGrid(radiusKm: radiusKm) { km, _, _ in -78 - 52 * km / radiusKm }
		let all = try bands(grid.geoJSON(style: style))
		let band = try #require(all.first { abs($0.dbm - floors[2]) < 0.1 })
		let inner = (-78 - (floors[2] + 50 / 6)) / 52 * radiusKm
		let outer = (-78 - floors[2]) / 52 * radiusKm
		let expected = Double.pi * (outer * outer - inner * inner)
		let area = band.polygons.reduce(0) { total, polygon in total + polygon.reduce(0) { $0 + areaKm2($1, around: grid) } }
		#expect(abs(area - expected) / expected < 0.02, "band area \(area) km², annulus \(expected) km²")
		#expect(band.polygons.count == 1)
		#expect(band.polygons.first?.count == 2, "one ring with one hole")

		// Grid cells would make most edges horizontal or vertical. A traced circle has almost none.
		var total = 0.0
		var axisAligned = 0.0
		for ring in band.polygons.joined() {
			for (a, b) in zip(ring, ring.dropFirst()) {
				let dx = (b[0] - a[0]) * cos(grid.site.latitude * .pi / 180)
				let dy = b[1] - a[1]
				let length = hypot(dx, dy)
				let degrees = atan2(abs(dy), abs(dx)) * 180 / .pi
				total += length
				if degrees < 1 || degrees > 89 { axisAligned += length }
			}
		}
		#expect(axisAligned / total < 0.1, "\(Int(axisAligned / total * 100))% of the outline runs along the grid")
	}

	@Test func oneStrongSampleIsASmallBlobOnItsNode() throws {
		let grid = discGrid(radiusKm: 10, resolution: 33) { _, x, y in x == 16 && y == 16 ? -82 : -95 }
		let top = try #require(try bands(grid.geoJSON(style: style)).first { abs($0.dbm - floors[5]) < 0.1 })
		#expect(top.polygons.count == 1)
		let ring = try #require(top.polygons.first?.first)
		let points = ring.dropLast()
		#expect(points.count >= 8, "a smooth outline, not a square: \(points.count) points")
		let lon = points.map { $0[0] }.reduce(0, +) / Double(points.count)
		let lat = points.map { $0[1] }.reduce(0, +) / Double(points.count)
		let cell = grid.longitude(atColumn: 1) - grid.longitude(atColumn: 0)
		#expect(abs(lon - grid.longitude(atColumn: 16)) < cell * 0.05)
		#expect(abs(lat - grid.latitude(atRow: 16)) < cell * 0.05)
		// The crossing sits about half way to each neighbor, well inside the sample's own cell.
		let reach = points.map { hypot(($0[0] - lon) / cell, ($0[1] - lat) / (grid.latitude(atRow: 0) - grid.latitude(atRow: 1))) }
		#expect(reach.max()! < 0.6)
		#expect(reach.min()! > 0.2)
	}

	@Test func bandsTileWithoutOverlap() throws {
		let grid = rugged(radiusKm: 30)
		let all = try bands(grid.geoJSON(style: style))
		var checked = 0
		for y in stride(from: 1, to: grid.height - 1, by: 4) {
			for x in stride(from: 1, to: grid.width - 1, by: 4) {
				let value = grid.at(x, y)
				guard !value.isNaN, !grid.at(x + 1, y).isNaN, !grid.at(x, y + 1).isNaN else { continue }
				// A point between samples falls in at most one band.
				let between = bandsHolding(all, grid.longitude(atColumn: Double(x) + 0.37), grid.latitude(atRow: Double(y) + 0.21))
				#expect(between.count <= 1)
				// A sample clear of a floor sits in its own band.
				guard !floors.contains(where: { abs(value - $0) < 0.5 }) else { continue }
				let expected = floors.last { value >= $0 }.map { [($0 * 10).rounded() / 10] } ?? []
				#expect(bandsHolding(all, grid.longitude(atColumn: Double(x)), grid.latitude(atRow: Double(y))) == expected, "sample \(value) dBm at \(x), \(y)")
				checked += 1
			}
		}
		#expect(checked > 1000)
	}

	@Test func nothingDrawsPastTheDiscEdge() throws {
		let radiusKm = 30.0
		let grid = discGrid(radiusKm: radiusKm) { _, _, _ in -85 }
		let all = try bands(grid.geoJSON(style: style))
		#expect(all.count == 1)
		let site = grid.site
		for step in 0..<72 {
			let bearing = Double(step) * 5
			let outside = LocalCoverage.destination(latitude: site.latitude, longitude: site.longitude, bearing: bearing, distanceKm: radiusKm * 1.01)
			let inside = LocalCoverage.destination(latitude: site.latitude, longitude: site.longitude, bearing: bearing, distanceKm: radiusKm * 0.99)
			#expect(bandsHolding(all, outside.longitude, outside.latitude).isEmpty)
			#expect(bandsHolding(all, inside.longitude, inside.latitude).count == 1)
		}
	}

	@Test func aDiscAboveEveryFloorIsOneBandAtAnyResolution() throws {
		// Every lower band's outer ring is the whole disc, the same ring as the hole the floor above cuts
		// from it, so the band is empty. Matching that pair by float area broke on a large grid, where
		// the reversed ring's area is no longer the exact negative.
		let grid = discGrid(radiusKm: 25, latitude: 0, longitude: 0, resolution: 1536) { _, _, _ in -85 }
		let all = try bands(grid.geoJSON(style: style))
		#expect(all.map(\.dbm) == [(floors[5] * 10).rounded() / 10])
	}

	@Test func aWeakPatchIsAHoleInTheBandAroundIt() throws {
		// Below the lowest floor near the middle: no band draws there, and the band around it has a hole.
		let grid = discGrid(radiusKm: 10, resolution: 65) { km, _, _ in km < 3 ? -140 : -125 }
		let all = try bands(grid.geoJSON(style: style))
		#expect(all.count == 1)
		#expect(bandsHolding(all, grid.site.longitude, grid.site.latitude).isEmpty)
		let polygon = try #require(all.first?.polygons.first)
		try #require(polygon.count == 2)
		#expect(signedArea(polygon[0]) > 0, "outer ring counterclockwise")
		#expect(signedArea(polygon[1]) < 0, "hole clockwise")
	}

	@Test func ringsAreClosedAndWoundForGeoJSON() throws {
		for band in try bands(rugged(radiusKm: 30).geoJSON(style: style)) {
			for polygon in band.polygons {
				for (index, ring) in polygon.enumerated() {
					#expect(ring.count >= 4)
					#expect(ring.first == ring.last)
					#expect(index == 0 ? signedArea(ring) > 0 : signedArea(ring) < 0)
				}
			}
		}
	}

	@Test func aDiscAcrossTheAntimeridianStaysContinuous() throws {
		let grid = discGrid(radiusKm: 20, latitude: -16.8, longitude: 179.95) { km, _, _ in -80 - km * 2 }
		let longitudes = try bands(grid.geoJSON(style: style)).flatMap { $0.polygons.joined().joined().map { $0[0] } }
		#expect(longitudes.max()! > 180)
		#expect(longitudes.min()! > 179)
	}

	@Test func theFileIsSmallerThanTheCellRectangles() throws {
		let grid = rugged(radiusKm: 30)
		let traced = grid.geoJSON(style: style).utf8.count
		let rectangles = rectangleBytes(grid)
		#expect(traced < rectangles / 2, "traced \(traced) bytes, rectangles \(rectangles) bytes")
	}

	/// Bytes the band coordinates took when each band was drawn as merged cell rectangles.
	private func rectangleBytes(_ grid: CoverageGrid) -> Int {
		var rings: [[[[Double]]]] = []
		for (index, lower) in floors.enumerated() {
			let upper = index == floors.count - 1 ? Double.infinity : floors[index + 1]
			var taken = [Bool](repeating: false, count: grid.width * grid.height)
			func inBand(_ x: Int, _ y: Int) -> Bool {
				let value = grid.at(x, y)
				return !value.isNaN && value >= lower && value < upper && !taken[y * grid.width + x]
			}
			for y in 0..<grid.height {
				for x in 0..<grid.width where inBand(x, y) {
					var right = x
					while right + 1 < grid.width, inBand(right + 1, y) { right += 1 }
					var bottom = y
					while bottom + 1 < grid.height, (x...right).allSatisfy({ inBand($0, bottom + 1) }) { bottom += 1 }
					for row in y...bottom { for column in x...right { taken[row * grid.width + column] = true } }
					let west = grid.longitude(atColumn: Double(x) - 0.5)
					let east = grid.longitude(atColumn: Double(right) + 0.5)
					let north = grid.latitude(atRow: Double(y) - 0.5)
					let south = grid.latitude(atRow: Double(bottom) + 0.5)
					rings.append([[[west, north], [east, north], [east, south], [west, south], [west, north]]])
				}
			}
		}
		return (try? JSONSerialization.data(withJSONObject: rings).count) ?? 0
	}
}
