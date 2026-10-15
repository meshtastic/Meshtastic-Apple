//
//  NodeLinks.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//

import CoreLocation
import Foundation

/// One node hearing another: `observer` heard `heard` at `snr` dB, last at `heardAt`.
/// One-way, so A hearing B says nothing about B hearing A.
struct NodeLinkObservation: Sendable, Equatable {
	let observer: Int64
	let heard: Int64
	let snr: Float
	let heardAt: Date
}

/// The fields of a node that say whether the connected radio hears it directly.
struct NodeLinkNodeRow: Sendable, Equatable {
	let num: Int64
	let hopsAway: Int32
	let viaMqtt: Bool
	let snr: Float
	let lastHeard: Date?
}

/// Two nodes that hear each other, with one SNR per direction. `a` is always the lower node
/// number so each pair has one link.
struct NodeLink: Sendable, Identifiable {
	let a: Int64
	let b: Int64
	let coordinateA: CLLocationCoordinate2D
	let coordinateB: CLLocationCoordinate2D
	/// SNR of `b` as heard by `a`; nil when unknown.
	let snrAtA: Float?
	/// SNR of `a` as heard by `b`; nil when unknown.
	let snrAtB: Float?
	/// Time since the newest of the two measurements.
	let age: TimeInterval

	var id: String { "\(a)-\(b)" }

	/// Only one direction is known.
	var isOneWay: Bool { snrAtA == nil || snrAtB == nil }

	/// The worse of the two directions, which sets the line color.
	var worstSnr: Float? {
		switch (snrAtA, snrAtB) {
		case let (atA?, atB?): min(atA, atB)
		case let (atA?, nil): atA
		case let (nil, atB?): atB
		case (nil, nil): nil
		}
	}
}

/// Builds the links drawn on the map from plain node rows, so it can be tested without a store.
enum NodeLinks {

	/// Links older than this are left out.
	static let maxAge: TimeInterval = 12 * 60 * 60
	/// Links newer than this are drawn at full strength; older ones fade until `maxAge`.
	static let fullStrengthAge: TimeInterval = 2 * 60 * 60
	/// The faintest an old link gets, so it never disappears before it ages out.
	static let minOpacity = 0.25

	/// The connected radio hearing each node it heard directly (no hops, not over MQTT, with an
	/// SNR) within `maxAge`.
	static func directObservations(connectedNum: Int64, nodes: [NodeLinkNodeRow], now: Date) -> [NodeLinkObservation] {
		nodes.compactMap { node in
			guard node.num != connectedNum, node.num != 0,
				  node.hopsAway == 0, !node.viaMqtt, node.snr != 0,
				  let lastHeard = node.lastHeard,
				  now.timeIntervalSince(lastHeard) <= maxAge
			else { return nil }
			return NodeLinkObservation(observer: connectedNum, heard: node.num, snr: node.snr, heardAt: lastHeard)
		}
	}

	/// One link per pair of nodes that both have a position. When a direction is reported more
	/// than once the newest report wins. Observations older than `maxAge` are dropped.
	static func links(from observations: [NodeLinkObservation], positions: [Int64: CLLocationCoordinate2D], now: Date) -> [NodeLink] {
		struct Pair: Hashable { let a: Int64, b: Int64 }
		var atA: [Pair: NodeLinkObservation] = [:]
		var atB: [Pair: NodeLinkObservation] = [:]
		for observation in observations {
			guard observation.observer != observation.heard,
				  now.timeIntervalSince(observation.heardAt) <= maxAge,
				  positions[observation.observer] != nil, positions[observation.heard] != nil
			else { continue }
			let observerIsA = observation.observer < observation.heard
			let pair = observerIsA
				? Pair(a: observation.observer, b: observation.heard)
				: Pair(a: observation.heard, b: observation.observer)
			if observerIsA {
				if atA[pair].map({ $0.heardAt < observation.heardAt }) ?? true { atA[pair] = observation }
			} else {
				if atB[pair].map({ $0.heardAt < observation.heardAt }) ?? true { atB[pair] = observation }
			}
		}
		let pairs = Set(atA.keys).union(atB.keys)
		return pairs.compactMap { pair -> NodeLink? in
			guard let coordinateA = positions[pair.a], let coordinateB = positions[pair.b] else { return nil }
			let fromA = atA[pair], fromB = atB[pair]
			let newest = max(fromA?.heardAt ?? .distantPast, fromB?.heardAt ?? .distantPast)
			return NodeLink(
				a: pair.a,
				b: pair.b,
				coordinateA: coordinateA,
				coordinateB: coordinateB,
				snrAtA: fromA?.snr,
				snrAtB: fromB?.snr,
				age: max(0, now.timeIntervalSince(newest))
			)
		}
		.sorted { ($0.age, $0.a, $0.b) < ($1.age, $1.a, $1.b) }
	}

	/// How strongly to draw a link of this age: 1 up to `fullStrengthAge`, then fading in a
	/// straight line to `minOpacity` at `maxAge`.
	static func opacity(forAge age: TimeInterval) -> Double {
		guard age > fullStrengthAge else { return 1 }
		let progress = min(1, (age - fullStrengthAge) / (maxAge - fullStrengthAge))
		return 1 - progress * (1 - minOpacity)
	}
}
