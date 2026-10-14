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

	@Test func spinCarriesTheGrabbedPointWithTheHand() {
		// Near half (toward the viewer): moving right turns the map so that point moves right.
		let near = SpatialWheelSpin.yawDelta(start: [0, 0.3], current: [0.1, 0.3], diskRadius: 0.5)
		#expect(near > 0)
		let point = simd_quatf(angle: near, axis: [0, 1, 0]).act(SIMD3<Float>(0, 0, 0.3))
		#expect(point.x > 0)
		// Far half: the same hand movement turns it the other way.
		#expect(SpatialWheelSpin.yawDelta(start: [0, -0.3], current: [0.1, -0.3], diskRadius: 0.5) < 0)
		// Ten centimeters of hand travel on a half-meter table is a useful turn (about 23 degrees).
		#expect(abs(near - 0.4) < 1e-5)
		#expect(SpatialWheelSpin.yawDelta(start: [0, 0.3], current: [.nan, 0.3], diskRadius: 0.5) == 0)
	}
}

@Suite("Spatial map wheel motion")
struct SpatialWheelMotionTests {
	private let frame = 1.0 / 90

	@Test func easingIsTheSameAtAnyFrameRate() {
		var fast: Float = 0, slow: Float = 0
		for _ in 0..<12 { fast = SpatialWheelMotion.eased(fast, toward: 1, dt: 1.0 / 120, timeConstant: 0.07) }
		for _ in 0..<6 { slow = SpatialWheelMotion.eased(slow, toward: 1, dt: 1.0 / 60, timeConstant: 0.07) }
		#expect(abs(fast - slow) < 1e-4)
		// One time constant closes about 63% of the gap.
		let one = SpatialWheelMotion.eased(0, toward: 1, dt: 0.07, timeConstant: 0.07)
		#expect(abs(one - 0.632) < 0.001)
	}

	@Test func easingSnapsOnceClose() {
		#expect(SpatialWheelMotion.eased(0.99995, toward: 1, dt: frame, timeConstant: 0.07) == 1)
		#expect(SpatialWheelMotion.eased(0.3, toward: 1, dt: 0, timeConstant: 0.07) == 1)
	}

	@Test func velocityUsesOnlyTheLastWindow() {
		// A slow start, then 2 rad/s over the last 100 ms.
		let samples: [(time: Double, yaw: Float)] = [(0, 0), (0.5, 0.1), (0.9, 0.2), (0.95, 0.3), (1.0, 0.4)]
		#expect(abs(SpatialWheelMotion.velocity(of: samples, at: 1.0) - 2) < 1e-4)
	}

	@Test func velocityIsZeroWhenTheHandHeldStill() {
		let samples: [(time: Double, yaw: Float)] = [(0, 0), (0.05, 0.5), (0.1, 1)]
		#expect(SpatialWheelMotion.velocity(of: samples, at: 0.5) == 0)
		#expect(SpatialWheelMotion.velocity(of: [(1, 1)], at: 1) == 0)
	}

	@Test func velocityDropsWhenTheHandStoppedBeforeLettingGo() {
		// Fast until 1.0 s, then held still with no new samples until the release at 1.08 s.
		let samples: [(time: Double, yaw: Float)] = [(0.96, 0), (0.98, 0.06), (1.0, 0.12)]
		#expect(abs(SpatialWheelMotion.velocity(of: samples, at: 1.0) - 3) < 1e-3)
		#expect(SpatialWheelMotion.velocity(of: samples, at: 1.08) < 1.1)
	}

	@Test func decayStopsWithinASecond() {
		var velocity = SpatialWheelMotion.maximumSpeed
		var time = 0.0
		while velocity != 0, time < 3 {
			velocity = SpatialWheelMotion.decayed(velocity, dt: frame)
			time += frame
		}
		#expect(velocity == 0)
		#expect(time < 1)
	}

	@Test func aFlickCoastsInTheSameDirectionAndStops() {
		var motion = SpatialWheelMotion()
		_ = motion.grab()
		for i in 0...10 { motion.drag(to: Float(i) * 0.03, at: Double(i) * 0.01) }
		while motion.shown != motion.target { _ = motion.step(dt: frame) }
		motion.release(at: 0.1)
		#expect(motion.isCoasting)
		#expect(abs(motion.velocity - 3) < 1e-3)
		var last = motion.shown
		var frames = 0
		while motion.isMoving, frames < 500 {
			_ = motion.step(dt: frame)
			#expect(motion.shown >= last)
			last = motion.shown
			frames += 1
		}
		#expect(!motion.isMoving)
		#expect(motion.shown > 0.3)
		#expect(Double(frames) * frame < 1.5)
	}

	@Test func aSlowReleaseDoesNotCoast() {
		var motion = SpatialWheelMotion()
		_ = motion.grab()
		for i in 0...10 { motion.drag(to: Float(i) * 0.001, at: Double(i) * 0.01) }
		motion.release(at: 0.1)
		#expect(!motion.isCoasting)
	}

	@Test func releaseSpeedIsCapped() {
		var motion = SpatialWheelMotion()
		_ = motion.grab()
		motion.drag(to: 0, at: 0)
		motion.drag(to: 5, at: 0.05)
		motion.release(at: 0.05)
		#expect(motion.velocity == SpatialWheelMotion.maximumSpeed)
	}

	@Test func grabbingStopsACoastWhereItIs() {
		var motion = SpatialWheelMotion()
		_ = motion.grab()
		motion.drag(to: 0, at: 0)
		motion.drag(to: 0.3, at: 0.1)
		motion.release(at: 0.1)
		for _ in 0..<10 { _ = motion.step(dt: frame) }
		let shown = motion.shown
		let grabbed = motion.grab()
		#expect(grabbed == shown)
		#expect(!motion.isMoving)
		let changed = motion.step(dt: frame)
		#expect(!changed)
	}

	@Test func resetGoesBackTheShortWay() {
		var motion = SpatialWheelMotion()
		_ = motion.grab()
		motion.drag(to: 2 * .pi + 0.4, at: 0)
		while motion.shown != motion.target { _ = motion.step(dt: frame) }
		motion.reset()
		#expect(abs(motion.shown - 0.4) < 1e-4)
		var frames = 0
		while motion.isMoving, frames < 500 { _ = motion.step(dt: frame); frames += 1 }
		#expect(motion.shown == 0)
		#expect(!motion.isResetting)
	}

	@Test func aTapDoesNotCancelAReset() {
		var motion = SpatialWheelMotion()
		_ = motion.grab()
		motion.drag(to: 1, at: 0)
		while motion.shown != motion.target { _ = motion.step(dt: frame) }
		motion.reset()
		motion.stop()
		#expect(motion.target == 0)
		#expect(motion.isResetting)
		var frames = 0
		while motion.isMoving, frames < 500 { _ = motion.step(dt: frame); frames += 1 }
		#expect(motion.shown == 0)
	}

	@Test func dragDirectionHoldsThroughTheCenterLine() {
		// The side is taken from where the drag started, so crossing to the other half of the table
		// mid-drag doesn't reverse the turn.
		let start = SIMD2<Float>(0, 0.05)
		let before = SpatialWheelSpin.yawDelta(start: start, current: SIMD2(0.05, 0.02), diskRadius: 0.4)
		let after = SpatialWheelSpin.yawDelta(start: start, current: SIMD2(0.1, -0.2), diskRadius: 0.4)
		#expect(before > 0)
		#expect(after > before)
	}
}
