//
//  SpatialTerrainMesh.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation
import simd

/// Scales the local meters frame into the model: the box fits a footprint of about a meter and
/// relief is exaggerated so a tabletop model still reads as hills.
struct SpatialModelTransform: Equatable, Sendable {
	let frame: SpatialFrame
	/// Model units per ground meter.
	let scale: Double
	/// Effective exaggeration after capping to the model height.
	let verticalExaggeration: Double
	/// Meters above sea level that sit at y = 0.
	let baseElevation: Double
	/// x and z extents of the ground in model units.
	let footprint: SIMD2<Float>

	init(frame: SpatialFrame, baseElevation: Double, maxElevation: Double, verticalExaggeration: Double = 1.5, modelSize: SIMD3<Float> = [1, 0.3, 1]) {
		self.frame = frame
		self.baseElevation = baseElevation
		let width = max(frame.widthMeters, 1)
		let depth = max(frame.depthMeters, 1)
		scale = min(Double(modelSize.x) / width, Double(modelSize.z) / depth)
		let relief = max(maxElevation - baseElevation, 0) * scale
		let cap = relief > 0 ? Double(modelSize.y) / relief : verticalExaggeration
		self.verticalExaggeration = max(min(verticalExaggeration, cap), 0.01)
		footprint = SIMD2(Float(width * scale), Float(depth * scale))
	}

	func height(forAltitude altitude: Double) -> Float {
		Float((altitude - baseElevation) * verticalExaggeration * scale)
	}

	func altitude(forHeight y: Float) -> Double {
		Double(y) / (verticalExaggeration * scale) + baseElevation
	}

	func position(_ coordinate: CLLocationCoordinate2D, altitude: Double) -> SIMD3<Float> {
		let meters = frame.localPosition(coordinate, altitude: 0)
		return SIMD3(meters.x * Float(scale), height(forAltitude: altitude), meters.z * Float(scale))
	}

	func coordinate(x: Float, z: Float) -> CLLocationCoordinate2D {
		frame.coordinate(x: x / Float(scale), z: z / Float(scale))
	}
}

/// The terrain mesh plus the height field it was built from, in model units.
struct SpatialTerrainGeometry: Sendable {
	/// RealityKit samples textures with v = 0 at the bottom of the image, so the north edge is v = 1.
	static let flipTextureV = true

	let transform: SpatialModelTransform
	let columns: Int
	let rows: Int
	/// Row-major ground heights in model units (y).
	let groundHeights: [Float]
	let covered: [Bool]
	let hasAnyTerrain: Bool
	let positions: [SIMD3<Float>]
	let normals: [SIMD3<Float>]
	let textureCoordinates: [SIMD2<Float>]
	let indices: [UInt32]
	let surfaceTriangleCount: Int

	init(grid: SpatialHeightGrid, transform: SpatialModelTransform, skirtDepth: Float = 0.02) {
		self.transform = transform
		columns = grid.columns
		rows = grid.rows
		covered = grid.covered
		hasAnyTerrain = grid.hasAnyTerrain
		let frame = transform.frame
		let bounds = frame.bounds
		let count = columns * rows
		var heights = [Float](repeating: 0, count: count)
		var positions = [SIMD3<Float>](repeating: .zero, count: count)
		var uvs = [SIMD2<Float>](repeating: .zero, count: count)
		for j in 0..<rows {
			let latitude = bounds.maxLat - (bounds.maxLat - bounds.minLat) * Double(j) / Double(rows - 1)
			let v = frame.mercatorFraction(latitude: latitude, longitude: bounds.minLon).y
			for i in 0..<columns {
				let longitude = bounds.minLon + (bounds.maxLon - bounds.minLon) * Double(i) / Double(columns - 1)
				let index = j * columns + i
				let y = transform.height(forAltitude: Double(grid.heights[index]))
				heights[index] = y
				positions[index] = transform.position(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: Double(grid.heights[index]))
				let u = Float(i) / Float(columns - 1)
				uvs[index] = SIMD2(u, Float(Self.flipTextureV ? 1 - v : v))
			}
		}
		groundHeights = heights

		// Surface normals from the height field: (-dh/dx, 1, -dh/dz), one-sided at the edges.
		let dx = transform.footprint.x / Float(columns - 1)
		let dz = transform.footprint.y / Float(rows - 1)
		var normals = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: count)
		for j in 0..<rows {
			for i in 0..<columns {
				let left = heights[j * columns + max(i - 1, 0)]
				let right = heights[j * columns + min(i + 1, columns - 1)]
				let north = heights[max(j - 1, 0) * columns + i]
				let south = heights[min(j + 1, rows - 1) * columns + i]
				let spanX = Float(min(i + 1, columns - 1) - max(i - 1, 0)) * dx
				let spanZ = Float(min(j + 1, rows - 1) - max(j - 1, 0)) * dz
				normals[j * columns + i] = simd_normalize(SIMD3(-(right - left) / spanX, 1, -(south - north) / spanZ))
			}
		}

		// Two counter-clockwise (seen from above) triangles per cell.
		var indices: [UInt32] = []
		indices.reserveCapacity((columns - 1) * (rows - 1) * 6)
		for j in 0..<(rows - 1) {
			for i in 0..<(columns - 1) {
				let a = UInt32(j * columns + i), b = a + 1
				let c = a + UInt32(columns), d = c + 1
				indices.append(contentsOf: [a, c, b, b, c, d])
			}
		}
		surfaceTriangleCount = indices.count / 3

		// A skirt: the perimeter duplicated below the ground so the model reads as a solid slab.
		if skirtDepth > 0 {
			var perimeter: [Int] = []
			for i in 0..<columns { perimeter.append(i) }
			for j in 1..<rows { perimeter.append(j * columns + columns - 1) }
			for i in stride(from: columns - 2, through: 0, by: -1) { perimeter.append((rows - 1) * columns + i) }
			for j in stride(from: rows - 2, through: 1, by: -1) { perimeter.append(j * columns) }
			let base = UInt32(positions.count)
			let center = SIMD2<Float>(0, 0)
			for index in perimeter {
				var p = positions[index]
				p.y = -skirtDepth
				positions.append(p)
				uvs.append(uvs[index])
				let outward = SIMD2(p.x, p.z) - center
				normals.append(simd_normalize(SIMD3(outward.x, 0, outward.y)))
			}
			for k in 0..<perimeter.count {
				let p = UInt32(perimeter[k]), q = UInt32(perimeter[(k + 1) % perimeter.count])
				let pBelow = base + UInt32(k), qBelow = base + UInt32((k + 1) % perimeter.count)
				indices.append(contentsOf: [p, q, pBelow, q, qBelow, pBelow])
			}
		}
		self.positions = positions
		self.normals = normals
		textureCoordinates = uvs
		self.indices = indices
	}

	/// Ground height (model units) under a coordinate, clamped to the box.
	func groundHeight(at coordinate: CLLocationCoordinate2D) -> Float {
		let bounds = transform.frame.bounds
		let u = (coordinate.longitude - bounds.minLon) / (bounds.maxLon - bounds.minLon)
		let v = (bounds.maxLat - coordinate.latitude) / (bounds.maxLat - bounds.minLat)
		let grid = SpatialHeightGrid(columns: columns, rows: rows, heights: groundHeights, covered: covered, baseElevation: 0, maxElevation: 0)
		return grid.height(u: u, v: v)
	}

	/// Where to put something that sits on the ground at a coordinate.
	func surfacePosition(for coordinate: CLLocationCoordinate2D, clearance: Float = 0) -> SIMD3<Float> {
		var p = transform.position(coordinate, altitude: transform.baseElevation)
		p.y = groundHeight(at: coordinate) + clearance
		return p
	}
}
