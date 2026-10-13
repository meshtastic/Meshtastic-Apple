//
//  SpatialWheelTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial map wheel")
struct SpatialWheelTests {
	private func point(_ angle: Float, _ distance: Float = 0.4) -> SIMD2<Float> {
		SpatialWheelLayout.point(distance: distance, angle: angle)
	}

	@Test func aQuarterTurnOfTheHandTurnsTheMapAQuarter() {
		let start = point(0)
		var drag = SpatialWheelDrag(startYaw: 0.3, x: start.x, z: start.y)
		let end = point(.pi / 2)
		let yaw = drag.update(x: end.x, z: end.y)
		#expect(abs(yaw - (0.3 + .pi / 2)) < 1e-5)
	}

	@Test func theAngleMatchesTheYawRotation() throws {
		// Turning the table by a yaw about +y moves a point's angle by the same amount.
		let p = SIMD3<Float>(0.3, 0, -0.1)
		let yaw: Float = 1.1
		let turned = simd_quatf(angle: yaw, axis: [0, 1, 0]).act(p)
		let before = try #require(SpatialWheelDrag.angle(x: p.x, z: p.z))
		let after = try #require(SpatialWheelDrag.angle(x: turned.x, z: turned.z))
		#expect(abs(SpatialWheelDrag.wrapped(after - before - yaw)) < 1e-5)
	}

	@Test func crossingTheBackOfTheCircleDoesNotJump() {
		// From just under π to just past -π is a small step, not nearly a full turn back.
		let start = point(.pi - 0.1)
		var drag = SpatialWheelDrag(startYaw: 0, x: start.x, z: start.y)
		let end = point(-.pi + 0.1)
		let yaw = drag.update(x: end.x, z: end.y)
		#expect(abs(yaw - 0.2) < 1e-4)
	}

	@Test func turnsAccumulatePastAFullTurn() {
		let start = point(0)
		var drag = SpatialWheelDrag(startYaw: 0, x: start.x, z: start.y)
		var yaw: Float = 0
		for step in 1...12 {
			let p = point(Float(step) * .pi / 4)
			yaw = drag.update(x: p.x, z: p.y)
		}
		#expect(abs(yaw - 3 * .pi) < 1e-4)
		for step in (0..<12).reversed() {
			let p = point(Float(step) * .pi / 4)
			yaw = drag.update(x: p.x, z: p.y)
		}
		#expect(abs(yaw) < 1e-4)
	}

	@Test func pointsNearTheCenterAreSkipped() {
		// A drag that starts on the middle picks up its angle once it leaves the dead zone.
		var drag = SpatialWheelDrag(startYaw: 0.5, x: 0, z: 0)
		let near = point(1, SpatialWheelDrag.deadZone / 2)
		#expect(drag.update(x: near.x, z: near.y) == 0.5)
		let out = point(0.2)
		#expect(drag.update(x: out.x, z: out.y) == 0.5)
		let further = point(0.7)
		#expect(abs(drag.update(x: further.x, z: further.y) - 1.0) < 1e-5)
		#expect(SpatialWheelDrag.angle(x: .nan, z: 0) == nil)
	}

	@Test func wrappedStaysInRange() {
		for angle in stride(from: Float(-20), through: 20, by: 0.37) {
			let wrapped = SpatialWheelDrag.wrapped(angle)
			#expect(wrapped > -.pi - 1e-5 && wrapped <= .pi + 1e-5)
			#expect(abs(sin(wrapped) - sin(angle)) < 1e-3 && abs(cos(wrapped) - cos(angle)) < 1e-3)
		}
		#expect(abs(SpatialWheelDrag.wrapped(3 * .pi / 2) + .pi / 2) < 1e-5)
	}

	@Test func theWheelFitsInTheRimMargin() {
		#expect(SpatialWheelLayout.reach <= SpatialVolumeFit.rimMargin)
	}

	@Test func northSitsAwayFromTheViewer() throws {
		let north = try #require(SpatialWheelLayout.compassPoints.first { $0.letter == "N" })
		let p = SpatialWheelLayout.point(distance: 1, angle: north.angle)
		#expect(abs(p.x) < 1e-5 && abs(p.y + 1) < 1e-5)
		#expect(SpatialWheelLayout.handleAngles.count == SpatialWheelLayout.handleCount)
	}

	@Test func theBezelFacesOutward() {
		let mesh = SpatialBezelMesh(innerRadius: 0.4, width: 0.022, bottom: -0.02, top: 0.01, chamfer: 0.004, segments: 24)
		#expect(mesh.positions.count == mesh.normals.count)
		#expect(mesh.indices.count == 5 * 24 * 6)
		for t in stride(from: 0, to: mesh.indices.count, by: 3) {
			let a = mesh.positions[Int(mesh.indices[t])]
			let b = mesh.positions[Int(mesh.indices[t + 1])]
			let c = mesh.positions[Int(mesh.indices[t + 2])]
			#expect(simd_dot(simd_cross(b - a, c - a), mesh.normals[Int(mesh.indices[t])]) > 0)
		}
		let radii = mesh.positions.map { simd_length(SIMD2($0.x, $0.z)) }
		#expect(abs((radii.min() ?? 0) - 0.4) < 1e-4)
		#expect(abs((radii.max() ?? 0) - 0.422) < 1e-4)
		#expect(abs((mesh.positions.map(\.y).max() ?? 0) - 0.01) < 1e-6)
	}
}
