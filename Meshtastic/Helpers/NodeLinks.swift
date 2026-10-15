//
//  NodeLinks.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//

import CoreLocation
import Foundation
import OSLog
import SwiftData

/// One node hearing another: `observer` heard `heard` at `snr` dB, last at `heardAt`.
/// One-way, so A hearing B says nothing about B hearing A.
struct NodeLinkObservation: Sendable, Equatable {

	/// Where the observation came from, which sets how long it stays on the map.
	enum Source: Sendable, Equatable {
		/// The connected radio heard the node directly, from the node list.
		case heardByRadio
		/// A node listed it in a Neighbor Info report. Reports come every 4 to 6 hours, so they
		/// stay at full strength longer and are kept for a day.
		case neighborReport

		/// Older than this and the observation is left out.
		var maxAge: TimeInterval {
			switch self {
			case .heardByRadio: 12 * 60 * 60
			case .neighborReport: 24 * 60 * 60
			}
		}

		/// Newer than this is drawn at full strength; older fades until `maxAge`.
		var fullStrengthAge: TimeInterval {
			switch self {
			case .heardByRadio: 2 * 60 * 60
			// The default report interval is 6 hours, plus some slack so a node on that
			// schedule doesn't start fading just before each new report.
			case .neighborReport: 7 * 60 * 60
			}
		}
	}

	let observer: Int64
	let heard: Int64
	let snr: Float
	let heardAt: Date
	var source: Source = .heardByRadio
}

/// One saved Neighbor Info entry: `reporter` heard `neighbor` at `snr` dB.
struct NodeLinkReportRow: Sendable, Equatable {
	let reporter: Int64
	let neighbor: Int64
	let snr: Float
	let receivedAt: Date
	let viaMqtt: Bool
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
	/// How strongly to draw each direction's pill, from its own age; 0 when unknown.
	let opacityAtA: Double
	let opacityAtB: Double
	/// Time since the newest of the two measurements.
	let age: TimeInterval

	/// How strongly to draw the line: the fresher of the two directions.
	var opacity: Double { max(opacityAtA, opacityAtB) }

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

	/// How long the connected radio's own direct links stay on the map.
	static let maxAge = NodeLinkObservation.Source.heardByRadio.maxAge
	/// How long links from Neighbor Info reports stay on the map.
	static let maxReportAge = NodeLinkObservation.Source.neighborReport.maxAge
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

	/// Each saved Neighbor Info entry as the reporter hearing its neighbor, within `maxReportAge`.
	/// Reports that reached us over MQTT are left out: they can come from meshes far from the
	/// user's own, and the radio's own links leave MQTT out too.
	static func reportedObservations(_ rows: [NodeLinkReportRow], now: Date) -> [NodeLinkObservation] {
		rows.compactMap { row in
			guard !row.viaMqtt, row.reporter != 0, row.neighbor != 0, row.reporter != row.neighbor,
				  now.timeIntervalSince(row.receivedAt) <= maxReportAge
			else { return nil }
			return NodeLinkObservation(observer: row.reporter, heard: row.neighbor, snr: row.snr, heardAt: row.receivedAt, source: .neighborReport)
		}
	}

	/// One link per pair of nodes that both have a position. When a direction is known from more
	/// than one observation the newest wins, so the radio hearing a node and a report of the same
	/// direction don't make two links. Observations older than their source's `maxAge` are dropped.
	static func links(from observations: [NodeLinkObservation], positions: [Int64: CLLocationCoordinate2D], now: Date) -> [NodeLink] {
		struct Pair: Hashable { let a: Int64, b: Int64 }
		var atA: [Pair: NodeLinkObservation] = [:]
		var atB: [Pair: NodeLinkObservation] = [:]
		for observation in observations {
			guard observation.observer != observation.heard,
				  now.timeIntervalSince(observation.heardAt) <= observation.source.maxAge,
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
				opacityAtA: fromA.map { opacity(for: $0, now: now) } ?? 0,
				opacityAtB: fromB.map { opacity(for: $0, now: now) } ?? 0,
				age: max(0, now.timeIntervalSince(newest))
			)
		}
		.sorted { ($0.age, $0.a, $0.b) < ($1.age, $1.a, $1.b) }
	}

	/// How strongly to draw an observation: 1 up to its source's `fullStrengthAge`, then fading
	/// in a straight line to `minOpacity` at its `maxAge`.
	static func opacity(for observation: NodeLinkObservation, now: Date) -> Double {
		opacity(forAge: max(0, now.timeIntervalSince(observation.heardAt)), source: observation.source)
	}

	static func opacity(forAge age: TimeInterval, source: NodeLinkObservation.Source = .heardByRadio) -> Double {
		guard age > source.fullStrengthAge else { return 1 }
		let progress = min(1, (age - source.fullStrengthAge) / (source.maxAge - source.fullStrengthAge))
		return 1 - progress * (1 - minOpacity)
	}

	/// The saved Neighbor Info entries young enough to draw, left out when they came over MQTT.
	/// There are few rows: at most ten per reporting node.
	@MainActor
	static func reportRows(context: ModelContext, now: Date) -> [NodeLinkReportRow] {
		let cutoff = now.addingTimeInterval(-maxReportAge)
		let rows: [NeighborLinkEntity]
		do {
			rows = try context.fetch(FetchDescriptor<NeighborLinkEntity>(
				predicate: #Predicate<NeighborLinkEntity> { $0.viaMqtt == false && $0.receivedAt >= cutoff }
			))
		} catch {
			Logger.data.error("💥 [NodeLinks] Neighbor link fetch failed: \(error.localizedDescription, privacy: .public)")
			rows = []
		}
		return rows.map {
			NodeLinkReportRow(reporter: $0.reporterNum, neighbor: $0.neighborNum, snr: $0.snr, receivedAt: $0.receivedAt, viaMqtt: $0.viaMqtt)
		}
	}
}
