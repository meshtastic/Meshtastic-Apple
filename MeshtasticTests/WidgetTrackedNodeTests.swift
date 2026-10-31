//
//  WidgetTrackedNodeTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
import Foundation
import Testing
@testable import Meshtastic

/// A Node Tracker widget's node that leaves the node database keeps the name it
/// last had, and snapshots from before the missing list still decode.
@Suite("Widget tracked nodes")
struct WidgetTrackedNodeTests {
	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	private func snapshot(nodes: [NodeSnapshot], missing: [MissingNodeSnapshot]? = nil) -> WidgetSnapshot {
		WidgetSnapshot(
			generatedAt: now, connectionState: .connected, radioNodeNum: 1,
			radioLongName: nil, radioShortName: nil, radioBatteryLevel: nil, localStats: nil,
			nodes: nodes, totalNodeCount: nodes.count, unreadChannelMessages: 0,
			unreadDirectMessages: 0, recentMessages: [], missingTrackedNodes: missing
		)
	}

	private func node(_ num: Int64, long: String, short: String) -> NodeSnapshot {
		NodeSnapshot(
			num: num, longName: long, shortName: short, colorSeed: UInt32(num),
			batteryLevel: nil, snr: nil, rssi: nil, signalRating: nil,
			lastHeard: now, isOnline: true, hopsAway: 0,
			latitude: nil, longitude: nil, isFavorite: false
		)
	}

	@Test func keepsTheNameFromTheLastSnapshot() {
		let previous = snapshot(nodes: [node(0x1A2B3C4D, long: "Ridge Repeater", short: "RDGE")])
		let missing = WidgetDataBroker.missingTrackedNodes([0x1A2B3C4D], previous: previous)
		#expect(missing.first?.longName == "Ridge Repeater")
		#expect(missing.first?.shortName == "RDGE")
	}

	@Test func keepsTheNameWhileItStaysMissing() {
		let previous = snapshot(nodes: [], missing: [MissingNodeSnapshot(num: 7, longName: "Base Camp", shortName: "BASE")])
		let missing = WidgetDataBroker.missingTrackedNodes([7], previous: previous)
		#expect(missing.first?.longName == "Base Camp")
	}

	@Test func aNodeNeverSeenGetsItsHexName() {
		let missing = WidgetDataBroker.missingTrackedNodes([0x1A2B3C4D], previous: nil)
		#expect(missing.first?.longName == "Node 1a2b3c4d")
		#expect(missing.first?.shortName == "3c4d")
	}

	@Test func snapshotsFromBeforeTheMissingListStillDecode() throws {
		let encoder = JSONEncoder()
		var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(snapshot(nodes: []))) as? [String: Any])
		object.removeValue(forKey: "missingTrackedNodes")
		let data = try JSONSerialization.data(withJSONObject: object)
		let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
		#expect(decoded.missingTrackedNodes == nil)
	}
}
