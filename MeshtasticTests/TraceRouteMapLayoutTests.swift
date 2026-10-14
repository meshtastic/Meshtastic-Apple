//
//  TraceRouteMapLayoutTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import CoreLocation
import MapKit
import Testing
@testable import Meshtastic

@Suite("Trace route map layout")
struct TraceRouteMapLayoutTests {

	private let origin: Int64 = 0x0A1B_2C3D
	private let relayA: Int64 = 0x3333_4444
	private let relayB: Int64 = 0x5555_6666
	private let target: Int64 = 0x1111_2222

	/// Origin, relay A, relay B and target about 2.2 km apart along a line of latitude.
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
	) -> TraceRouteMapLayout {
		let legs = TraceRouteLegs(
			originNum: origin,
			targetNum: target,
			forwardHops: forward,
			backRelays: back,
			originBackSnr: originBackSnr,
			hasBack: true,
			preset: .longFast,
			positions: positions ?? self.positions,
			lookup: { _ in nil }
		)
		return TraceRouteMapLayout(legs: legs, positions: positions ?? self.positions)
	}

	private var threeLegForward: [TraceRouteLegs.Hop] {
		[.init(num: origin, snr: 4), .init(num: relayA, snr: 7), .init(num: relayB, snr: -2.5), .init(num: target, snr: 1)]
	}

	private func region(spanLongitude: Double) -> MKMapRect {
		TraceRouteMapLayout.mapRect(for: MKCoordinateRegion(
			center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.355),
			span: MKCoordinateSpan(latitudeDelta: spanLongitude * 0.6, longitudeDelta: spanLongitude)
		))
	}

	@Test("Each leg gets a label at its midpoint with the SNR of the node it arrives at")
	func labelsAtMidpoints() {
		let result = layout(forward: threeLegForward)
		#expect(result.labels.map(\.snr) == [7, -2.5, 1])
		let first = result.labels[0]
		#expect(abs(first.coordinate.longitude - -122.385) < 0.000_1)
		#expect(abs(first.coordinate.latitude - 47.6) < 0.000_1)
	}

	@Test("Legs with an unknown SNR get no label but are still drawn")
	func unknownSnrHasNoLabel() {
		let forward: [TraceRouteLegs.Hop] = [.init(num: origin, snr: 4), .init(num: relayA, snr: TraceRouteLegs.unknownSnr), .init(num: target, snr: 3)]
		let result = layout(forward: forward)
		#expect(result.segments.count == 2)
		#expect(result.segments[0].snr == nil)
		#expect(result.labels.map(\.snr) == [3])
	}

	@Test("Relays are numbered in each direction and the endpoints get no badge")
	func badgeNumbers() {
		let result = layout(forward: threeLegForward, back: [.init(num: relayB, snr: 2), .init(num: relayA, snr: 3)])
		#expect(result.badges.filter { !$0.isBack }.map(\.number) == [1, 2])
		#expect(result.badges.filter { $0.isBack }.map(\.number) == [1, 2])
		#expect(result.badges.first { $0.isBack && $0.number == 1 }?.coordinate.longitude == positions[relayB]?.longitude)
	}

	@Test("A relay without a position keeps its number gap and the line spans it")
	func relayWithoutPosition() {
		var positions = self.positions
		positions[relayA] = nil
		let result = layout(forward: threeLegForward, positions: positions)
		#expect(result.badges.map(\.number) == [2])
		#expect(result.segments.map(\.fromNum) == [origin, relayB])
		#expect(result.segments.map(\.toNum) == [relayB, target])
	}

	@Test("The unknown repeater gets no badge or line end")
	func unknownRepeater() {
		let forward: [TraceRouteLegs.Hop] = [.init(num: origin, snr: 4), .init(num: TraceRouteLegs.unknownRepeaterNum, snr: 5), .init(num: target, snr: 6)]
		let result = layout(forward: forward)
		#expect(result.badges.isEmpty)
		#expect(result.segments.count == 1)
		#expect(result.segments[0].fromNum == origin && result.segments[0].toNum == target)
	}

	@Test("A direct return isn't drawn; a return through relays is, with the originator's SNR on the last leg")
	func returnPath() {
		let direct = layout(forward: threeLegForward)
		#expect(direct.segments.allSatisfy { !$0.isBack })
		let relayed = layout(forward: threeLegForward, back: [.init(num: relayB, snr: 2)], originBackSnr: -6)
		let back = relayed.segments.filter(\.isBack)
		#expect(back.map(\.fromNum) == [target, relayB])
		#expect(back.map(\.toNum) == [relayB, origin])
		#expect(back.map(\.snr) == [2, -6])
	}

	@Test("Labels on a leg drawn both ways move apart instead of sharing the midpoint")
	func sharedLegLabelsSeparate() {
		let forward: [TraceRouteLegs.Hop] = [.init(num: origin, snr: 4), .init(num: relayA, snr: 7), .init(num: target, snr: 1)]
		let result = layout(forward: forward, back: [.init(num: relayA, snr: 2)], originBackSnr: 5)
		let outbound = result.labels.first { !$0.isBack && $0.snr == 7 }
		let inbound = result.labels.first { $0.isBack && $0.snr == 5 }
		// Origin → relay A: 35% of the way from the origin; relay A → origin: 35% of the way from relay A.
		#expect(abs((outbound?.coordinate.longitude ?? 0) - -122.3895) < 0.000_1)
		#expect(abs((inbound?.coordinate.longitude ?? 0) - -122.3805) < 0.000_1)
	}

	@Test("Only legs used in both directions count as shared")
	func sharedLegs() {
		let relayed = layout(forward: threeLegForward, back: [.init(num: relayB, snr: 2)], originBackSnr: -6)
		let shared = relayed.segments.filter { relayed.sharesLeg($0) }.map { "\($0.fromNum)>\($0.toNum)" }
		// Relay B ↔ target is used both ways; origin → A → B out and B → origin back are not.
		#expect(shared == ["\(relayB)>\(target)", "\(target)>\(relayB)"])
	}

	@Test("Zoomed out, legs too short for a label are hidden; zoomed in, all show")
	func labelsByZoom() {
		let result = layout(forward: threeLegForward)
		// Each leg is 0.03° of longitude. At a 0.1° wide view that's 30% of the width.
		#expect(result.visibleLabels(in: region(spanLongitude: 0.1)).count == 3)
		// At 1° each leg is 3% of the width, under the 20% threshold.
		#expect(result.visibleLabels(in: region(spanLongitude: 1)).isEmpty)
	}

	@Test("Badges that would overlap at the current zoom are thinned, forward and return separately")
	func badgesByZoom() {
		let result = layout(forward: threeLegForward, back: [.init(num: relayB, snr: 2), .init(num: relayA, snr: 3)])
		// Zoomed in: relays are 30% of the width apart, all four badges show.
		#expect(result.visibleBadges(in: region(spanLongitude: 0.1)).count == 4)
		// Zoomed far out: relays are 0.3% apart, so one badge per direction remains.
		let far = result.visibleBadges(in: region(spanLongitude: 10))
		#expect(far.filter { !$0.isBack }.map(\.number) == [1])
		#expect(far.filter { $0.isBack }.map(\.number) == [1])
	}

	@Test("The map rect for a region spans its width in map points")
	func mapRectForRegion() {
		let rect = region(spanLongitude: 1)
		#expect(abs(rect.width - MKMapSize.world.width / 360) < 1)
		#expect(rect.height > 0)
	}
}
