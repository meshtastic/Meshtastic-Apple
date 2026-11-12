//
//  SpatialStationTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial map space station")
struct SpatialStationTests {

	@Test("the station stays within its triangle budget, every part drawn, centered on its middle")
	func meshShape() throws {
		let parts = SpatialStation.geometry()
		#expect(Set(parts.keys) == Set(SpatialStation.Part.allCases))
		let total = parts.values.map(\.triangleCount).reduce(0, +)
		#expect(total > 200 && total < SpatialStation.triangleBudget, "\(total)")
		for (part, mesh) in parts {
			#expect(mesh.triangleCount > 0, "\(part)")
			#expect(mesh.positions.count == mesh.normals.count, "\(part)")
			#expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count }, "\(part)")
			#expect(mesh.normals.allSatisfy { !$0.x.isNaN && abs(simd_length($0) - 1) < 0.001 }, "\(part)")
		}
		let positions = parts.values.flatMap(\.positions)
		let xs = positions.map(\.x), ys = positions.map(\.y), zs = positions.map(\.z)
		// The truss is the widest thing, then the wings out either side of it.
		#expect(abs(try #require(xs.max()) - SpatialStation.trussLength / 2) < 0.001)
		#expect(abs(try #require(xs.min()) + SpatialStation.trussLength / 2) < 0.001)
		#expect(try #require(zs.max()) < SpatialStation.trussLength / 2)
		#expect(try #require(ys.max()) < SpatialStation.halfHeight && -(try #require(ys.min())) < SpatialStation.halfHeight)
	}

	@Test("every face winds the way its normals point")
	func winding() {
		for (part, mesh) in SpatialStation.geometry() {
			var facing = true
			for t in 0..<mesh.triangleCount {
				let i = (0..<3).map { Int(mesh.indices[3 * t + $0]) }
				let p = i.map { mesh.positions[$0] }
				let face = simd_cross(p[1] - p[0], p[2] - p[0])
				let normal = i.map { mesh.normals[$0] }.reduce(SIMD3<Float>.zero, +)
				if simd_dot(face, normal) <= 0 { facing = false }
			}
			#expect(facing, "\(part)")
		}
	}

	@Test("the cupola is on the underside")
	func cupolaDown() throws {
		let window = try #require(SpatialStation.geometry()[.window])
		#expect(window.positions.allSatisfy { $0.y < -SpatialStation.moduleDrop })
	}

	@Test("it floats over the highest of the terrain and the roofs, under the volume's top")
	func placement() {
		let scale: Float = 2
		// Over the terrain, or a taller roof.
		#expect(SpatialStation.height(terrainTop: 0.2, roofTop: nil, counterScale: scale) == 0.2 + SpatialStation.clearance * scale)
		#expect(SpatialStation.height(terrainTop: 0.2, roofTop: 0.25, counterScale: scale) == 0.25 + SpatialStation.clearance * scale)
		#expect(SpatialStation.height(terrainTop: 0.2, roofTop: 0.1, counterScale: scale) == 0.2 + SpatialStation.clearance * scale)
		// Brought down under a low ceiling, but never into the ground under it.
		let low = SpatialStation.height(terrainTop: 0.2, roofTop: nil, counterScale: scale, ceiling: 0.35)
		#expect(abs(low - (0.35 - SpatialStation.halfHeight * scale)) < 0.0001)
		let tooLow = SpatialStation.height(terrainTop: 0.2, roofTop: nil, counterScale: scale, ceiling: 0.21)
		#expect(tooLow >= 0.2 + SpatialStation.halfHeight * scale)
	}

	@Test("it grows with the map's zoom, never smaller than at the whole mesh and never past its cap")
	func growsWithZoom() {
		#expect(SpatialStation.growth(zoom: 1) == 1)
		#expect(SpatialStation.growth(zoom: 0.5) == 1)
		#expect(SpatialStation.growth(zoom: 2) == 2)
		#expect(SpatialStation.growth(zoom: 40) == SpatialStation.maximumGrowth)
		#expect(SpatialStation.growth(zoom: .nan) == 1)
	}
}
