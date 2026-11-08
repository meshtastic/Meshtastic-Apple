//
//  SpatialCastleTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial map castle tower")
struct SpatialCastleTests {

	@Test("the castle stays within its triangle budget, stands on the ground and tops out at its height")
	func meshShape() throws {
		let parts = SpatialCastle.geometry()
		#expect(Set(parts.keys) == Set(SpatialCastle.Part.allCases))
		let total = parts.values.map(\.triangleCount).reduce(0, +)
		#expect(total > 200 && total < SpatialCastle.triangleBudget, "\(total)")
		let ys = parts.values.flatMap { $0.positions.map(\.y) }
		#expect(try #require(ys.min()) >= -0.0001)
		#expect(try #require(ys.min()) < 0.0001)
		#expect(abs(try #require(ys.max()) - SpatialCastle.height) < 0.0003)
		for (part, mesh) in parts {
			#expect(mesh.triangleCount > 0, "\(part)")
			#expect(mesh.positions.count == mesh.normals.count, "\(part)")
			#expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count }, "\(part)")
			#expect(mesh.normals.allSatisfy { !$0.x.isNaN && abs(simd_length($0) - 1) < 0.001 }, "\(part)")
		}
	}

	@Test("every face winds the way its normals point")
	func winding() {
		for (part, mesh) in SpatialCastle.geometry() {
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

	@Test("every point of the stone has a place on the block texture, the blocks running level up the walls")
	func blockMapping() throws {
		let stone = try #require(SpatialCastle.geometry()[.stone])
		let uvs = SpatialCastle.textureCoordinates(stone)
		#expect(uvs.count == stone.positions.count)
		#expect(uvs.allSatisfy { $0.x.isFinite && $0.y.isFinite })
		// On the front wall, a course higher is a course further up the texture.
		let front = SpatialMeshData(positions: [[0, 0.01, SpatialCastle.keepHalf], [0, 0.01 + SpatialCastle.blockHeight, SpatialCastle.keepHalf]], normals: [[0, 0, 1], [0, 0, 1]])
		let mapped = SpatialCastle.textureCoordinates(front)
		#expect(abs((mapped[1].y - mapped[0].y) * Float(SpatialCastle.tileBlocks) - 1) < 0.0001)
		#expect(mapped[1].x == mapped[0].x)
	}

	@Test("the windows sit between the string courses and clear the corners' bartizans")
	func windows() {
		for window in SpatialCastle.windows {
			#expect(window.bottom - 0.0007 > SpatialCastle.courses[0])
			#expect(window.bottom + window.height < SpatialCastle.courses[1] - 0.0005)
			#expect(abs(window.along) + window.width / 2 + 0.00035 < SpatialCastle.keepHalf - SpatialCastle.bartizanRadius)
		}
	}

	@Test("the castle stands on about the lookout's footprint and height, so it steps aside the same way")
	func likeTheLookout() {
		let positions = SpatialCastle.geometry().values.flatMap(\.positions)
		let reach = positions.map { max(abs($0.x), abs($0.z)) }.max() ?? 0
		#expect(reach < SpatialLookout.deckHalf * 1.2)
		#expect(SpatialCastle.height > SpatialLookout.height * 0.8 && SpatialCastle.height < SpatialLookout.height * 1.2)
	}
}
