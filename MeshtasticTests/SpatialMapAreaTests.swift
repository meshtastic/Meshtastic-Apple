//
//  SpatialMapAreaTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation
import Testing
@testable import Meshtastic

@Suite("Spatial map area and routes")
struct SpatialMapAreaTests {
	let seattle = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33)

	@Test func farNodesAreLeftOutAroundTheAnchor() {
		let berlin = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)
		let tacoma = CLLocationCoordinate2D(latitude: 47.25, longitude: -122.44)
		let selection = SpatialMapArea.select([seattle, tacoma, berlin], anchor: seattle)
		#expect(selection.coordinates.count == 2)
		#expect(selection.outsideCount == 1)
	}

	@Test func circleIsKeptUntilANodeLeavesOrTheMeshShrinks() {
		let now = Date()
		let wide = SpatialCircle.around([seattle, CLLocationCoordinate2D(latitude: 47.9, longitude: -122.0)])!
		let tight = SpatialCircle.around([seattle])!
		#expect(SpatialMapArea.next(current: nil, candidate: wide, nodes: [seattle], lastChange: nil, now: now) == wide)
		#expect(SpatialMapArea.next(current: wide, candidate: wide, nodes: [seattle], lastChange: now, now: now) == nil, "nothing changed")
		let outside = CLLocationCoordinate2D(latitude: 48.5, longitude: -122.33)
		#expect(SpatialMapArea.next(current: wide, candidate: wide, nodes: [outside], lastChange: now, now: now) == wide, "a node outside forces a rebuild")
		#expect(SpatialMapArea.next(current: wide, candidate: tight, nodes: [seattle], lastChange: now, now: now) == nil, "a shrink waits")
		#expect(SpatialMapArea.next(current: wide, candidate: tight, nodes: [seattle], lastChange: now.addingTimeInterval(-60), now: now) == tight, "a shrink rebuilds after the interval")
	}

	@Test func aNodeInTheBoxCornerButOutsideTheCircleRebuilds() {
		let now = Date()
		let circle = SpatialCircle(latitude: 47.6, longitude: -122.33, radiusMeters: 10_000)
		// Northeast, inside the square around the circle but about 13 km from its center.
		let corner = CLLocationCoordinate2D(latitude: 47.6 + 9_000 / SpatialFrame.metersPerDegreeLatitude, longitude: -122.33 + 9_000 / circle.metersPerDegreeLongitude)
		#expect(circle.bounds.contains(corner))
		#expect(!circle.contains(corner))
		#expect(SpatialMapArea.next(current: circle, candidate: circle, nodes: [seattle, corner], lastChange: now, now: now) != nil)
		// Shrinking to just over half does not rebuild, even after the interval.
		let slightlySmaller = SpatialCircle(latitude: 47.6, longitude: -122.33, radiusMeters: 5_500)
		#expect(SpatialMapArea.next(current: circle, candidate: slightlySmaller, nodes: [seattle], lastChange: now.addingTimeInterval(-60), now: now) == nil)
	}

	@Test func linksKeepTheLatestSnrPerDirection() {
		func point(_ num: Int64, snr: Float) -> SpatialRouteSnapshot.Point {
			SpatialRouteSnapshot.Point(num: num, coordinate: seattle, altitude: 0, snr: snr)
		}
		let older = SpatialRouteSnapshot(id: 1, fromNum: 1, toNum: 3, targetName: "c", time: Date(timeIntervalSince1970: 100),
										 forward: [point(1, snr: 0), point(2, snr: -5), point(3, snr: 2)],
										 back: [point(3, snr: 0), point(2, snr: 7), point(1, snr: 4)])
		let newer = SpatialRouteSnapshot(id: 2, fromNum: 1, toNum: 2, targetName: "b", time: Date(timeIntervalSince1970: 200),
										 forward: [point(1, snr: 0), point(2, snr: 9)], back: [])
		let links = SpatialRouteSource.links(from: [older, newer])
		#expect(links.count == 2)
		let oneTwo = links.first { $0.a == 1 && $0.b == 2 }
		#expect(oneTwo?.snrAtoB == 9, "the newer route wins the 1→2 direction")
		#expect(oneTwo?.snrBtoA == 4, "2→1 was only heard on the older return path")
		let twoThree = links.first { $0.a == 2 && $0.b == 3 }
		#expect(twoThree?.snrAtoB == 2 && twoThree?.snrBtoA == 7)
	}

	@Test func flyoverCruisesThenLandsAndHolds() {
		var flyover = SpatialFlyover(legs: [[SIMD3(0, 0, 0), SIMD3(0.4, 0, 0)], [SIMD3(0.4, 0, 0), SIMD3(0.4, 0, 0.4)]])
		#expect(flyover.legs.count == 2)
		#expect(flyover.legs[0].duration == 5, "0.4 m at 0.08 m/s")
		let quarter = flyover.advance(by: 1.25)
		#expect(quarter != nil && abs(quarter!.x - 0.4 * Float(SpatialFlyover.eased(0.25))) < 1e-4)
		#expect(SpatialFlyover.eased(0.25) > 0.25, "cruise runs a little faster than linear to make room for the landing")
		#expect(abs(SpatialFlyover.eased(1) - 1) < 1e-9)
		_ = flyover.advance(by: 10)
		#expect(flyover.legIndex == 0 && flyover.holdRemaining > 0, "holds at the end of the first leg")
		_ = flyover.advance(by: SpatialFlyover.landingHold + 0.1)
		#expect(flyover.legIndex == 1)
		_ = flyover.advance(by: 100)
		_ = flyover.advance(by: 100)
		#expect(flyover.isFinished)
		#expect(flyover.advance(by: 1) == nil)
	}
}
