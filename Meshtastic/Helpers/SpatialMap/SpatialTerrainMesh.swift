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
	/// Radius of the round map, the circle inscribed in the footprint, in model units.
	var diskRadius: Float { min(footprint.x, footprint.y) / 2 }

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

/// The terrain mesh plus the height field it was built from, in model units. The mesh is a disk
/// inscribed in the box: a regular grid with the vertices outside the circle moved onto it, and a
/// round skirt below the edge so the model reads as a solid table.
struct SpatialTerrainGeometry: Sendable {
	/// RealityKit samples textures with v = 0 at the bottom of the image, so the north edge is v = 1.
	static let flipTextureV = true
	/// Coarser grids are resampled to this many vertices across, so the edge still has enough
	/// vertices to look round.
	static let minimumGridSize = 97
	/// How far the skirt hangs below y = 0, in model units.
	static let defaultSkirtDepth: Float = 0.02

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
	/// Vertices on the top of the skirt, copies of the surface's edge; the same number again sit below them.
	let skirtRingCount: Int
	/// Height of the highest point on the map's edge, in model units, so the bezel can stand above it.
	let rimTop: Float

	init(grid source: SpatialHeightGrid, transform: SpatialModelTransform, skirtDepth: Float = defaultSkirtDepth) {
		let grid = source.upsampled(toAtLeast: Self.minimumGridSize)
		self.transform = transform
		let columns = grid.columns, rows = grid.rows
		self.columns = columns
		self.rows = rows
		covered = grid.covered
		hasAnyTerrain = grid.hasAnyTerrain
		let frame = transform.frame
		let bounds = frame.bounds
		let radius = transform.diskRadius
		let count = columns * rows
		let heights = grid.heights.map { transform.height(forAltitude: Double($0)) }
		groundHeights = heights

		// Surface normals from the height field: (-dh/dx, 1, -dh/dz), one-sided at the edges.
		let dx = transform.footprint.x / Float(columns - 1)
		let dz = transform.footprint.y / Float(rows - 1)
		var gridNormals = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: count)
		for j in 0..<rows {
			for i in 0..<columns {
				let left = heights[j * columns + max(i - 1, 0)]
				let right = heights[j * columns + min(i + 1, columns - 1)]
				let north = heights[max(j - 1, 0) * columns + i]
				let south = heights[min(j + 1, rows - 1) * columns + i]
				let spanX = Float(min(i + 1, columns - 1) - max(i - 1, 0)) * dx
				let spanZ = Float(min(j + 1, rows - 1) - max(j - 1, 0)) * dz
				gridNormals[j * columns + i] = simd_normalize(SIMD3(-(right - left) / spanX, 1, -(south - north) / spanZ))
			}
		}

		// A point on the ground at a model x/z: height and normal read bilinearly off the grid,
		// texture coordinate from its coordinate in the Mercator image.
		struct SurfacePoint { let position: SIMD3<Float>; let normal: SIMD3<Float>; let uv: SIMD2<Float> }
		func surfacePoint(x: Float, z: Float) -> SurfacePoint {
			let coordinate = transform.coordinate(x: x, z: z)
			let u = (coordinate.longitude - bounds.minLon) / (bounds.maxLon - bounds.minLon)
			let v = (bounds.maxLat - coordinate.latitude) / (bounds.maxLat - bounds.minLat)
			let gx = min(max(u, 0), 1) * Double(columns - 1)
			let gy = min(max(v, 0), 1) * Double(rows - 1)
			let x0 = min(Int(gx), columns - 2), y0 = min(Int(gy), rows - 2)
			let tx = Float(gx - Double(x0)), ty = Float(gy - Double(y0))
			let i00 = y0 * columns + x0, i10 = i00 + 1, i01 = i00 + columns, i11 = i01 + 1
			let w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty
			let height = heights[i00] * w00 + heights[i10] * w10 + heights[i01] * w01 + heights[i11] * w11
			let normal = simd_normalize(gridNormals[i00] * w00 + gridNormals[i10] * w10 + gridNormals[i01] * w01 + gridNormals[i11] * w11)
			let mercatorV = frame.mercatorFraction(latitude: coordinate.latitude, longitude: coordinate.longitude).y
			return SurfacePoint(position: SIMD3(x, height, z), normal: normal, uv: SIMD2(Float(u), Float(Self.flipTextureV ? 1 - mercatorV : mercatorV)))
		}

		var positions = [SIMD3<Float>](repeating: .zero, count: count)
		var normals = gridNormals
		var uvs = [SIMD2<Float>](repeating: .zero, count: count)
		var moved = [Bool](repeating: false, count: count)
		for j in 0..<rows {
			let latitude = bounds.maxLat - (bounds.maxLat - bounds.minLat) * Double(j) / Double(rows - 1)
			let v = frame.mercatorFraction(latitude: latitude, longitude: bounds.minLon).y
			for i in 0..<columns {
				let longitude = bounds.minLon + (bounds.maxLon - bounds.minLon) * Double(i) / Double(columns - 1)
				let index = j * columns + i
				let p = transform.position(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: Double(grid.heights[index]))
				let distance = (p.x * p.x + p.z * p.z).squareRoot()
				if distance > radius {
					// Outside the circle: onto it at the same angle, with the ground found there.
					let point = surfacePoint(x: p.x * radius / distance, z: p.z * radius / distance)
					positions[index] = point.position
					normals[index] = point.normal
					uvs[index] = point.uv
					moved[index] = true
				} else {
					positions[index] = p
					uvs[index] = SIMD2(Float(i) / Float(columns - 1), Float(Self.flipTextureV ? 1 - v : v))
				}
			}
		}

		// Two counter-clockwise (seen from above) triangles per cell. Triangles squeezed onto the
		// edge (every corner moved) or folded flat by the move are left out.
		let minimumArea = dx * dz * 1e-3
		var indices: [UInt32] = []
		indices.reserveCapacity((columns - 1) * (rows - 1) * 6)
		func add(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> Bool {
			if moved[Int(a)], moved[Int(b)], moved[Int(c)] { return false }
			let pa = positions[Int(a)], pb = positions[Int(b)], pc = positions[Int(c)]
			let doubleArea = (pb.z - pa.z) * (pc.x - pa.x) - (pb.x - pa.x) * (pc.z - pa.z)
			guard doubleArea > minimumArea else { return false }
			indices.append(contentsOf: [a, b, c])
			return true
		}
		// Which of each cell's two triangles were kept: [cell * 2] is a-c-b, [cell * 2 + 1] is b-c-d.
		var kept = [Bool](repeating: false, count: (columns - 1) * (rows - 1) * 2)
		for j in 0..<(rows - 1) {
			for i in 0..<(columns - 1) {
				let a = UInt32(j * columns + i), b = a + 1
				let c = a + UInt32(columns), d = c + 1
				let cell = j * (columns - 1) + i
				kept[cell * 2] = add(a, c, b)
				kept[cell * 2 + 1] = add(b, c, d)
			}
		}
		surfaceTriangleCount = indices.count / 3

		// A round skirt hung from the surface's own edge, so the two meet with no gap: every kept
		// triangle edge with no kept triangle across it gets a wall down to below the ground.
		if skirtDepth > 0 {
			func isKept(_ i: Int, _ j: Int, _ second: Int) -> Bool {
				i >= 0 && j >= 0 && i < columns - 1 && j < rows - 1 && kept[(j * (columns - 1) + i) * 2 + second]
			}
			// Edges in the order their triangle lists them, which runs counter-clockwise seen from above.
			var edges: [(UInt32, UInt32)] = []
			for j in 0..<(rows - 1) {
				for i in 0..<(columns - 1) {
					let a = UInt32(j * columns + i), b = a + 1
					let c = a + UInt32(columns), d = c + 1
					if isKept(i, j, 0) {
						if !isKept(i - 1, j, 1) { edges.append((a, c)) }
						if !isKept(i, j, 1) { edges.append((c, b)) }
						if !isKept(i, j - 1, 1) { edges.append((b, a)) }
					}
					if isKept(i, j, 1) {
						if !isKept(i, j, 0) { edges.append((b, c)) }
						if !isKept(i, j + 1, 0) { edges.append((c, d)) }
						if !isKept(i + 1, j, 0) { edges.append((d, b)) }
					}
				}
			}
			var ring = [UInt32](repeating: UInt32.max, count: count)
			var ringVertices: [UInt32] = []
			for (p, q) in edges {
				for v in [p, q] where ring[Int(v)] == UInt32.max {
					ring[Int(v)] = UInt32(ringVertices.count)
					ringVertices.append(v)
				}
			}
			let n = ringVertices.count
			let base = UInt32(positions.count)
			for below in [false, true] {
				for v in ringVertices {
					var p = positions[Int(v)]
					normals.append(simd_normalize(SIMD3(p.x, 0, p.z)))
					uvs.append(uvs[Int(v)])
					if below { p.y = -skirtDepth }
					positions.append(p)
				}
			}
			for (p, q) in edges {
				let pTop = base + ring[Int(p)], qTop = base + ring[Int(q)]
				let pBelow = pTop + UInt32(n), qBelow = qTop + UInt32(n)
				indices.append(contentsOf: [qTop, pTop, qBelow, pTop, pBelow, qBelow])
			}
			skirtRingCount = n
			rimTop = ringVertices.map { positions[Int($0)].y }.max() ?? 0
		} else {
			skirtRingCount = 0
			rimTop = (0..<count).filter { moved[$0] }.map { positions[$0].y }.max() ?? 0
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

/// The buffers of a mesh drawn over the terrain.
struct SpatialOverlayMesh: Sendable {
	let positions: [SIMD3<Float>]
	let normals: [SIMD3<Float>]
	let uvs: [SIMD2<Float>]
	let indices: [UInt32]
}

extension SpatialTerrainGeometry {
	/// How far an overlay floats over the ground, in model units: a couple of millimeters on the table.
	static let overlayLift: Float = 0.003

	/// The top surface alone, raised by `lift`, for an overlay drawn over the terrain with the same
	/// texture coordinates. The skirt's vertices and triangles come after the surface's, so the
	/// first `columns * rows` vertices and `surfaceTriangleCount` triangles are the surface.
	func overlaySurface(lift: Float = overlayLift) -> SpatialOverlayMesh {
		let count = columns * rows
		let positions = positions.prefix(count).map { SIMD3($0.x, $0.y + lift, $0.z) }
		return SpatialOverlayMesh(
			positions: positions, normals: Array(normals.prefix(count)),
			uvs: Array(textureCoordinates.prefix(count)), indices: Array(indices.prefix(surfaceTriangleCount * 3))
		)
	}
}
