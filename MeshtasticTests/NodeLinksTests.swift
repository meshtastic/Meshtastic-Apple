//
//  NodeLinksTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//

import CoreLocation
import MapKit
import Testing
@testable import Meshtastic

@Suite("Node links")
struct NodeLinksTests {

	private let now = Date(timeIntervalSince1970: 1_800_000_000)
	private let radio: Int64 = 0x5000
	private let nodeA: Int64 = 0x1000
	private let nodeB: Int64 = 0x7000
	private let nodeC: Int64 = 0x9000

	private var positions: [Int64: CLLocationCoordinate2D] {
		[
			radio: CLLocationCoordinate2D(latitude: 47.60, longitude: -122.33),
			nodeA: CLLocationCoordinate2D(latitude: 47.62, longitude: -122.35),
			nodeB: CLLocationCoordinate2D(latitude: 47.58, longitude: -122.30),
			nodeC: CLLocationCoordinate2D(latitude: 47.65, longitude: -122.40)
		]
	}

	private func row(_ num: Int64, hops: Int32 = 0, mqtt: Bool = false, snr: Float = 6, heardAgo: TimeInterval? = 600) -> NodeLinkNodeRow {
		NodeLinkNodeRow(num: num, hopsAway: hops, viaMqtt: mqtt, snr: snr, lastHeard: heardAgo.map { now.addingTimeInterval(-$0) })
	}

	private func hours(_ value: Double) -> TimeInterval { value * 60 * 60 }

	// MARK: Direct observations

	@Test func keepsOnlyNodesHeardDirectly() {
		let rows = [
			row(nodeA),
			row(nodeB, hops: 2),
			row(nodeC, mqtt: true),
			row(0x2222, snr: 0),
			row(0x3333, heardAgo: nil),
			row(radio)
		]
		let observations = NodeLinks.directObservations(connectedNum: radio, nodes: rows, now: now)
		#expect(observations.map(\.heard) == [nodeA])
		#expect(observations.first?.observer == radio)
		#expect(observations.first?.snr == 6)
	}

	@Test func dropsNodesHeardMoreThanTwelveHoursAgo() {
		let rows = [row(nodeA, heardAgo: hours(11.9)), row(nodeB, heardAgo: hours(12)), row(nodeC, heardAgo: hours(12.1))]
		let observations = NodeLinks.directObservations(connectedNum: radio, nodes: rows, now: now)
		#expect(Set(observations.map(\.heard)) == [nodeA, nodeB])
	}

	// MARK: Links

	@Test func oneLinkPerNodeWithTheRadio() {
		let observations = NodeLinks.directObservations(connectedNum: radio, nodes: [row(nodeA, snr: -3), row(nodeB, snr: 8)], now: now)
		let links = NodeLinks.links(from: observations, positions: positions, now: now)
		#expect(links.count == 2)
		// The lower node number is always `a`, so the radio's measurement lands on its own side.
		let toA = links.first { $0.b == radio }
		#expect(toA?.a == nodeA)
		#expect(toA?.snrAtB == -3)
		#expect(toA?.snrAtA == nil)
		let toB = links.first { $0.b == nodeB }
		#expect(toB?.a == radio)
		#expect(toB?.snrAtA == 8)
		#expect(toB?.snrAtB == nil)
		#expect(links.allSatisfy { $0.isOneWay })
	}

	@Test func skipsNodesWithoutAPosition() {
		var positions = positions
		positions[nodeB] = nil
		let observations = NodeLinks.directObservations(connectedNum: radio, nodes: [row(nodeA), row(nodeB)], now: now)
		let links = NodeLinks.links(from: observations, positions: positions, now: now)
		#expect(links.map(\.id) == ["\(nodeA)-\(radio)"])
	}

	@Test func noLinksWhenTheRadioHasNoPosition() {
		var positions = positions
		positions[radio] = nil
		let observations = NodeLinks.directObservations(connectedNum: radio, nodes: [row(nodeA), row(nodeB)], now: now)
		#expect(NodeLinks.links(from: observations, positions: positions, now: now).isEmpty)
	}

	@Test func bothDirectionsMakeOneLink() {
		let observations = [
			NodeLinkObservation(observer: radio, heard: nodeB, snr: 7, heardAt: now.addingTimeInterval(-hours(3))),
			NodeLinkObservation(observer: nodeB, heard: radio, snr: -9, heardAt: now.addingTimeInterval(-hours(1)))
		]
		let links = NodeLinks.links(from: observations, positions: positions, now: now)
		#expect(links.count == 1)
		let link = links[0]
		#expect(link.snrAtA == 7)
		#expect(link.snrAtB == -9)
		#expect(!link.isOneWay)
		#expect(link.worstSnr == -9)
		// The age comes from the newer of the two measurements.
		#expect(link.age == hours(1))
	}

	@Test func newestReportForADirectionWins() {
		let observations = [
			NodeLinkObservation(observer: radio, heard: nodeB, snr: 1, heardAt: now.addingTimeInterval(-hours(5))),
			NodeLinkObservation(observer: radio, heard: nodeB, snr: 4, heardAt: now.addingTimeInterval(-hours(2))),
			NodeLinkObservation(observer: radio, heard: nodeB, snr: 2, heardAt: now.addingTimeInterval(-hours(4)))
		]
		let links = NodeLinks.links(from: observations, positions: positions, now: now)
		#expect(links.count == 1)
		#expect(links[0].snrAtA == 4)
		#expect(links[0].age == hours(2))
	}

	@Test func dropsOldAndSelfObservations() {
		let observations = [
			NodeLinkObservation(observer: radio, heard: nodeB, snr: 4, heardAt: now.addingTimeInterval(-hours(13))),
			NodeLinkObservation(observer: radio, heard: radio, snr: 4, heardAt: now)
		]
		#expect(NodeLinks.links(from: observations, positions: positions, now: now).isEmpty)
	}

	@Test func newestLinksComeFirst() {
		let rows = [row(nodeA, heardAgo: hours(6)), row(nodeB, heardAgo: hours(1)), row(nodeC, heardAgo: hours(3))]
		let observations = NodeLinks.directObservations(connectedNum: radio, nodes: rows, now: now)
		let links = NodeLinks.links(from: observations, positions: positions, now: now)
		#expect(links.map(\.age) == [hours(1), hours(3), hours(6)])
	}

	// MARK: Age

	@Test func opacityIsFullForTwoHoursThenFades() {
		#expect(NodeLinks.opacity(forAge: 0) == 1)
		#expect(NodeLinks.opacity(forAge: hours(2)) == 1)
		#expect(NodeLinks.opacity(forAge: hours(7)) < 1)
		#expect(NodeLinks.opacity(forAge: hours(7)) > NodeLinks.minOpacity)
		#expect(abs(NodeLinks.opacity(forAge: hours(12)) - NodeLinks.minOpacity) < 0.0001)
		#expect(NodeLinks.opacity(forAge: hours(4)) > NodeLinks.opacity(forAge: hours(8)))
	}

	// MARK: Pills

	@Test func pillSitsNearTheNodeThatMeasuredIt() throws {
		let observations = [
			NodeLinkObservation(observer: radio, heard: nodeB, snr: 7, heardAt: now),
			NodeLinkObservation(observer: nodeB, heard: radio, snr: -2, heardAt: now)
		]
		let layout = NodeLinkMapLayout(links: NodeLinks.links(from: observations, positions: positions, now: now))
		#expect(layout.labels.count == 2)
		let atRadio = try #require(layout.labels.first { $0.snr == 7 })
		let atB = try #require(layout.labels.first { $0.snr == -2 })
		let radioPoint = MKMapPoint(positions[radio]!), bPoint = MKMapPoint(positions[nodeB]!)
		#expect(MKMapPoint(atRadio.coordinate).distance(to: radioPoint) < MKMapPoint(atRadio.coordinate).distance(to: bPoint))
		#expect(MKMapPoint(atB.coordinate).distance(to: bPoint) < MKMapPoint(atB.coordinate).distance(to: radioPoint))
	}

	@Test func pillsHideWhenZoomedOut() {
		let observations = NodeLinks.directObservations(connectedNum: radio, nodes: [row(nodeA)], now: now)
		let layout = NodeLinkMapLayout(links: NodeLinks.links(from: observations, positions: positions, now: now))
		let close = TraceRouteMapLayout.mapRect(for: MKCoordinateRegion(
			center: positions[radio]!, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
		let far = TraceRouteMapLayout.mapRect(for: MKCoordinateRegion(
			center: positions[radio]!, span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)))
		#expect(layout.visibleLabels(in: close).count == 1)
		#expect(layout.visibleLabels(in: far).isEmpty)
	}

	// MARK: Neighbor Info reports

	private func report(_ reporter: Int64, _ neighbor: Int64, snr: Float = 5, ago: TimeInterval = 600, mqtt: Bool = false) -> NodeLinkReportRow {
		NodeLinkReportRow(reporter: reporter, neighbor: neighbor, snr: snr, receivedAt: now.addingTimeInterval(-ago), viaMqtt: mqtt)
	}

	@Test func reportsBecomeObservationsByTheReporter() {
		let observations = NodeLinks.reportedObservations([report(nodeA, nodeC, snr: -4)], now: now)
		#expect(observations == [NodeLinkObservation(observer: nodeA, heard: nodeC, snr: -4, heardAt: now.addingTimeInterval(-600), source: .neighborReport)])
	}

	@Test func reportsSkipMqttSelfZeroAndOld() {
		let rows = [
			report(nodeA, nodeC, mqtt: true),
			report(nodeA, nodeA),
			report(nodeA, 0),
			report(0, nodeC),
			report(nodeB, nodeC, ago: hours(24.1)),
			report(nodeB, nodeA, ago: hours(23.9))
		]
		let observations = NodeLinks.reportedObservations(rows, now: now)
		#expect(observations.map(\.observer) == [nodeB])
		#expect(observations.map(\.heard) == [nodeA])
	}

	@Test func twoReportsOfOnePairMakeOneSolidLink() throws {
		let observations = NodeLinks.reportedObservations([report(nodeA, nodeC, snr: 3), report(nodeC, nodeA, snr: -6)], now: now)
		let links = NodeLinks.links(from: observations, positions: positions, now: now)
		let link = try #require(links.first)
		#expect(links.count == 1)
		#expect(link.a == nodeA && link.b == nodeC)
		#expect(link.snrAtA == 3)
		#expect(link.snrAtB == -6)
		#expect(!link.isOneWay)
		#expect(link.worstSnr == -6)
	}

	@Test func radioHearingANodeAndTheNodesReportMakeOneLink() throws {
		// The radio hears nodeB directly, and nodeB's report says it hears the radio.
		let direct = NodeLinks.directObservations(connectedNum: radio, nodes: [row(nodeB, snr: 8, heardAgo: hours(1))], now: now)
		let reported = NodeLinks.reportedObservations([report(nodeB, radio, snr: -2, ago: hours(3))], now: now)
		let links = NodeLinks.links(from: direct + reported, positions: positions, now: now)
		let link = try #require(links.first)
		#expect(links.count == 1)
		#expect(link.a == radio && link.b == nodeB)
		#expect(link.snrAtA == 8)
		#expect(link.snrAtB == -2)
		#expect(!link.isOneWay)
		#expect(link.age == hours(1))
	}

	@Test func radioHearingANodeAndItsOwnReportShareADirection() {
		// The radio's own report lists nodeB too; the newer of the two readings wins.
		let direct = NodeLinks.directObservations(connectedNum: radio, nodes: [row(nodeB, snr: 8, heardAgo: hours(5))], now: now)
		let reported = NodeLinks.reportedObservations([report(radio, nodeB, snr: 2, ago: hours(1))], now: now)
		let links = NodeLinks.links(from: direct + reported, positions: positions, now: now)
		#expect(links.count == 1)
		#expect(links.first?.snrAtA == 2)
		#expect(links.first?.snrAtB == nil)
		#expect(links.first?.isOneWay == true)
	}

	@Test func reportedLinksDontNeedTheRadiosPosition() {
		var positions = positions
		positions[radio] = nil
		let direct = NodeLinks.directObservations(connectedNum: radio, nodes: [row(nodeA)], now: now)
		let reported = NodeLinks.reportedObservations([report(nodeA, nodeC)], now: now)
		let links = NodeLinks.links(from: direct + reported, positions: positions, now: now)
		#expect(links.map(\.id) == ["\(nodeA)-\(nodeC)"])
	}

	@Test func reportedLinksSkipNodesWithoutAPosition() {
		var positions = positions
		positions[nodeC] = nil
		let reported = NodeLinks.reportedObservations([report(nodeA, nodeC), report(nodeA, nodeB)], now: now)
		let links = NodeLinks.links(from: reported, positions: positions, now: now)
		#expect(links.map(\.id) == ["\(nodeA)-\(nodeB)"])
	}

	@Test func reportedLinksOutlastTheRadiosOwn() {
		// At 13 hours a direct reading is gone but a report is still shown.
		let direct = NodeLinkObservation(observer: radio, heard: nodeA, snr: 4, heardAt: now.addingTimeInterval(-hours(13)))
		let reported = NodeLinks.reportedObservations([report(nodeB, nodeC, ago: hours(13))], now: now)
		let links = NodeLinks.links(from: [direct] + reported, positions: positions, now: now)
		#expect(links.map(\.id) == ["\(nodeB)-\(nodeC)"])
	}

	@Test func reportOpacityIsFullForSevenHoursThenFadesToADay() {
		let source = NodeLinkObservation.Source.neighborReport
		#expect(NodeLinks.opacity(forAge: hours(6.9), source: source) == 1)
		#expect(NodeLinks.opacity(forAge: hours(12), source: source) < 1)
		#expect(NodeLinks.opacity(forAge: hours(12), source: source) > NodeLinks.opacity(forAge: hours(20), source: source))
		#expect(abs(NodeLinks.opacity(forAge: hours(24), source: source) - NodeLinks.minOpacity) < 0.0001)
	}

	@Test func eachDirectionFadesOnItsOwn() throws {
		// A fresh direct reading and a 20 hour old report on the same pair.
		let direct = NodeLinks.directObservations(connectedNum: radio, nodes: [row(nodeB, snr: 8, heardAgo: 0)], now: now)
		let reported = NodeLinks.reportedObservations([report(nodeB, radio, snr: -2, ago: hours(20))], now: now)
		let link = try #require(NodeLinks.links(from: direct + reported, positions: positions, now: now).first)
		#expect(link.opacityAtA == 1)
		#expect(link.opacityAtB < 0.5)
		#expect(link.opacity == 1)
		let layout = NodeLinkMapLayout(links: [link])
		#expect(layout.labels.first { $0.snr == 8 }?.opacity == 1)
		#expect((layout.labels.first { $0.snr == -2 }?.opacity ?? 1) < 0.5)
	}
}
