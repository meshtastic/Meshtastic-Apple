//
//  SpatialTowerTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

/// Every triangle's winding should face the same way as its vertex normals, or RealityKit culls
/// the side that should show.
private func windingMatchesNormals(_ mesh: SpatialMeshData) -> Bool {
	for t in 0..<mesh.triangleCount {
		let i = (0..<3).map { Int(mesh.indices[3 * t + $0]) }
		let p = i.map { mesh.positions[$0] }
		let face = simd_cross(p[1] - p[0], p[2] - p[0])
		let normal = i.map { mesh.normals[$0] }.reduce(SIMD3<Float>.zero, +)
		if simd_dot(face, normal) <= 0 { return false }
	}
	return true
}

@Suite("Spatial map towers")
struct SpatialTowerTests {

	@Test("routers stand tallest, then router late, repeater and client base")
	func heightByRole() throws {
		let router = try #require(SpatialTower.height(for: .router))
		let routerLate = try #require(SpatialTower.height(for: .routerLate))
		let repeater = try #require(SpatialTower.height(for: .repeater))
		let clientBase = try #require(SpatialTower.height(for: .clientBase))
		#expect(router > routerLate && routerLate > repeater && repeater > clientBase)
		#expect(router == 0.05)
		#expect(clientBase == 0.035)
	}

	@Test("only infrastructure roles get a tower")
	func towerRoles() {
		for role in DeviceRoles.allCases {
			#expect((SpatialTower.height(for: role) != nil) == role.isInfrastructure, "\(role)")
		}
		#expect(SpatialTower.height(for: nil) == nil)
	}

	@Test("each tower stays within the triangle budget and stands on the ground")
	func meshBudget() throws {
		for role in [DeviceRoles.router, .routerLate, .repeater, .clientBase] {
			let height = try #require(SpatialTower.height(for: role))
			let mesh = SpatialTower.geometry(height: height)
			#expect(mesh.triangleCount > 300 && mesh.triangleCount < SpatialTower.triangleBudget, "\(role): \(mesh.triangleCount)")
			#expect(mesh.positions.count == mesh.normals.count)
			#expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
			let ys = mesh.positions.map(\.y)
			#expect(ys.min() == 0)
			// The mast reaches the light, which tops out at the tower's height.
			let top = try #require(ys.max())
			#expect(top <= height && top > SpatialTower.beaconCenter(height: height) - 0.001, "\(role)")
		}
	}

	@Test("the legs spread over a footprint about 1.4 cm a side")
	func footprint() {
		let mesh = SpatialTower.geometry(height: 0.05)
		let spread = mesh.positions.filter { $0.y < 0.001 }.map { simd_length(SIMD2($0.x, $0.z)) }.max() ?? 0
		let circumradius = SpatialTower.footprintSide / Float(3).squareRoot()
		#expect(abs(spread - circumradius) < 0.001)
	}

	@Test("tower and ring triangles face the way their normals do")
	func winding() {
		#expect(windingMatchesNormals(SpatialTower.geometry(height: 0.04)))
		#expect(windingMatchesNormals(SpatialSignalRings.ringMesh()))
	}

	@Test("bracing levels climb to the lattice top, each section shorter")
	func levels() {
		let levels = SpatialTower.levels(latticeHeight: 0.036)
		#expect(levels.count == SpatialTower.sections + 1)
		#expect(levels.first == 0 && levels.last == 0.036)
		let steps = zip(levels.dropFirst(), levels).map { $0 - $1 }
		#expect(zip(steps.dropFirst(), steps).allSatisfy { $0 < $1 })
	}
}

@Suite("Spatial map tower light")
struct SpatialTowerBeaconTests {

	@Test("on for about a second, off for about a second, fading between")
	func blink() {
		#expect(SpatialTowerBeacon.brightness(time: 0, offset: 0) == 0)
		#expect(SpatialTowerBeacon.brightness(time: 0.6, offset: 0) == 1)
		#expect(SpatialTowerBeacon.brightness(time: 1.6, offset: 0) == 0)
		let rising = SpatialTowerBeacon.brightness(time: 0.15, offset: 0)
		let falling = SpatialTowerBeacon.brightness(time: 1.15, offset: 0)
		#expect(rising > 0 && rising < 1)
		#expect(falling > 0 && falling < 1)
		// One full period later it is in the same place.
		#expect(SpatialTowerBeacon.brightness(time: 0.15 + SpatialTowerBeacon.period, offset: 0) == rising)
	}

	@Test("a node's offset is stable and keeps neighbors out of step")
	func offsets() {
		#expect(SpatialTowerBeacon.offset(for: 0x1234_5678) == SpatialTowerBeacon.offset(for: 0x1234_5678))
		let offsets = (0..<50).map { SpatialTowerBeacon.offset(for: Int64(0xA000_0000 + $0)) }
		#expect(offsets.allSatisfy { $0 >= 0 && $0 < SpatialTowerBeacon.maxOffset })
		#expect(Set(offsets).count > 40)
	}
}

@Suite("Spatial map signal rings")
struct SpatialSignalRingTests {

	@Test("each ring starts a moment after the last, widens and fades")
	func progression() throws {
		#expect(SpatialSignalRings.ring(1, elapsed: 0.1) == nil)
		let early = try #require(SpatialSignalRings.ring(0, elapsed: 0))
		let middle = try #require(SpatialSignalRings.ring(0, elapsed: 0.7))
		let late = try #require(SpatialSignalRings.ring(0, elapsed: 1.3))
		#expect(early.radius == SpatialSignalRings.startRadius)
		#expect(early.opacity == SpatialSignalRings.peakOpacity)
		#expect(early.radius < middle.radius && middle.radius < late.radius)
		#expect(early.opacity > middle.opacity && middle.opacity > late.opacity)
		#expect(late.radius <= SpatialSignalRings.endRadius)
	}

	@Test("every ring has faded by the end of the burst")
	func burstEnds() {
		for index in 0..<SpatialSignalRings.count {
			#expect(SpatialSignalRings.ring(index, elapsed: SpatialSignalRings.burstDuration) == nil)
			#expect(SpatialSignalRings.ring(index, elapsed: SpatialSignalRings.burstDuration - 0.05 - Double(SpatialSignalRings.count - 1 - index) * SpatialSignalRings.stagger) != nil)
		}
	}

	@Test("a tower ripples at most every couple of seconds")
	func rateLimit() {
		var limiter = SpatialSignalRings.limiter()
		let first = limiter.admit(sender: 1, now: 0, highTraffic: false)
		let soon = limiter.admit(sender: 1, now: 1, highTraffic: false)
		let later = limiter.admit(sender: 1, now: 3, highTraffic: false)
		let busy = limiter.admit(sender: 2, now: 3, highTraffic: true)
		#expect(first && !soon && later && !busy)
	}
}
