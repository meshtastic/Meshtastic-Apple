//
//  SpatialRouteLayoutTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//

import CoreLocation
import simd
import Testing
@testable import Meshtastic

@Suite("Spatial route layout")
struct SpatialRouteLayoutTests {

	private let origin: Int64 = 0x0A1B_2C3D
	private let relayA: Int64 = 0x3333_4444
	private let relayB: Int64 = 0x5555_6666
	private let target: Int64 = 0x1111_2222

	private var positions: [Int64: CLLocationCoordinate2D] {
		[
			origin: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.40),
			relayA: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.37),
			relayB: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.34),
			target: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.31)
		]
	}

	private func layout(
		forward: [TraceRouteLegs.Hop],
		back: [TraceRouteLegs.Hop] = [],
		originBackSnr: Float = 4,
		positions: [Int64: CLLocationCoordinate2D]? = nil
	) -> SpatialRouteLayout {
		let positions = positions ?? self.positions
		let legs = TraceRouteLegs(
			originNum: origin, targetNum: target, forwardHops: forward, backRelays: back,
			originBackSnr: originBackSnr, hasBack: true, preset: .longFast, positions: positions, lookup: { _ in nil }
		)
		return SpatialRouteLayout(legs: legs, positions: positions)
	}

	private var forward: [TraceRouteLegs.Hop] {
		[.init(num: origin, snr: 4), .init(num: relayA, snr: 7), .init(num: relayB, snr: -2.5), .init(num: target, snr: 1)]
	}

	@Test("Forward legs are solid, return legs dashed")
	func dashedReturn() {
		let result = layout(forward: forward, back: [.init(num: relayB, snr: 2)])
		#expect(result.segments.filter { !$0.isBack }.allSatisfy { !$0.isDashed })
		#expect(result.segments.filter(\.isBack).allSatisfy { $0.isDashed })
	}

	@Test("A forward leg with no SNR is dashed")
	func unknownSnrDashed() {
		let hops: [TraceRouteLegs.Hop] = [.init(num: origin, snr: 4), .init(num: relayA, snr: TraceRouteLegs.unknownSnr), .init(num: target, snr: 3)]
		let result = layout(forward: hops)
		#expect(result.segments.map(\.isDashed) == [true, false])
		#expect(result.segments[0].snr == nil)
	}

	@Test("Only legs used both ways are marked shared, and their pills move off the middle")
	func sharedLegs() {
		// Out through A and B, back through B only: target→B is shared with B→target; B→origin isn't.
		let result = layout(forward: forward, back: [.init(num: relayB, snr: 2)])
		let shared = result.segments.filter(\.sharesLeg).map { "\($0.isBack ? "b" : "f"):\($0.fromNum)>\($0.toNum)" }
		#expect(shared.sorted() == ["b:\(target)>\(relayB)", "f:\(relayB)>\(target)"].sorted())
		#expect(result.segments.first { !$0.sharesLeg }?.pillFraction == 0.5)
		#expect(result.segments.first(where: \.sharesLeg)?.pillFraction == 0.35)
	}

	@Test("Relays are numbered per direction with their node numbers")
	func badges() {
		let result = layout(forward: forward, back: [.init(num: relayB, snr: 2), .init(num: relayA, snr: 3)])
		#expect(result.badges.filter { !$0.isBack }.map(\.number) == [1, 2])
		#expect(result.badges.filter { !$0.isBack }.map(\.num) == [relayA, relayB])
		#expect(result.badges.filter(\.isBack).map(\.num) == [relayB, relayA])
		#expect(result.originNum == origin)
		#expect(result.targetNum == target)
	}

	@Test("An endpoint without a position has no ring")
	func endpointWithoutPosition() {
		var positions = self.positions
		positions[target] = nil
		let result = layout(forward: forward, positions: positions)
		#expect(result.originNum == origin)
		#expect(result.targetNum == nil)
	}

	@Test("Right of travel is level and flips with direction")
	func rightSide() {
		// Heading toward -z (away from the viewer), right is +x.
		let right = SpatialRouteGeometry.rightSide(from: [0, 0, 0], to: [0, 0.2, -1])
		#expect(simd_distance(right, [1, 0, 0]) < 1e-5)
		let back = SpatialRouteGeometry.rightSide(from: [0, 0.2, -1], to: [0, 0, 0])
		#expect(simd_distance(back, [-1, 0, 0]) < 1e-5)
		#expect(SpatialRouteGeometry.rightSide(from: [0, 0, 0], to: [0, 1, 0]) == .zero)
	}

	@Test("Dashes are centered, the right length, and stay on the line")
	func dashes() {
		let dashes = SpatialRouteGeometry.dashes(length: 1, dash: 0.1, gap: 0.05)
		// (1 + 0.05) / 0.15 = 7 dashes using 7 × 0.15 − 0.05 = 1.0
		#expect(dashes.count == 7)
		#expect(dashes.allSatisfy { abs(($0.y - $0.x) - 0.1) < 1e-5 })
		#expect(abs(dashes[0].x - (1 - dashes[6].y)) < 1e-5)
		let odd = SpatialRouteGeometry.dashes(length: 0.5, dash: 0.1, gap: 0.05)
		#expect(odd.count == 3)
		#expect(abs(odd[0].x - (0.5 - odd[2].y)) < 1e-5)
		#expect(SpatialRouteGeometry.dashes(length: 0.05, dash: 0.1, gap: 0.05) == [SIMD2(0, 0.05)])
		#expect(SpatialRouteGeometry.dashes(length: 0, dash: 0.1, gap: 0.05).isEmpty)
	}

	@Test("Chevrons are spread inside the margins and wrap as they drift")
	func marks() {
		let marks = SpatialRouteGeometry.marks(length: 1, spacing: 0.2, margin: 0.1)
		#expect(marks.count == 4)
		#expect(abs(marks[0] - 0.2) < 1e-5)
		#expect(abs(marks[3] - 0.8) < 1e-5)
		let drifted = SpatialRouteGeometry.marks(length: 1, spacing: 0.2, margin: 0.1, phase: 0.15)
		#expect(drifted.count == 4)
		#expect(drifted.allSatisfy { $0 >= 0.1 && $0 <= 0.9 })
		#expect(abs(drifted[0] - 0.15) < 1e-5)
		#expect(SpatialRouteGeometry.marks(length: 0.1, spacing: 0.2, margin: 0.1) == [0.05])
	}

	@Test("A pill moves along its leg to clear nodes and other pills, or is left out")
	func pillPlacement() {
		let fractions = SpatialRouteGeometry.pillFractions(preferred: 0.5)
		#expect(zip(fractions, [0.5, 0.65, 0.35, 0.8, 0.2] as [Float]).allSatisfy { abs($0 - $1) < 1e-5 } && fractions.count == 5)
		// Spots too near either end are skipped.
		#expect(SpatialRouteGeometry.pillFractions(preferred: 0.35).count == 5)
		// Second item's first spot is on the first item's, so it takes its next one.
		let first: [SIMD3<Float>] = [[0, 0, 0]]
		let second: [SIMD3<Float>] = [[0.01, 0, 0], [0.1, 0, 0]]
		#expect(SpatialRouteGeometry.choose([first, second], minDistance: 0.05) == [0, 1])
		// Over a node, with nowhere else to go, it is left out.
		#expect(SpatialRouteGeometry.choose([first], minDistance: 0.05, obstacles: [[0, 0.01, 0]], clearance: 0.04) == [nil])
	}

	@Test("A leg is cut where it crosses the rim, through the zoom preview")
	func clip() {
		let clip = SpatialRouteClip(scale: 1, translation: .zero, radius: 1)
		#expect(clip.range(from: [0, 0, 0], to: [0.5, 0, 0]) == SIMD2(0, 1))
		let out = clip.range(from: [0, 0, 0], to: [2, 0, 0])
		#expect(abs((out?.y ?? 0) - 0.5) < 1e-5)
		let across = clip.range(from: [-2, 0, 0], to: [2, 0, 0])
		#expect(abs((across?.x ?? 0) - 0.25) < 1e-5 && abs((across?.y ?? 0) - 0.75) < 1e-5)
		#expect(clip.range(from: [2, 0, 2], to: [3, 0, 2]) == nil)
		// Zoomed 2× about the middle: x = 0.75 now shows at 1.5, past the rim.
		let zoomed = SpatialRouteClip(scale: 2, translation: .zero, radius: 1)
		#expect(!zoomed.isInside([0.75, 0, 0]))
		#expect(abs((zoomed.range(from: [0, 0, 0], to: [1, 0, 0])?.y ?? 0) - 0.5) < 1e-5)
	}

	@Test("A capped bar is a closed box and dashes add one per dash")
	func capped() {
		var mesh = SpatialMeshData()
		mesh.addCappedBar(from: [0, 0, 0], to: [0, 0, 1], width: 0.1)
		#expect(mesh.triangleCount == 12)
		#expect(mesh.positions.count == mesh.normals.count)
		var dashed = SpatialMeshData()
		dashed.addDashes(from: [0, 0, 0], to: [1, 0, 0], dashes: SpatialRouteGeometry.dashes(length: 1, dash: 0.1, gap: 0.05), width: 0.01)
		#expect(dashed.triangleCount == 7 * 12)
		#expect(dashed.positions.allSatisfy { $0.x >= -1e-5 && $0.x <= 1 + 1e-5 })
	}
}
