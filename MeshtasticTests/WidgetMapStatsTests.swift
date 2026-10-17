//
//  WidgetMapStatsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//
import Foundation
import Testing
@testable import Meshtastic

/// The map widget's counts cover the nodes drawn on the image, even when the
/// snapshot's capped node list no longer has some of them.
@Suite("Widget map stats")
struct WidgetMapStatsTests {
	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	private func node(_ num: Int64, online: Bool, favorite: Bool = false, lat: Double? = nil, lon: Double? = nil) -> NodeSnapshot {
		NodeSnapshot(
			num: num, longName: "Node \(num)", shortName: "N\(num)", colorSeed: UInt32(num),
			batteryLevel: nil, snr: nil, rssi: nil, signalRating: nil,
			lastHeard: now, isOnline: online, hopsAway: 0,
			latitude: lat, longitude: lon, isFavorite: favorite
		)
	}

	private func snapshot(_ nodes: [NodeSnapshot], radio: Int64?) -> WidgetSnapshot {
		WidgetSnapshot(
			generatedAt: now, connectionState: .connected, radioNodeNum: radio,
			radioLongName: nil, radioShortName: nil, radioBatteryLevel: nil, localStats: nil,
			nodes: nodes, totalNodeCount: nodes.count, unreadChannelMessages: 0,
			unreadDirectMessages: 0, recentMessages: []
		)
	}

	private func pin(_ num: Int64, lat: Double, heardAgo: TimeInterval, favorite: Bool = false) -> WidgetMapPin {
		WidgetMapPin(num: num, latitude: lat, longitude: 0, lastHeard: now.addingTimeInterval(-heardAgo), isFavorite: favorite)
	}

	@Test func pinsMissingFromTheSnapshotStillCount() {
		let meta = WidgetMapMeta(
			generatedAt: now, nodeNums: [1, 2, 3], radioNum: 1,
			pins: [pin(1, lat: 0, heardAgo: 60), pin(2, lat: 0.01, heardAgo: 60, favorite: true), pin(3, lat: 0.1, heardAgo: 3 * 3600)]
		)
		// Only the radio is still in the snapshot.
		let stats = WidgetMapStats(meta: meta, snapshot: snapshot([node(1, online: true, lat: 0, lon: 0)], radio: 1), now: now)
		#expect(stats.onMap == 3)
		#expect(stats.online == 2)
		#expect(stats.favorites == 1)
		// Node 3 at its drawn position, about 11 km north.
		#expect(abs((stats.farthest ?? 0) - 11_057) < 100)
	}

	@Test func liveSnapshotWinsForOnlineAndFavorite() {
		let meta = WidgetMapMeta(generatedAt: now, nodeNums: [1, 2], radioNum: 1, pins: [pin(1, lat: 0, heardAgo: 60), pin(2, lat: 0.01, heardAgo: 3 * 3600)])
		let stats = WidgetMapStats(
			meta: meta,
			snapshot: snapshot([node(1, online: true), node(2, online: true, favorite: true)], radio: 1),
			now: now
		)
		#expect(stats.online == 2)
		#expect(stats.favorites == 1)
	}

	@Test func distanceUsesTheDrawnPositions() {
		let meta = WidgetMapMeta(generatedAt: now, nodeNums: [1, 2], radioNum: 1, pins: [pin(1, lat: 0, heardAgo: 60), pin(2, lat: 0.01, heardAgo: 60)])
		// The node has moved since the render; the image still shows it at 0.01.
		let stats = WidgetMapStats(
			meta: meta,
			snapshot: snapshot([node(1, online: true, lat: 0, lon: 0), node(2, online: true, lat: 0.5, lon: 0)], radio: 1),
			now: now
		)
		#expect(abs((stats.farthest ?? 0) - 1_106) < 20)
	}

	@Test func oldMetadataWithoutPinsFallsBackToTheSnapshot() throws {
		let json = #"{"version":2,"generatedAt":1800000000000,"nodeNums":[1,2,3],"radioNum":1}"#
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .millisecondsSince1970
		let meta = try decoder.decode(WidgetMapMeta.self, from: Data(json.utf8))
		#expect(meta.pins == nil)
		let stats = WidgetMapStats(
			meta: meta,
			snapshot: snapshot([node(1, online: true, lat: 0, lon: 0), node(2, online: false, lat: 0.01, lon: 0)], radio: 1),
			now: now
		)
		#expect(stats.onMap == 3)
		#expect(stats.online == 1)
		#expect(abs((stats.farthest ?? 0) - 1_106) < 20)
	}

	@Test func noRadioPositionMeansNoDistance() {
		let meta = WidgetMapMeta(generatedAt: now, nodeNums: [2], radioNum: 1, pins: [pin(2, lat: 0, heardAgo: 60)])
		#expect(WidgetMapStats(meta: meta, snapshot: nil, now: now).farthest == nil)
	}
}
