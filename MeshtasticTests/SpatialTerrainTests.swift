//
//  SpatialTerrainTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation
import simd
import Testing
import UIKit
@testable import Meshtastic

/// Elevation from a closure, so the grid and mesh can be checked against known ground.
struct SyntheticElevationSource: ElevationTileSource {
	let coverage: GeoBounds?
	var maxZoom = 12
	let height: @Sendable (_ latitude: Double, _ longitude: Double) -> Float

	private func intersects(z: Int, x: Int, y: Int) -> GeoBounds? {
		guard let coverage else { return nil }
		let tile = TerrainStore.tileBounds(z: z, x: x, y: y)
		guard tile.maxLon > coverage.minLon, tile.minLon < coverage.maxLon,
			  tile.maxLat > coverage.minLat, tile.minLat < coverage.maxLat else { return nil }
		return coverage
	}

	func elevationTile(z: Int, x: Int, y: Int, margin: Int) async -> ElevationTile? {
		guard intersects(z: z, x: x, y: y) != nil else { return nil }
		let size = TerrainStore.tileSize
		let grid = size + 2 * margin
		let n = Double(1 << z)
		var elevations = [Float](repeating: 0, count: grid * grid)
		for gy in 0..<grid {
			let latitude = atan(sinh(.pi * (1 - 2 * (Double(y) + (Double(gy - margin) + 0.5) / Double(size)) / n))) * 180 / .pi
			for gx in 0..<grid {
				let longitude = (Double(x) + (Double(gx - margin) + 0.5) / Double(size)) / n * 360 - 180
				elevations[gy * grid + gx] = height(latitude, longitude)
			}
		}
		return ElevationTile(z: z, x: x, y: y, size: size, margin: margin, elevations: elevations)
	}

	func coverage(z: Int, x: Int, y: Int) async -> GeoBounds? { intersects(z: z, x: x, y: y) }

	func finestDataZoom() async -> Int? { coverage == nil ? nil : maxZoom }
}

@Suite("Spatial terrain")
struct SpatialTerrainTests {
	let seattle = GeoBounds(minLon: -122.45, minLat: 47.55, maxLon: -122.25, maxLat: 47.70)

	@Test func planStaysUnderBudgetAndNearTheData() {
		let frame = SpatialFrame(bounds: seattle)
		let plan = SpatialHeightGrid.plan(frame: frame, maxTriangles: 100_000, dataMaxZoom: 12)
		#expect(plan.triangleCount <= 100_000)
		#expect(plan.columns >= 2 && plan.rows >= 2)
		#expect(plan.samplingZoom <= 14)
		// A tiny box is limited by the data, not the budget.
		let tiny = SpatialFrame(bounds: GeoBounds(minLon: -122.30, minLat: 47.60, maxLon: -122.29, maxLat: 47.61))
		let tinyPlan = SpatialHeightGrid.plan(frame: tiny, maxTriangles: 100_000, dataMaxZoom: 12)
		#expect(tinyPlan.triangleCount < 100_000 / 4)
	}

	@Test func samplingReproducesASlope() async throws {
		let bounds = seattle
		let source = SyntheticElevationSource(coverage: bounds) { latitude, _ in
			Float(100 + (latitude - bounds.minLat) / (bounds.maxLat - bounds.minLat) * 1000)
		}
		let frame = SpatialFrame(bounds: bounds)
		let plan = SpatialHeightGrid.Plan(columns: 21, rows: 31, samplingZoom: 12)
		let grid = try await SpatialHeightGrid.sample(frame: frame, plan: plan, source: source)
		#expect(grid.covered.allSatisfy { $0 })
		// North row is the top of the slope, south row the bottom.
		#expect(abs(grid.heights[0] - 1100) < 2)
		#expect(abs(grid.heights[(plan.rows - 1) * plan.columns] - 100) < 2)
		#expect(abs(grid.heights[15 * plan.columns + 10] - 600) < 2)
	}

	@Test func uncoveredGroundSitsAtTheLowestCoveredHeight() async throws {
		let bounds = seattle
		let west = GeoBounds(minLon: bounds.minLon, minLat: bounds.minLat, maxLon: (bounds.minLon + bounds.maxLon) / 2, maxLat: bounds.maxLat)
		let source = SyntheticElevationSource(coverage: west) { _, _ in 300 }
		let frame = SpatialFrame(bounds: bounds)
		let plan = SpatialHeightGrid.Plan(columns: 41, rows: 11, samplingZoom: 12)
		let grid = try await SpatialHeightGrid.sample(frame: frame, plan: plan, source: source).cleaned(featherCells: 3)
		#expect(grid.hasAnyTerrain)
		#expect(grid.baseElevation == 300)
		#expect(!grid.covered[40], "the east edge is outside the download")
		#expect(grid.heights[40] == 300, "uncovered cells take the base height")
		#expect(grid.covered[0] && grid.heights[0] == 300)
	}

	@Test func cleaningRemovesSpikesAndFlattensWater() {
		let columns = 9, rows = 9
		var heights = [Float](repeating: 0.3, count: columns * rows)
		heights[4 * columns + 4] = 12
		heights[2 * columns + 2] = -20
		let grid = SpatialHeightGrid(columns: columns, rows: rows, heights: heights, covered: [Bool](repeating: true, count: columns * rows), baseElevation: 0, maxElevation: 0)
		let cleaned = grid.cleaned(featherCells: 0)
		#expect(cleaned.heights.allSatisfy { $0 == 0 }, "a lone spike, a negative sample and shallow noise all become flat water")
		#expect(cleaned.baseElevation == 0 && cleaned.maxElevation == 0)

		var step = [Float](repeating: 100, count: columns * rows)
		for j in 0..<rows { for i in 5..<columns { step[j * columns + i] = 150 } }
		let stepped = SpatialHeightGrid(columns: columns, rows: rows, heights: step, covered: [Bool](repeating: true, count: columns * rows), baseElevation: 0, maxElevation: 0).cleaned(featherCells: 0)
		#expect(stepped.heights[4 * columns + 4] == 100 && stepped.heights[4 * columns + 5] == 150, "a real edge survives the median")
		#expect(stepped.baseElevation == 100 && stepped.maxElevation == 150)
	}

	@Test func meshIsAClosedDiskThatFacesUp() {
		let columns = 120, rows = 120
		let heights = (0..<(columns * rows)).map { Float($0 % columns) * 2 }
		let grid = SpatialHeightGrid(columns: columns, rows: rows, heights: heights, covered: [Bool](repeating: true, count: columns * rows), baseElevation: 0, maxElevation: 238)
		let circle = SpatialCircle(latitude: 47.6, longitude: -122.33, radiusMeters: 8_000)
		let transform = SpatialModelTransform(frame: SpatialFrame(bounds: circle.bounds), baseElevation: 0, maxElevation: 238)
		let geometry = SpatialTerrainGeometry(grid: grid, transform: transform, skirtDepth: 0.02)
		let radius = transform.diskRadius
		#expect(abs(radius - 0.5) < 1e-5, "the disk fills the one meter footprint")
		let ring = geometry.skirtRingCount
		#expect(ring > 100)
		#expect(geometry.positions.count == columns * rows + 2 * ring)
		#expect(geometry.indices.count / 3 == geometry.surfaceTriangleCount + 2 * ring)
		#expect(geometry.surfaceTriangleCount < 2 * (columns - 1) * (rows - 1), "cells outside the circle are dropped")
		#expect(geometry.surfaceTriangleCount > Int(Double(2 * (columns - 1) * (rows - 1)) * .pi / 4 * 0.95), "the disk keeps about pi/4 of the grid")
		#expect(geometry.indices.allSatisfy { Int($0) < geometry.positions.count })
		#expect(geometry.normals.count == geometry.positions.count && geometry.textureCoordinates.count == geometry.positions.count)

		// Every vertex is on the disk.
		#expect(geometry.positions.allSatisfy { simd_length(SIMD2($0.x, $0.z)) <= radius + 1e-5 })

		for t in 0..<(geometry.indices.count / 3) {
			let a = geometry.positions[Int(geometry.indices[t * 3])]
			let b = geometry.positions[Int(geometry.indices[t * 3 + 1])]
			let c = geometry.positions[Int(geometry.indices[t * 3 + 2])]
			let normal = simd_cross(b - a, c - a)
			#expect(simd_length(normal) > 1e-9, "triangle \(t) is not degenerate")
			if t < geometry.surfaceTriangleCount {
				#expect(normal.y > 0, "surface triangle \(t) winds counter-clockwise seen from above")
			} else {
				let centroid = (a + b + c) / 3
				#expect(normal.x * centroid.x + normal.z * centroid.z > 0, "skirt triangle \(t) faces outward")
			}
		}

		// The skirt hangs from the surface's own edge: its top edges are exactly the surface edges
		// that only one triangle uses, so there is no gap between them.
		let top = columns * rows
		var surfaceEdgeUses: [SIMD2<UInt32>: Int] = [:]
		for t in 0..<geometry.surfaceTriangleCount {
			for e in 0..<3 {
				let p = geometry.indices[t * 3 + e], q = geometry.indices[t * 3 + (e + 1) % 3]
				surfaceEdgeUses[SIMD2(min(p, q), max(p, q)), default: 0] += 1
			}
		}
		let surfaceEdge = Set(surfaceEdgeUses.filter { $0.value == 1 }.map { $0.key })
		var rimVertex: [SIMD3<Float>: UInt32] = [:]
		for edge in surfaceEdge { for v in [edge.x, edge.y] { rimVertex[geometry.positions[Int(v)]] = v } }
		var skirtTopEdge = Set<SIMD2<UInt32>>()
		for t in stride(from: geometry.surfaceTriangleCount, to: geometry.indices.count / 3, by: 2) {
			let tops = (0..<3).map { geometry.indices[t * 3 + $0] }.filter { geometry.positions[Int($0)].y > -0.02 }
			let mapped = tops.compactMap { rimVertex[geometry.positions[Int($0)]] }
			#expect(mapped.count == 2, "skirt quad \(t) hangs from two surface vertices")
			if mapped.count == 2 { skirtTopEdge.insert(SIMD2(min(mapped[0], mapped[1]), max(mapped[0], mapped[1]))) }
		}
		#expect(skirtTopEdge == surfaceEdge)
		#expect(surfaceEdge.count == ring, "the edge is one closed loop")

		// The skirt ring sits on the circle, ground height on top, normals pointing straight out.
		for k in 0..<ring {
			let p = geometry.positions[top + k], below = geometry.positions[top + ring + k]
			#expect(abs(simd_length(SIMD2(p.x, p.z)) - radius) < 1e-5)
			#expect(below.y == -0.02 && below.x == p.x && below.z == p.z)
			let n = geometry.normals[top + k]
			#expect(abs(n.y) < 1e-6 && simd_dot(SIMD2(n.x, n.z), simd_normalize(SIMD2(p.x, p.z))) > 0.9999)
			#expect(abs(p.y - geometry.groundHeight(at: transform.coordinate(x: p.x, z: p.z))) < 1e-4)
		}

		// Vertices moved onto the edge carry the texture coordinate and height of where they are now.
		var edgeVertices = 0
		for index in 0..<top where abs(simd_length(SIMD2(geometry.positions[index].x, geometry.positions[index].z)) - radius) < 1e-5 {
			edgeVertices += 1
			let p = geometry.positions[index]
			let coordinate = transform.coordinate(x: p.x, z: p.z)
			let fraction = transform.frame.mercatorFraction(latitude: coordinate.latitude, longitude: coordinate.longitude)
			let uv = geometry.textureCoordinates[index]
			#expect(abs(Double(uv.x) - fraction.x) < 1e-4 && abs(Double(uv.y) - (1 - fraction.y)) < 1e-4)
			#expect(abs(p.y - geometry.groundHeight(at: coordinate)) < 1e-4)
		}
		#expect(edgeVertices > 100)

		// The center vertex is untouched: u, v = 0.5 there, and the eastward slope leans the normal west.
		let middle = (rows / 2) * columns + columns / 2
		#expect(geometry.normals[middle].x < 0)
		#expect(abs(geometry.textureCoordinates[middle].x - Float(columns / 2) / Float(columns - 1)) < 1e-6)
	}

	@Test func aCoarseGridStillMakesARoundDisk() {
		let flat = SpatialHeightGrid(columns: 2, rows: 2, heights: [0, 0, 0, 0], covered: [false, false, false, false], baseElevation: 0, maxElevation: 0)
		let circle = SpatialCircle(latitude: 47.6, longitude: -122.33, radiusMeters: 1_000)
		let geometry = SpatialTerrainGeometry(grid: flat, transform: SpatialModelTransform(frame: SpatialFrame(bounds: circle.bounds), baseElevation: 0, maxElevation: 0))
		#expect(geometry.columns == SpatialTerrainGeometry.minimumGridSize && geometry.rows == SpatialTerrainGeometry.minimumGridSize)
		#expect(geometry.surfaceTriangleCount > 10_000)
		// The surface covers the disk: its triangles add up to nearly pi r^2.
		var area: Float = 0
		for t in 0..<geometry.surfaceTriangleCount {
			let a = geometry.positions[Int(geometry.indices[t * 3])]
			let b = geometry.positions[Int(geometry.indices[t * 3 + 1])]
			let c = geometry.positions[Int(geometry.indices[t * 3 + 2])]
			area += simd_length(simd_cross(b - a, c - a)) / 2
		}
		let disk = Float.pi * 0.25
		#expect(abs(area - disk) / disk < 0.002, "surface area \(area) vs the disk's \(disk)")
	}

	@Test func nodesSitOnTheGround() {
		let columns = 3, rows = 3
		let grid = SpatialHeightGrid(columns: columns, rows: rows, heights: [Float](repeating: 500, count: 9), covered: [Bool](repeating: true, count: 9), baseElevation: 500, maxElevation: 500)
		let transform = SpatialModelTransform(frame: SpatialFrame(bounds: seattle), baseElevation: 500, maxElevation: 500)
		let geometry = SpatialTerrainGeometry(grid: grid, transform: transform, skirtDepth: 0)
		let center = CLLocationCoordinate2D(latitude: 47.625, longitude: -122.35)
		#expect(abs(geometry.groundHeight(at: center)) < 1e-6)
		#expect(abs(geometry.surfacePosition(for: center).y) < 1e-6)
		#expect(abs(geometry.surfacePosition(for: center, clearance: 0.01).y - 0.01) < 1e-6)

		let flat = SpatialHeightGrid(columns: 2, rows: 2, heights: [0, 0, 0, 0], covered: [false, false, false, false], baseElevation: 0, maxElevation: 0)
		let flatGeometry = SpatialTerrainGeometry(grid: flat, transform: SpatialModelTransform(frame: SpatialFrame(bounds: seattle), baseElevation: 0, maxElevation: 0), skirtDepth: 0)
		#expect(flatGeometry.surfacePosition(for: center).y == 0)
	}

	@Test func textureSizeFollowsTheBox() {
		let size = SpatialTextureRenderer.pixelSize(for: SpatialFrame(bounds: seattle), maxEdge: 2048)
		#expect(max(size.width, size.height) == 2048)
		#expect(size.height > size.width, "the Seattle box is taller than it is wide once Mercator stretches latitude")
		let crop = SpatialTextureRenderer.cropRect(northWest: CGPoint(x: 10.4, y: 5.6), southEast: CGPoint(x: 510.4, y: 405.6), scale: 2, imageWidth: 1040, imageHeight: 820)
		#expect(crop == CGRect(x: 21, y: 11, width: 1000, height: 800))
	}

	@Test func canvasPointsFollowTheMercatorMapping() {
		let frame = SpatialFrame(bounds: seattle)
		let size = CGSize(width: 200, height: 100)
		let northWest = SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: seattle.maxLat, longitude: seattle.minLon), frame: frame, size: size)
		let southEast = SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: seattle.minLat, longitude: seattle.maxLon), frame: frame, size: size)
		#expect(abs(northWest.x) < 1e-9 && abs(northWest.y - 100) < 1e-9, "north-west is the top-left corner, with y measured from the bottom")
		#expect(abs(southEast.x - 200) < 1e-9 && abs(southEast.y) < 1e-9)
		let middle = SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: frame.latitude(atMercatorFraction: 0.5), longitude: frame.centerLongitude), frame: frame, size: size)
		#expect(abs(middle.x - 100) < 1e-9 && abs(middle.y - 50) < 1e-9)
		let midLatitude = SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: (seattle.minLat + seattle.maxLat) / 2, longitude: seattle.minLon), frame: frame, size: size)
		#expect(midLatitude.y < 50, "the middle latitude sits south of the Mercator middle")
	}

	@Test func waterIsFilledWhereThePolygonIsAndHolesStayLand() throws {
		let frame = SpatialFrame(bounds: seattle)
		let width = 64, height = 64
		let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
											 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		context.clear(CGRect(x: 0, y: 0, width: width, height: height))
		// The north-west quarter of the box, with a hole in it.
		let midLat = frame.latitude(atMercatorFraction: 0.5), midLon = frame.centerLongitude
		let outer = [(seattle.maxLat, seattle.minLon), (seattle.maxLat, midLon), (midLat, midLon), (midLat, seattle.minLon)]
		let holeTop = frame.latitude(atMercatorFraction: 0.2), holeBottom = frame.latitude(atMercatorFraction: 0.3)
		let holeLeft = frame.longitude(atFraction: 0.2), holeRight = frame.longitude(atFraction: 0.3)
		let hole = [(holeTop, holeLeft), (holeTop, holeRight), (holeBottom, holeRight), (holeBottom, holeLeft)]
		let polygon = OfflineMapPolygon(
			id: "lake", role: .water,
			coordinates: outer.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) },
			interiorRings: [hole.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }]
		)
		SpatialTextureRenderer.drawWater([polygon], frame: frame, size: CGSize(width: width, height: height), dark: false, in: context)

		let data = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
		// Rows are stored top-down, so (x, y) here counts from the top-left of the image.
		func pixel(_ x: Int, _ y: Int) -> [Int] {
			let offset = y * context.bytesPerRow + x * 4
			return (0..<4).map { Int(data[offset + $0]) }
		}
		var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		OfflineMapPalette.fill(.water, dark: false)?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		let water = pixel(8, 8)
		#expect(abs(water[0] - Int(red * 255)) <= 2 && abs(water[1] - Int(green * 255)) <= 2 && abs(water[2] - Int(blue * 255)) <= 2 && water[3] == 255)
		#expect(pixel(16, 16)[3] == 0, "the island inside the hole is not painted")
		#expect(pixel(48, 48)[3] == 0, "the south-east quarter is land")
		#expect(pixel(48, 8)[3] == 0 && pixel(8, 48)[3] == 0)
	}

	@Test func offlineWaterWithNoBasemapIsEmpty() {
		#expect(SpatialTextureRenderer.offlineWater(frame: SpatialFrame(bounds: seattle), width: 1024, files: []).isEmpty)
	}

	@Test func contourSpacingFitsTheRelief() {
		let hills = SpatialTerrainContours.intervals(relief: 1500, metric: true)
		#expect(hills.minor == 50 && hills.index == 250)
		let flat = SpatialTerrainContours.intervals(relief: 80, metric: true)
		#expect(flat.minor == 10 && flat.index == 50, "low relief gets the finest spacing")
		let peaks = SpatialTerrainContours.intervals(relief: 4000, metric: true)
		#expect(peaks.minor == 100 && peaks.index == 500)
		#expect(SpatialTerrainContours.intervals(relief: 100_000, metric: true).minor == 1000, "the coarsest step caps the ladder")
		let feet = SpatialTerrainContours.intervals(relief: 1500, metric: false)
		#expect(abs(feet.minor - 200 * 0.3048) < 1e-9 && abs(feet.index - 1000 * 0.3048) < 1e-9)
		for relief in [50.0, 300, 900, 2500, 6000] {
			for metric in [true, false] {
				let intervals = SpatialTerrainContours.intervals(relief: relief, metric: metric)
				#expect(relief / intervals.minor <= 40)
				#expect(abs((intervals.index / intervals.minor) - 5) < 1e-9)
			}
		}
	}

	@Test func contoursOfASlopeLandOnTheRightRows() async throws {
		let bounds = seattle
		let source = SyntheticElevationSource(coverage: bounds) { latitude, _ in
			Float(100 + (latitude - bounds.minLat) / (bounds.maxLat - bounds.minLat) * 1000)
		}
		let frame = SpatialFrame(bounds: bounds)
		let size = CGSize(width: 1000, height: 1000)
		let intervals = ContourIntervals(minor: 100, index: 500)
		let tiles = await SpatialTerrainContours.tiles(frame: frame, width: Int(size.width), dataZoom: 12, intervals: intervals, source: source)
		#expect(!tiles.isEmpty)
		#expect(tiles.allSatisfy { $0.clip.minLon >= bounds.minLon - 1e-9 && $0.clip.maxLat <= bounds.maxLat + 1e-9 }, "lines are clipped to the download")
		var levelsSeen = Set<Int>()
		for tile in tiles {
			for (lines, isIndex) in [(tile.minor, false), (tile.index, true)] {
				for line in lines {
					let start = SpatialTextureRenderer.canvasPoint(line[0], frame: frame, size: size)
					// Which level this line is, from where it starts; then every point must sit on that level's row.
					let elevation = 100 + (line[0].latitude - bounds.minLat) / (bounds.maxLat - bounds.minLat) * 1000
					let level = (elevation / 100).rounded() * 100
					#expect(isIndex == (Int(level) % 500 == 0), "level \(level) is classed as index only on multiples of 500")
					let latitude = bounds.minLat + (level - 100) / 1000 * (bounds.maxLat - bounds.minLat)
					let row = SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: latitude, longitude: bounds.minLon), frame: frame, size: size).y
					#expect(abs(start.y - row) < 2)
					for coordinate in line {
						let point = SpatialTextureRenderer.canvasPoint(coordinate, frame: frame, size: size)
						#expect(abs(point.y - row) < 2, "a contour of an east-west slope runs along one row")
					}
					// Tiles reach past the box, where the synthetic slope keeps going; count only what gets drawn.
					let clip = tile.clip
					if line.contains(where: { $0.longitude > clip.minLon && $0.longitude < clip.maxLon && $0.latitude > clip.minLat && $0.latitude < clip.maxLat }) {
						levelsSeen.insert(Int(level))
					}
				}
			}
		}
		#expect(levelsSeen.isSuperset(of: [200, 300, 400, 500, 600, 700, 800, 900, 1000]))
		#expect(levelsSeen.allSatisfy { (100...1100).contains($0) }, "nothing drawn inside the box lies off the slope")
	}

	@Test func contoursAreStrokedOntoTheTexture() async throws {
		let bounds = seattle
		let source = SyntheticElevationSource(coverage: bounds) { latitude, _ in
			Float(100 + (latitude - bounds.minLat) / (bounds.maxLat - bounds.minLat) * 1000)
		}
		let frame = SpatialFrame(bounds: bounds)
		let width = 256, height = 256
		let blank = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
										   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		blank.setFillColor(UIColor.black.cgColor)
		blank.fill(CGRect(x: 0, y: 0, width: width, height: height))
		let base = try #require(blank.makeImage())
		let tiles = await SpatialTerrainContours.tiles(frame: frame, width: width, dataZoom: 12, intervals: ContourIntervals(minor: 100, index: 500), source: source)
		let image = try #require(SpatialTerrainContours.draw(tiles, over: base, frame: frame, imagery: true))
		let data = try #require(image.dataProvider?.data as Data?)
		// The 500 m index line: image rows count from the top.
		let latitude = bounds.minLat + 0.4 * (bounds.maxLat - bounds.minLat)
		let row = Int((Double(height) - SpatialTextureRenderer.canvasPoint(CLLocationCoordinate2D(latitude: latitude, longitude: bounds.minLon), frame: frame, size: CGSize(width: width, height: height)).y).rounded(.down))
		func brightness(_ x: Int, _ y: Int) -> Int { Int(data[y * image.bytesPerRow + x * 4]) }
		let onLine = (max(0, row - 1)...min(height - 1, row + 1)).map { brightness(width / 2, $0) }.max() ?? 0
		#expect(onLine > 150, "a white index line crosses the slope at 500 m")
		#expect(brightness(width / 2, max(0, row - 10)) < 10, "between levels the image is untouched")
	}
}
