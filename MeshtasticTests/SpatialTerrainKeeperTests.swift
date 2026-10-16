//
//  SpatialTerrainKeeperTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//
import CoreLocation
import Foundation
import Testing
@testable import Meshtastic

@Suite("Spatial terrain app check")
struct SpatialTerrainKeeperTests {
	let start = Date(timeIntervalSince1970: 1_800_000_000)
	let seattle = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33)
	let tacoma = CLLocationCoordinate2D(latitude: 47.25, longitude: -122.44)
	let berlin = CLLocationCoordinate2D(latitude: 52.5, longitude: 13.4)

	func node(_ num: Int64, _ coordinate: CLLocationCoordinate2D, radio: Bool = false) -> SpatialNodeSnapshot {
		SpatialNodeSnapshot(
			id: num, coordinate: coordinate, altitude: nil, isPrecise: true, longName: "Node \(num)", shortName: "N\(num)",
			isOnline: true, lastHeard: start, isFavorite: false, viaMqtt: false, hopsAway: 0, snr: 6,
			isConnectedRadio: radio, role: nil
		)
	}

	// MARK: - Mesh area

	@Test func meshCircleLeavesOutNodesFarFromTheRadio() {
		let nodes = [node(1, seattle, radio: true), node(2, tacoma), node(3, berlin)]
		let fit = SpatialMapArea.fit(nodes)
		#expect(fit.nodes.map(\.id) == [1, 2])
		#expect(fit.outsideCount == 1)
		#expect(SpatialMapArea.meshCircle(nodes) == SpatialCircle.around([seattle, tacoma]))
	}

	@Test func pinnedNodesStayOnTheMap() {
		let nodes = [node(1, seattle, radio: true), node(3, berlin)]
		let fit = SpatialMapArea.fit(nodes, pinned: [3])
		#expect(fit.nodes.map(\.id) == [1, 3])
		#expect(fit.outsideCount == 0)
	}

	@Test func withoutARadioEveryNodeStays() {
		let nodes = [node(2, seattle), node(3, berlin)]
		#expect(SpatialMapArea.fit(nodes).nodes.count == 2)
		#expect(SpatialMapArea.meshCircle([]) == nil)
	}

	// MARK: - Schedule

	/// Runs the schedule through ticks of (seconds after start, connected radio, can check) and
	/// returns which ticks checked.
	func run(_ ticks: [Tick]) -> [Bool] {
		var schedule = SpatialTerrainCheckSchedule()
		return ticks.map { schedule.shouldCheck(now: start.addingTimeInterval($0.after), radio: $0.radio, canCheck: $0.canCheck) }
	}

	struct Tick {
		let after: TimeInterval
		let radio: Int64?
		let canCheck: Bool
		init(_ after: TimeInterval, _ radio: Int64?, _ canCheck: Bool) {
			self.after = after
			self.radio = radio
			self.canCheck = canCheck
		}
	}

	@Test func firstTickChecksThenWaitsForTheInterval() {
		let interval = SpatialTerrainCheckSchedule.interval
		#expect(run([Tick(0, 1, true), Tick(60, 1, true), Tick(interval, 1, true)]) == [true, false, true])
	}

	@Test func withoutARadioOnlyTheLaunchCheckRuns() {
		#expect(run([Tick(0, nil, true), Tick(3_600, nil, true)]) == [true, false])
	}

	@Test func aNewConnectionChecksSoon() {
		// Reconnecting, even to the same radio, checks again.
		#expect(run([Tick(0, nil, true), Tick(30, 1, true), Tick(60, 1, true), Tick(90, nil, true), Tick(120, 1, true)]) == [true, true, false, false, true])
	}

	@Test func aBlockedTickKeepsTheCheckPending() {
		// Connected while the volume was open: the check waits for it to close.
		#expect(run([Tick(0, nil, true), Tick(30, 1, false), Tick(60, 1, true)]) == [true, false, true])
	}

	@Test func anUndoneCheckRunsAgainOnTheNextTick() {
		var schedule = SpatialTerrainCheckSchedule()
		let first = schedule.shouldCheck(now: start, radio: 1, canCheck: true)
		#expect(first)
		schedule.undoLastCheck()
		#expect(schedule.lastCheck == nil)
		let retry = schedule.shouldCheck(now: start.addingTimeInterval(30), radio: 1, canCheck: true)
		#expect(retry)
		// A check that read the mesh, even with no nodes, isn't undone, so the interval holds.
		let after = schedule.shouldCheck(now: start.addingTimeInterval(60), radio: 1, canCheck: true)
		#expect(!after)
	}

	@Test func undoingALaterCheckKeepsTheEarlierOne() {
		let interval = SpatialTerrainCheckSchedule.interval
		var schedule = SpatialTerrainCheckSchedule()
		let first = schedule.shouldCheck(now: start, radio: 1, canCheck: true)
		let second = schedule.shouldCheck(now: start.addingTimeInterval(interval), radio: 1, canCheck: true)
		#expect(first && second)
		schedule.undoLastCheck()
		#expect(schedule.lastCheck == start)
		let retry = schedule.shouldCheck(now: start.addingTimeInterval(interval + 30), radio: 1, canCheck: true)
		#expect(retry)
		// Undo only takes back one check.
		schedule.undoLastCheck()
		schedule.undoLastCheck()
		#expect(schedule.lastCheck == start)
	}
}
