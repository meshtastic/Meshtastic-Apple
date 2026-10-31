//
//  SpatialLookoutTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
import CoreLocation
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial map fire lookout")
struct SpatialLookoutTests {

	@Test("the lookout stays within its triangle budget, stands on the ground and tops out at its height")
	func meshShape() throws {
		let parts = SpatialLookout.geometry()
		#expect(Set(parts.keys) == Set(SpatialLookout.Part.allCases))
		let total = parts.values.map(\.triangleCount).reduce(0, +)
		#expect(total > 200 && total < SpatialLookout.triangleBudget, "\(total)")
		let ys = parts.values.flatMap { $0.positions.map(\.y) }
		#expect(try #require(ys.min()) >= -0.0001)
		#expect(try #require(ys.min()) < 0.0001)
		#expect(abs(try #require(ys.max()) - SpatialLookout.height) < 0.0003)
		for (part, mesh) in parts {
			#expect(mesh.triangleCount > 0, "\(part)")
			#expect(mesh.positions.count == mesh.normals.count, "\(part)")
			#expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count }, "\(part)")
		}
	}

	@Test("every face winds the way its normals point")
	func winding() {
		for (part, mesh) in SpatialLookout.geometry() {
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

	@Test("the cab stands on a tower that narrows toward the top, with the stairs inside it")
	func towerAndStairs() throws {
		#expect(SpatialLookout.towerHalf(at: 0) > SpatialLookout.towerHalf(at: SpatialLookout.towerHeight))
		#expect(SpatialLookout.towerHeight > SpatialLookout.height / 2)
		let wood = try #require(SpatialLookout.geometry()[.wood])
		// Below the catwalk, everything is inside the legs' footprint at the ground.
		let below = wood.positions.filter { $0.y < SpatialLookout.towerHeight - 0.001 }
		#expect(!below.isEmpty)
		let limit = SpatialLookout.baseHalf + SpatialLookout.legWidth
		#expect(below.allSatisfy { abs($0.x) <= limit && abs($0.z) <= limit })
		#expect(SpatialLookout.levels.first == 0 && SpatialLookout.levels.last == SpatialLookout.towerHeight)
	}

	@Test("the front faces the cab's bearing on the map, x east and z south")
	func frontHeading() {
		let turn = simd_quatf(angle: SpatialLookout.yaw, axis: [0, 1, 0])
		let front = turn.act([0, 0, 1])
		let bearing = SpatialLookout.frontHeading * .pi / 180
		#expect(abs(front.x - Float(sin(bearing))) < 0.0001)
		#expect(abs(front.z + Float(cos(bearing))) < 0.0001)
	}

	@Test("a site's ID gives its coordinate; anything else gives nil")
	func siteID() throws {
		let coordinate = try #require(SpatialLookout.coordinate(siteID: "46.8529,-121.7604"))
		#expect(coordinate.latitude == 46.8529)
		#expect(coordinate.longitude == -121.7604)
		#expect(SpatialLookout.coordinate(siteID: "") == nil)
		#expect(SpatialLookout.coordinate(siteID: "46.8") == nil)
		#expect(SpatialLookout.coordinate(siteID: "north,east") == nil)
		#expect(SpatialLookout.coordinate(siteID: "95,10") == nil)
	}

	@Test("the lookout stands on the summit when no node is there")
	func spotClearSummit() {
		#expect(SpatialLookoutSpot.spot(summit: .zero, pins: [[0.1, 0]], clearance: 0.02) == nil)
	}

	@Test("the lookout steps aside clear of every node on the summit, not just the nearest")
	func spotClearsAllPins() throws {
		let pins: [SIMD2<Float>] = [[-0.010, 0], [0.012, 0]]
		let spot = try #require(SpatialLookoutSpot.spot(summit: .zero, pins: pins, clearance: 0.022))
		for pin in pins {
			#expect(simd_distance(spot, pin) >= 0.022 - 1e-6)
		}
	}

	@Test("the lookout steps behind its cab first")
	func spotBehindCab() throws {
		let spot = try #require(SpatialLookoutSpot.spot(summit: .zero, pins: [.zero], clearance: 0.02))
		let back = Float(SpatialLookout.frontHeading * .pi / 180) + .pi
		#expect(simd_distance(spot, SIMD2(sin(back), -cos(back)) * 0.02) < 1e-5)
	}
}
