//
//  TraceRouteLegsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import CoreLocation
import Foundation
import Testing
@testable import Meshtastic

@Suite("Trace route legs")
struct TraceRouteLegsTests {

	private let origin: Int64 = 0x0A1B_2C3D
	private let relay: Int64 = 0x3333_4444
	private let mqttRelay: Int64 = 0x5555_6666
	private let stranger: Int64 = 0x7777_8888
	private let target: Int64 = 0x1111_2222

	private var nodes: [Int64: TraceRouteLegs.NodeDetails] {
		[
			origin: .init(longName: "Base Camp", shortName: "BASE"),
			relay: .init(longName: "Ridge Relay", shortName: "RDG"),
			mqttRelay: .init(longName: "Gateway", shortName: "GW", viaMqtt: true),
			target: .init(longName: "Summit", shortName: "SUM")
		]
	}

	private func legs(
		forward: [TraceRouteLegs.Hop],
		back: [TraceRouteLegs.Hop] = [],
		originBackSnr: Float = TraceRouteLegs.unknownSnr,
		hasBack: Bool = true,
		positions: [Int64: CLLocationCoordinate2D] = [:]
	) -> TraceRouteLegs {
		let nodes = self.nodes
		return TraceRouteLegs(
			originNum: origin,
			targetNum: target,
			forwardHops: forward,
			backRelays: back,
			originBackSnr: originBackSnr,
			hasBack: hasBack,
			preset: .longFast,
			positions: positions,
			lookup: { nodes[$0] }
		)
	}

	@Test("Forward stops carry names and the SNR of the leg arriving at them")
	func forwardNamesAndSnr() {
		let result = legs(forward: [.init(num: origin, snr: 6), .init(num: relay, snr: 7), .init(num: target, snr: -3.25)])
		#expect(result.forward.map(\.num) == [origin, relay, target])
		#expect(result.forward.map(\.longName) == ["Base Camp", "Ridge Relay", "Summit"])
		#expect(result.forward.map(\.shortName) == ["BASE", "RDG", "SUM"])
		#expect(result.forward.map(\.snr) == [nil, 7, -3.25])
		#expect(result.forward.map(\.id) == [0, 1, 2])
	}

	@Test("The return path runs target, relays, originator")
	func backPath() {
		let result = legs(
			forward: [.init(num: origin, snr: 5), .init(num: relay, snr: 7), .init(num: target, snr: 4)],
			back: [.init(num: relay, snr: 2.5)],
			originBackSnr: 5
		)
		#expect(result.back.map(\.num) == [target, relay, origin])
		#expect(result.back.map(\.snr) == [nil, 2.5, 5])
	}

	@Test("No return path gives no back stops")
	func noBack() {
		let result = legs(forward: [.init(num: origin, snr: 5), .init(num: target, snr: 4)], hasBack: false)
		#expect(result.back.isEmpty)
		#expect(result.forward.count == 2)
	}

	@Test("A direct route with a return path has two stops each way")
	func direct() {
		let result = legs(forward: [.init(num: origin, snr: 6), .init(num: target, snr: 8)], originBackSnr: 6)
		#expect(result.forward.map(\.num) == [origin, target])
		#expect(result.back.map(\.num) == [target, origin])
		#expect(result.back.last?.snr == 6)
	}

	@Test("Unknown repeaters and unknown nodes get fallback names")
	func fallbackNames() {
		let result = legs(forward: [
			.init(num: origin, snr: 0),
			.init(num: TraceRouteLegs.unknownRepeaterNum, snr: 3),
			.init(num: stranger, snr: 4),
			.init(num: target, snr: 5)
		])
		let repeater = result.forward[1]
		#expect(repeater.isUnknownRepeater)
		#expect(repeater.longName == String(localized: "Unknown repeater"))
		#expect(repeater.shortName == "?")
		let unknown = result.forward[2]
		#expect(!unknown.isUnknownRepeater)
		#expect(unknown.longName == "!77778888")
		#expect(unknown.shortName == "8888")
	}

	@Test("The MQTT flag comes from the node")
	func mqttFlag() {
		let result = legs(forward: [.init(num: origin, snr: 0), .init(num: mqttRelay, snr: 3), .init(num: target, snr: 5)])
		#expect(result.forward.map(\.viaMqtt) == [false, true, false])
	}

	@Test("Unknown SNR has no value and no quality")
	func unknownSnr() {
		let result = legs(forward: [.init(num: origin, snr: 0), .init(num: relay, snr: TraceRouteLegs.unknownSnr), .init(num: target, snr: 5)])
		#expect(result.forward[1].snr == nil)
		#expect(result.forward[1].quality == nil)
		#expect(result.forward[0].quality == nil)
	}

	@Test("Quality follows the preset's SNR limit")
	func quality() {
		let limit = ModemPresets.longFast.snrLimit()
		let result = legs(forward: [
			.init(num: origin, snr: 0),
			.init(num: relay, snr: limit + 10),
			.init(num: target, snr: limit - 10)
		])
		#expect(result.forward[1].quality == getLoRaSignalStrength(snr: limit + 10, rssi: 0, preset: .longFast))
		#expect(result.forward[1].quality == .good)
		#expect(result.forward[2].quality == getLoRaSignalStrength(snr: limit - 10, rssi: 0, preset: .longFast))
		#expect(result.forward[2].quality! < .good)
	}

	@Test("Leg distance needs a position at both ends")
	func distances() throws {
		let positions: [Int64: CLLocationCoordinate2D] = [
			origin: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
			relay: CLLocationCoordinate2D(latitude: 47.7, longitude: -122.3)
		]
		let result = legs(
			forward: [.init(num: origin, snr: 0), .init(num: relay, snr: 3), .init(num: target, snr: 5)],
			back: [.init(num: relay, snr: 2)],
			positions: positions
		)
		#expect(result.forward[0].legDistance == nil)
		let first = try #require(result.forward[1].legDistance)
		#expect(abs(first - 11_120) < 50)
		#expect(result.forward[2].legDistance == nil)
		#expect(result.back[1].legDistance == nil)
		#expect(result.back[2].legDistance.map { abs($0 - first) < 1 } == true)
	}

	@Test("Stored routes build from their hops and endpoints")
	func fromEntity() {
		let route = TraceRouteEntity()
		route.fromNum = origin
		route.toNum = target
		route.response = true
		route.sent = true
		route.hopsTowards = 1
		route.hopsBack = 1
		func hop(_ num: Int64, _ snr: Float, _ index: Int32, back: Bool = false) -> TraceRouteHopEntity {
			let hop = TraceRouteHopEntity()
			hop.num = num
			hop.snr = snr
			hop.index = index
			hop.back = back
			return hop
		}
		route.hops = [hop(target, 4, 2), hop(origin, 6, 0), hop(relay, 7, 1), hop(relay, 2.5, 0, back: true)]

		let nodes = self.nodes
		let result = TraceRouteLegs(route: route, preset: .longFast) { nodes[$0] }
		#expect(result.forward.map(\.num) == [origin, relay, target])
		#expect(result.forward.map(\.snr) == [nil, 7, 4])
		#expect(result.back.map(\.num) == [target, relay, origin])
		#expect(result.back.map(\.snr) == [nil, 2.5, 6])
	}
}
