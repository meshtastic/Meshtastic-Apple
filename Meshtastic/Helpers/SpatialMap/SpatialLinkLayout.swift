//
//  SpatialLinkLayout.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//
import CoreLocation
import Foundation

/// One link as the spatial map draws it: the two nodes, the SNR each heard the other at, and how
/// strongly to draw each end. Opacities are rounded to quarter steps so the set only changes, and
/// the lines are only rebuilt, when the drawing would look different.
struct SpatialLinkSnapshot: Equatable, Identifiable, Sendable {
	let a: Int64
	let b: Int64
	/// SNR of `b` as heard by `a`; nil when unknown.
	let snrAtA: Float?
	/// SNR of `a` as heard by `b`; nil when unknown.
	let snrAtB: Float?
	let opacityAtA: Double
	let opacityAtB: Double

	var id: String { "\(a)-\(b)" }
	var isOneWay: Bool { snrAtA == nil || snrAtB == nil }
	/// The fresher of the two directions sets how strongly the line is drawn.
	var opacity: Double { max(opacityAtA, opacityAtB) }

	/// The worse of the two directions, which sets the line color.
	var worstSnr: Float? {
		switch (snrAtA, snrAtB) {
		case let (atA?, atB?): min(atA, atB)
		case let (atA?, nil): atA
		case let (nil, atB?): atB
		case (nil, nil): nil
		}
	}

	func touches(_ num: Int64) -> Bool { a == num || b == num }
}

/// An SNR pill near the node that measured it.
struct SpatialLinkPill: Equatable, Identifiable, Sendable {
	let linkID: String
	/// The node that heard the other one, which the pill sits next to.
	let atNum: Int64
	let otherNum: Int64
	let snr: Float
	let opacity: Double

	var id: String { "\(linkID)-\(atNum)" }
}

/// Turns the nodes on the spatial map and saved Neighbor Info into the links it draws, using the
/// same builder as the 2D map, and picks which links get SNR pills.
enum SpatialLinkLayout {

	/// Each pill is a SwiftUI attachment, so only this many are made at once.
	static let pillLimit = 12
	/// How far along the line, from the node that measured it, a pill sits.
	static let pillFraction: Float = 0.3

	/// Links between nodes shown on the map. The connected radio's own links come from the nodes
	/// it heard directly; links between other nodes come from `reports`. Newest first.
	static func links(nodes: [SpatialNodeSnapshot], connectedNum: Int64?, reports: [NodeLinkReportRow], now: Date) -> [SpatialLinkSnapshot] {
		var positions: [Int64: CLLocationCoordinate2D] = [:]
		for node in nodes where positions[node.id] == nil {
			positions[node.id] = node.coordinate
		}
		var observations = NodeLinks.reportedObservations(reports, now: now)
		if let connectedNum, connectedNum != 0 {
			let rows = nodes.map {
				NodeLinkNodeRow(num: $0.id, hopsAway: Int32(clamping: $0.hopsAway), viaMqtt: $0.viaMqtt, snr: $0.snr, lastHeard: $0.lastHeard)
			}
			observations += NodeLinks.directObservations(connectedNum: connectedNum, nodes: rows, now: now)
		}
		return NodeLinks.links(from: observations, positions: positions, now: now).map { link in
			SpatialLinkSnapshot(
				a: link.a, b: link.b, snrAtA: link.snrAtA, snrAtB: link.snrAtB,
				opacityAtA: link.snrAtA == nil ? 0 : quarterStep(link.opacityAtA),
				opacityAtB: link.snrAtB == nil ? 0 : quarterStep(link.opacityAtB)
			)
		}
	}

	/// The pills to show, at most `limit`. With a node selected, only its links get pills, so
	/// the pills answer "who does this node hear". Otherwise the newest links get them, the
	/// connected radio's first. `links` should be newest first.
	static func pills(for links: [SpatialLinkSnapshot], selected: Int64?, connected: Int64?, limit: Int = pillLimit) -> [SpatialLinkPill] {
		let chosen: [SpatialLinkSnapshot]
		if let selected {
			chosen = links.filter { $0.touches(selected) }
		} else if let connected {
			chosen = links.filter { $0.touches(connected) } + links.filter { !$0.touches(connected) }
		} else {
			chosen = links
		}
		var pills: [SpatialLinkPill] = []
		for link in chosen {
			if let snr = link.snrAtA {
				pills.append(SpatialLinkPill(linkID: link.id, atNum: link.a, otherNum: link.b, snr: snr, opacity: link.opacityAtA))
			}
			if let snr = link.snrAtB {
				pills.append(SpatialLinkPill(linkID: link.id, atNum: link.b, otherNum: link.a, snr: snr, opacity: link.opacityAtB))
			}
			if pills.count >= limit { break }
		}
		return Array(pills.prefix(limit))
	}

	/// Rounds to the nearest quarter, keeping at least the faintest step.
	static func quarterStep(_ opacity: Double) -> Double {
		max(0.25, min(1, (opacity * 4).rounded() / 4))
	}
}
