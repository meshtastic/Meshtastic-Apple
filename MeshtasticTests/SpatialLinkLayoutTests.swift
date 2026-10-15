//
//  SpatialLinkLayoutTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//
import CoreLocation
import Foundation
import Testing
@testable import Meshtastic

/// The spatial map's direct links: which links the nodes on the map and saved Neighbor Info
/// make, and which of them get SNR pills.
@Suite("Spatial map direct links")
struct SpatialLinkLayoutTests {

	let now = Date(timeIntervalSince1970: 1_800_000_000)
	let radio: Int64 = 1

	func node(_ num: Int64, hops: Int = 0, snr: Float = 6, heard: TimeInterval = 600, viaMqtt: Bool = false) -> SpatialNodeSnapshot {
		SpatialNodeSnapshot(
			id: num, coordinate: CLLocationCoordinate2D(latitude: 47.6 + Double(num) * 0.01, longitude: -122.3),
			altitude: nil, isPrecise: true, longName: "Node \(num)", shortName: "N\(num)", isOnline: true,
			lastHeard: now.addingTimeInterval(-heard), isFavorite: false, viaMqtt: viaMqtt, hopsAway: hops, snr: snr,
			isConnectedRadio: num == radio, role: nil
		)
	}

	func report(_ reporter: Int64, _ neighbor: Int64, snr: Float, age: TimeInterval = 3600) -> NodeLinkReportRow {
		NodeLinkReportRow(reporter: reporter, neighbor: neighbor, snr: snr, receivedAt: now.addingTimeInterval(-age), viaMqtt: false)
	}

	@Test func radioLinksComeFromNodesItHearsDirectly() {
		let nodes = [node(radio, snr: 0), node(2, snr: 7), node(3, hops: 2), node(4, viaMqtt: true)]
		let links = SpatialLinkLayout.links(nodes: nodes, connectedNum: radio, reports: [], now: now)
		#expect(links.map(\.id) == ["1-2"])
		#expect(links.first?.snrAtA == 7)
		#expect(links.first?.snrAtB == nil)
		#expect(links.first?.isOneWay == true)
	}

	@Test func reportsMakeLinksBetweenOtherNodesOnTheMap() {
		let nodes = [node(radio, snr: 0), node(2, hops: 1), node(3, hops: 1)]
		let reports = [report(2, 3, snr: -4), report(3, 2, snr: 1), report(2, 9, snr: 5)]
		let links = SpatialLinkLayout.links(nodes: nodes, connectedNum: radio, reports: reports, now: now)
		#expect(links.count == 1, "node 9 isn't on the map")
		let link = links.first
		#expect(link?.id == "2-3")
		#expect(link?.isOneWay == false)
		#expect(link?.worstSnr == -4)
	}

	@Test func withNoConnectedRadioOnlyReportsCount() {
		let nodes = [node(2, snr: 7), node(3, hops: 1)]
		let links = SpatialLinkLayout.links(nodes: nodes, connectedNum: nil, reports: [report(2, 3, snr: 2)], now: now)
		#expect(links.map(\.id) == ["2-3"])
	}

	@Test func opacityIsRoundedToQuarterStepsAndUnknownDirectionsAreZero() {
		// 8 h is 60% through the radio's 2 h to 12 h fade: 1 - 0.6 * 0.75 = 0.55, which rounds to 0.5.
		let nodes = [node(radio, snr: 0), node(2, snr: 7, heard: 8 * 60 * 60)]
		let link = SpatialLinkLayout.links(nodes: nodes, connectedNum: radio, reports: [], now: now).first
		#expect(link?.opacityAtA == 0.5)
		#expect(link?.opacityAtB == 0)
		#expect(link?.opacity == 0.5)
		#expect(SpatialLinkLayout.quarterStep(0.9) == 1)
		#expect(SpatialLinkLayout.quarterStep(0.1) == 0.25)
	}

	@Test func unchangedInputGivesEqualLinks() {
		let nodes = [node(radio, snr: 0), node(2, snr: 7), node(3, hops: 1)]
		let reports = [report(2, 3, snr: 2)]
		let first = SpatialLinkLayout.links(nodes: nodes, connectedNum: radio, reports: reports, now: now)
		let second = SpatialLinkLayout.links(nodes: nodes, connectedNum: radio, reports: reports, now: now.addingTimeInterval(2))
		#expect(first == second, "a refresh two seconds later doesn't rebuild the lines")
	}

	func link(_ a: Int64, _ b: Int64, atA: Float? = 3, atB: Float? = 3) -> SpatialLinkSnapshot {
		SpatialLinkSnapshot(a: a, b: b, snrAtA: atA, snrAtB: atB, opacityAtA: atA == nil ? 0 : 1, opacityAtB: atB == nil ? 0 : 1)
	}

	@Test func pillsSitNextToTheNodeThatMeasured() {
		let pills = SpatialLinkLayout.pills(for: [link(2, 3, atA: -5, atB: nil)], selected: nil, connected: nil)
		#expect(pills.count == 1)
		#expect(pills.first?.atNum == 2)
		#expect(pills.first?.otherNum == 3)
		#expect(pills.first?.snr == -5)
		#expect(pills.first?.id == "2-3-2")
	}

	@Test func aSelectedNodeGetsOnlyItsOwnPills() {
		let links = [link(2, 3), link(3, 4), link(5, 6)]
		let pills = SpatialLinkLayout.pills(for: links, selected: 3, connected: radio)
		#expect(Set(pills.map(\.linkID)) == ["2-3", "3-4"])
		#expect(pills.count == 4)
	}

	@Test func withNothingSelectedTheRadioLinksComeFirstUpToTheLimit() {
		let links = [link(5, 6), link(7, 8), link(1, 2), link(1, 3)]
		let pills = SpatialLinkLayout.pills(for: links, selected: nil, connected: radio, limit: 5)
		#expect(pills.count == 5)
		#expect(pills.prefix(4).allSatisfy { $0.linkID.hasPrefix("1-") })
		#expect(pills.last?.linkID == "5-6")
	}
}
