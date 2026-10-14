//
//  TraceRouteLegs.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import CoreLocation
import Foundation

/// One node along a trace route, with the leg that arrives at it.
struct TraceRouteStop: Equatable, Identifiable {
	/// Position in its direction, starting at 0 for the node the packet leaves from.
	let id: Int
	let num: Int64
	let longName: String
	let shortName: String
	/// A repeater that didn't add its number to the route (`0xFFFFFFFF`).
	let isUnknownRepeater: Bool
	let viaMqtt: Bool
	/// SNR this node heard the previous one at, in dB. Nil for the first stop and when unknown.
	let snr: Float?
	/// Signal quality of the arriving leg, from `snr` and the radio's preset.
	let quality: LoRaSignalStrength?
	/// Length of the arriving leg in meters, when both ends have a position snapshot.
	let legDistance: CLLocationDistance?
}

/// The forward and return paths of a trace route as lists of stops, built from plain values so it
/// can be tested without SwiftData.
struct TraceRouteLegs: Equatable {

	/// What the legs need to know about a node.
	struct NodeDetails: Equatable {
		var longName: String?
		var shortName: String?
		var viaMqtt: Bool = false
	}

	/// A stored hop: its node number and the SNR it was heard at (`unknownSnr` when unknown).
	struct Hop: Equatable {
		let num: Int64
		let snr: Float
	}

	/// Node number a repeater uses when it doesn't add its own.
	static let unknownRepeaterNum: Int64 = 0xFFFF_FFFF
	/// The firmware's "no SNR" value (INT8_MIN) after the ÷4 scaling.
	static let unknownSnr: Float = -32

	let forward: [TraceRouteStop]
	/// Empty when the response didn't carry a return path.
	let back: [TraceRouteStop]

	/// - Parameters:
	///   - originNum: the node that sent the request.
	///   - targetNum: the node that answered.
	///   - forwardHops: originator → relays → target, in order, each with the SNR it heard the
	///     previous node at (the originator's entry is ignored for SNR).
	///   - backRelays: the relays on the way back, in order (target and originator excluded).
	///   - originBackSnr: SNR the originator heard the last return relay (or target) at.
	///   - hasBack: whether the response carried a return path.
	///   - preset: the connected radio's modem preset, for signal quality.
	///   - positions: position snapshots by node number.
	///   - lookup: node details by number; nil when the node isn't known.
	init(
		originNum: Int64,
		targetNum: Int64,
		forwardHops: [Hop],
		backRelays: [Hop],
		originBackSnr: Float,
		hasBack: Bool,
		preset: ModemPresets,
		positions: [Int64: CLLocationCoordinate2D] = [:],
		lookup: (Int64) -> NodeDetails?
	) {
		let forwardPath = forwardHops.isEmpty
			? [Hop(num: originNum, snr: Self.unknownSnr), Hop(num: targetNum, snr: Self.unknownSnr)]
			: forwardHops
		forward = Self.stops(for: forwardPath, preset: preset, positions: positions, lookup: lookup)
		if hasBack {
			let backPath = [Hop(num: targetNum, snr: Self.unknownSnr)] + backRelays + [Hop(num: originNum, snr: originBackSnr)]
			back = Self.stops(for: backPath, preset: preset, positions: positions, lookup: lookup)
		} else {
			back = []
		}
	}

	private static func stops(
		for path: [Hop],
		preset: ModemPresets,
		positions: [Int64: CLLocationCoordinate2D],
		lookup: (Int64) -> NodeDetails?
	) -> [TraceRouteStop] {
		path.enumerated().map { index, hop in
			let isUnknownRepeater = hop.num == unknownRepeaterNum
			let details = isUnknownRepeater ? nil : lookup(hop.num)
			let snr: Float? = (index == 0 || hop.snr <= unknownSnr) ? nil : hop.snr
			var distance: CLLocationDistance?
			if index > 0, let from = positions[path[index - 1].num], let to = positions[hop.num] {
				distance = CLLocation(latitude: from.latitude, longitude: from.longitude)
					.distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
			}
			return TraceRouteStop(
				id: index,
				num: hop.num,
				longName: longName(num: hop.num, isUnknownRepeater: isUnknownRepeater, details: details),
				shortName: shortName(num: hop.num, isUnknownRepeater: isUnknownRepeater, details: details),
				isUnknownRepeater: isUnknownRepeater,
				viaMqtt: details?.viaMqtt ?? false,
				snr: snr,
				quality: snr.map { getLoRaSignalStrength(snr: $0, rssi: 0, preset: preset) },
				legDistance: distance
			)
		}
	}

	private static func longName(num: Int64, isUnknownRepeater: Bool, details: NodeDetails?) -> String {
		if isUnknownRepeater {
			return String(localized: "Unknown repeater", comment: "Trace route hop that didn't add its node number")
		}
		if let name = details?.longName, !name.isEmpty { return name }
		return num.toHex()
	}

	private static func shortName(num: Int64, isUnknownRepeater: Bool, details: NodeDetails?) -> String {
		if isUnknownRepeater { return "?" }
		if let name = details?.shortName, !name.isEmpty { return name }
		return String(num.toHex().suffix(4))
	}
}

extension TraceRouteLegs {

	/// Builds the legs for a stored trace route.
	init(route: TraceRouteEntity, preset: ModemPresets, lookup: (Int64) -> NodeDetails?) {
		let forwardHops = route.hops.filter { !$0.back }.sorted { $0.index < $1.index }
		let backHops = route.hops.filter { $0.back }.sorted { $0.index < $1.index }
		// The originator's forward entry holds the SNR it heard the return path at.
		let originBackSnr = forwardHops.first?.snr ?? Self.unknownSnr
		// The forward hops carry both endpoints, which covers records stored without from/to nums.
		let hasEndpoints = forwardHops.count >= 2
		self.init(
			originNum: hasEndpoints ? forwardHops[0].num : route.fromNum,
			targetNum: hasEndpoints ? forwardHops[forwardHops.count - 1].num : route.toNum,
			forwardHops: forwardHops.map { Hop(num: $0.num, snr: $0.snr) },
			backRelays: backHops.map { Hop(num: $0.num, snr: $0.snr) },
			originBackSnr: originBackSnr,
			hasBack: route.hopsBack >= 0 && route.response,
			preset: preset,
			positions: route.nodePositionsByNum.compactMapValues { $0.coordinate },
			lookup: lookup
		)
	}
}

extension TraceRouteLegs.NodeDetails {
	init(node: NodeInfoEntity) {
		self.init(longName: node.user?.longName, shortName: node.user?.shortName, viaMqtt: node.viaMqtt)
	}
}
