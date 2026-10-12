//
//  SpatialHeightGrid.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation

/// Where the spatial map reads elevation from. `TerrainStore` in the app; a synthetic source in tests.
protocol ElevationTileSource: Sendable {
	func elevationTile(z: Int, x: Int, y: Int, margin: Int) async -> ElevationTile?
	func coverage(z: Int, x: Int, y: Int) async -> GeoBounds?
	/// The finest zoom any configured archive carries, nil with no archives.
	func finestDataZoom() async -> Int?
}

extension TerrainStore: ElevationTileSource {}

/// Elevations sampled on a regular lon/lat grid over a box: the ground the terrain mesh is built on.
struct SpatialHeightGrid: Equatable, Sendable {
	/// How many vertices across and down, and which tile zoom to read them from.
	struct Plan: Equatable, Sendable {
		let columns: Int
		let rows: Int
		let samplingZoom: Int
		var triangleCount: Int { 2 * (columns - 1) * (rows - 1) }
	}

	let columns: Int
	let rows: Int
	/// Row-major, north to south, west to east. Meters above sea level.
	let heights: [Float]
	let covered: [Bool]
	/// Lowest covered height after cleaning (meters); 0 with no coverage.
	let baseElevation: Float
	let maxElevation: Float
	var hasAnyTerrain: Bool { covered.contains(true) }

	/// Picks a grid that stays under the triangle budget and does not sample finer than twice the
	/// data resolution (overzoomed tiles are just bilinear upsampling).
	static func plan(frame: SpatialFrame, maxTriangles: Int = 400_000, dataMaxZoom: Int) -> Plan {
		let width = max(frame.widthMeters, 1)
		let depth = max(frame.depthMeters, 1)
		let aspect = width / depth
		let rowsMinusOne = max(1, Int((Double(maxTriangles) / (2 * aspect)).squareRoot()))
		let columnsMinusOne = max(1, Int(aspect * Double(rowsMinusOne)))
		let budgetStep = max(width / Double(columnsMinusOne), depth / Double(rowsMinusOne))
		let dataStep = 40_075_016.686 * cos(frame.centerLatitude * .pi / 180) / Double(1 << dataMaxZoom) / Double(TerrainStore.tileSize)
		let step = max(budgetStep, dataStep / 2)
		let columns = max(2, Int(width / step) + 1)
		let rows = max(2, Int(depth / step) + 1)
		let pixel = TerrainStore.tilePixel(latitude: frame.centerLatitude, longitude: frame.centerLongitude, z: 8, size: TerrainStore.tileSize)
		var zoom = 8
		while zoom < min(dataMaxZoom + 2, 16) {
			let y = pixel.y << (zoom - 8)
			if TerrainStore.metersPerSample(z: zoom, y: y, size: TerrainStore.tileSize) <= step { break }
			zoom += 1
		}
		return Plan(columns: columns, rows: rows, samplingZoom: zoom)
	}

	/// Reads every vertex through the tiles at the plan's zoom, one tile fetch per tile. Vertices
	/// outside the downloaded coverage are uncovered; the caller cleans and fills them.
	static func sample(frame: SpatialFrame, plan: Plan, source: any ElevationTileSource) async throws -> SpatialHeightGrid {
		let size = TerrainStore.tileSize
		let z = plan.samplingZoom
		let bounds = frame.bounds
		let longitudes = (0..<plan.columns).map { bounds.minLon + (bounds.maxLon - bounds.minLon) * Double($0) / Double(plan.columns - 1) }
		let latitudes = (0..<plan.rows).map { bounds.maxLat - (bounds.maxLat - bounds.minLat) * Double($0) / Double(plan.rows - 1) }
		// tilePixel is separable: x/px depend on longitude only, y/py on latitude only.
		let columnPixels = longitudes.map { TerrainStore.tilePixel(latitude: frame.centerLatitude, longitude: $0, z: z, size: size) }
		let rowPixels = latitudes.map { TerrainStore.tilePixel(latitude: $0, longitude: frame.centerLongitude, z: z, size: size) }

		var heights = [Float](repeating: 0, count: plan.columns * plan.rows)
		var covered = [Bool](repeating: false, count: plan.columns * plan.rows)
		struct Key: Hashable { let x: Int; let y: Int }
		var tiles: [Key: (tile: ElevationTile, coverage: GeoBounds)?] = [:]
		var currentTileRow = -1
		for (j, row) in rowPixels.enumerated() {
			if row.y != currentTileRow {
				tiles.removeAll(keepingCapacity: true)
				currentTileRow = row.y
				try Task.checkCancellation()
			}
			for (i, column) in columnPixels.enumerated() {
				let key = Key(x: column.x, y: row.y)
				let entry: (tile: ElevationTile, coverage: GeoBounds)?
				if let cached = tiles[key] {
					entry = cached
				} else {
					if let coverage = await source.coverage(z: z, x: column.x, y: row.y),
					   let tile = await source.elevationTile(z: z, x: column.x, y: row.y, margin: 1) {
						entry = (tile, coverage)
					} else {
						entry = nil
					}
					tiles[key] = entry
				}
				guard let entry, entry.coverage.contains(CLLocationCoordinate2D(latitude: latitudes[j], longitude: longitudes[i])) else { continue }
				let index = j * plan.columns + i
				heights[index] = TerrainStore.sample(entry.tile, px: column.px, py: row.py)
				covered[index] = true
			}
		}
		return SpatialHeightGrid(columns: plan.columns, rows: plan.rows, heights: heights, covered: covered, baseElevation: 0, maxElevation: 0)
	}

	/// Sea clamp, median-of-9 despike (the source data has isolated spikes on water), flat water,
	/// then uncovered cells sit at the lowest covered height with a short feathered slope into it.
	func cleaned(featherCells: Int = 6) -> SpatialHeightGrid {
		let count = columns * rows
		guard count > 0 else { return self }
		var clamped = heights.map { max($0, 0) }
		for index in 0..<count where !covered[index] { clamped[index] = 0 }

		var filtered = clamped
		var window = [Float](repeating: 0, count: 9)
		for j in 0..<rows {
			for i in 0..<columns {
				let index = j * columns + i
				guard covered[index] else { continue }
				var n = 0
				for dj in -1...1 {
					let jj = min(max(j + dj, 0), rows - 1)
					for di in -1...1 {
						let ii = min(max(i + di, 0), columns - 1)
						let neighbor = jj * columns + ii
						window[n] = covered[neighbor] ? clamped[neighbor] : clamped[index]
						n += 1
					}
				}
				let median = Self.medianOfNine(&window)
				filtered[index] = median < 0.5 ? 0 : median
			}
		}

		var base = Float.greatestFiniteMagnitude
		var top: Float = 0
		for index in 0..<count where covered[index] {
			base = min(base, filtered[index])
			top = max(top, filtered[index])
		}
		if base == .greatestFiniteMagnitude { base = 0 }

		// Chamfer distance (in cells) from the nearest uncovered cell, two passes.
		let far = Int.max / 2
		var distance = [Int](repeating: far, count: count)
		for index in 0..<count where !covered[index] { distance[index] = 0 }
		if distance.contains(0), featherCells > 0 {
			for j in 0..<rows {
				for i in 0..<columns {
					let index = j * columns + i
					if i > 0 { distance[index] = min(distance[index], distance[index - 1] + 1) }
					if j > 0 { distance[index] = min(distance[index], distance[index - columns] + 1) }
				}
			}
			for j in stride(from: rows - 1, through: 0, by: -1) {
				for i in stride(from: columns - 1, through: 0, by: -1) {
					let index = j * columns + i
					if i < columns - 1 { distance[index] = min(distance[index], distance[index + 1] + 1) }
					if j < rows - 1 { distance[index] = min(distance[index], distance[index + columns] + 1) }
				}
			}
		}
		for index in 0..<count {
			if !covered[index] {
				filtered[index] = base
			} else if featherCells > 0, distance[index] < featherCells {
				filtered[index] = base + (filtered[index] - base) * Float(distance[index]) / Float(featherCells)
			}
		}
		return SpatialHeightGrid(columns: columns, rows: rows, heights: filtered, covered: covered, baseElevation: base, maxElevation: max(top, base))
	}

	/// The same ground on a grid at least `minimum` vertices across and down, read bilinearly.
	func upsampled(toAtLeast minimum: Int) -> SpatialHeightGrid {
		guard columns < minimum || rows < minimum else { return self }
		let newColumns = max(columns, minimum), newRows = max(rows, minimum)
		var newHeights = [Float](repeating: 0, count: newColumns * newRows)
		var newCovered = [Bool](repeating: false, count: newColumns * newRows)
		for j in 0..<newRows {
			let v = Double(j) / Double(newRows - 1)
			for i in 0..<newColumns {
				let u = Double(i) / Double(newColumns - 1)
				newHeights[j * newColumns + i] = height(u: u, v: v)
				let nearest = Int((v * Double(rows - 1)).rounded()) * columns + Int((u * Double(columns - 1)).rounded())
				newCovered[j * newColumns + i] = covered[nearest]
			}
		}
		return SpatialHeightGrid(columns: newColumns, rows: newRows, heights: newHeights, covered: newCovered, baseElevation: baseElevation, maxElevation: maxElevation)
	}

	/// Bilinear height at a fraction across the grid (0...1 west to east, 0...1 north to south).
	func height(u: Double, v: Double) -> Float {
		let x = min(max(u, 0), 1) * Double(columns - 1)
		let y = min(max(v, 0), 1) * Double(rows - 1)
		let x0 = min(Int(x), columns - 2), y0 = min(Int(y), rows - 2)
		let tx = Float(x - Double(x0)), ty = Float(y - Double(y0))
		let p00 = heights[y0 * columns + x0], p10 = heights[y0 * columns + x0 + 1]
		let p01 = heights[(y0 + 1) * columns + x0], p11 = heights[(y0 + 1) * columns + x0 + 1]
		let top = p00 + (p10 - p00) * tx
		let bottom = p01 + (p11 - p01) * tx
		return top + (bottom - top) * ty
	}

	/// Median of nine values by a fixed comparison network, no sorting allocation per cell.
	static func medianOfNine(_ v: inout [Float]) -> Float {
		@inline(__always) func swap(_ a: Int, _ b: Int) { if v[a] > v[b] { v.swapAt(a, b) } }
		swap(1, 2); swap(4, 5); swap(7, 8); swap(0, 1); swap(3, 4); swap(6, 7)
		swap(1, 2); swap(4, 5); swap(7, 8); swap(0, 3); swap(5, 8); swap(4, 7)
		swap(3, 6); swap(1, 4); swap(2, 5); swap(4, 7); swap(4, 2); swap(6, 4); swap(4, 2)
		return v[4]
	}
}
