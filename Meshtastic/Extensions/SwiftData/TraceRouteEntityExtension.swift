//
//  TraceRouteEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 12/7/23.
//

import SwiftData
import CoreLocation
import MapKit
import SwiftUI

extension TraceRouteNodePositionEntity {

	var latitude: Double? {

		let d = Double(latitudeI)
		if d == 0 {
			return 0
		}
		return d / 1e7
	}

	var longitude: Double? {

		let d = Double(longitudeI)
		if d == 0 {
			return 0
		}
		return d / 1e7
	}

	var coordinate: CLLocationCoordinate2D? {
		if latitudeI != 0 && longitudeI != 0 {
			let coord = CLLocationCoordinate2D(latitude: latitude!, longitude: longitude!)
			return coord
		} else {
		   return nil
		}
	}
}

/// Where a trace route stands, for the log rows.
enum TraceRouteState: Equatable {
	/// A response we saw on the mesh for someone else's request.
	case observed
	/// We sent the request and are still inside the wait window.
	case pending
	/// We sent the request and nothing came back in time.
	case noResponse
	/// The radio refused to send the request because of its cooldown.
	case rateLimited
	/// We sent the request and got the route back.
	case complete

	/// How long to wait for a response before calling it no response.
	static let responseWindow: TimeInterval = 120

	/// Short text for the state; nil for `complete` and `observed`, whose rows show the hops.
	var label: String? {
		switch self {
		case .pending: String(localized: "Waiting for response", comment: "Trace route state: request sent, no answer yet")
		case .noResponse: String(localized: "No response", comment: "Trace route state: request sent, nothing came back")
		case .rateLimited: String(localized: "Rate limited")
		case .observed, .complete: nil
		}
	}

	var systemImage: String {
		switch self {
		case .observed, .complete: "point.3.connected.trianglepath.dotted"
		case .pending: "hourglass"
		case .noResponse: "person.slash"
		case .rateLimited: "square.and.arrow.up.trianglebadge.exclamationmark"
		}
	}
}

extension TraceRouteEntity {

	/// When the request went out. Older records have no `sentAt`; before a response arrives their
	/// `time` is the send time.
	private var requestTime: Date? { sentAt ?? time }

	/// Seconds from sending the request to getting the response; nil for observed routes, requests
	/// without a response and older records that didn't keep the send time.
	var roundTrip: TimeInterval? {
		guard sent, response, let sentAt, let time else { return nil }
		let interval = time.timeIntervalSince(sentAt)
		return interval >= 0 ? interval : nil
	}

	/// The state of this trace route at `now`.
	func state(now: Date = .now) -> TraceRouteState {
		if rateLimited { return .rateLimited }
		if response { return sent ? .complete : .observed }
		// Older records marked a rate-limited request by clearing `sent`; observed routes are only
		// ever stored with a response, so an unsent record without one was rate limited.
		guard sent else { return .rateLimited }
		guard let requestTime else { return .noResponse }
		return now.timeIntervalSince(requestTime) < TraceRouteState.responseWindow ? .pending : .noResponse
	}

	/// The icon for a log row: a direct route gets the two-person symbol.
	func rowSystemImage(now: Date = .now) -> String {
		let state = state(now: now)
		if (state == .complete || state == .observed) && hopsTowards == 0 {
			return "person.line.dotted.person"
		}
		return state.systemImage
	}

	/// Snapshotted node positions keyed by node num for quick lookup when rendering a route.
	var nodePositionsByNum: [Int64: TraceRouteNodePositionEntity] {
		Dictionary(nodePositions.map { ($0.num, $0) }, uniquingKeysWith: { first, _ in first })
	}

	/// Ordered coordinates along the path towards the target (originator → hops → target), limited
	/// to the nodes we have a snapshotted position for. The `hops` relationship is unordered, so we
	/// sort by the stored `index`.
	var forwardCoordinates: [CLLocationCoordinate2D] {
		let byNum = nodePositionsByNum
		return hops.filter { !$0.back }
			.sorted { $0.index < $1.index }
			.compactMap { byNum[$0.num]?.coordinate }
	}

	/// Ordered coordinates along the return path (target → return hops → originator). The return
	/// hops don't include the endpoints, so we bracket them with the target and originator nums.
	var backCoordinates: [CLLocationCoordinate2D] {
		let backHops = hops.filter { $0.back }.sorted { $0.index < $1.index }
		guard !backHops.isEmpty else { return [] }
		let byNum = nodePositionsByNum
		let nums = [toNum] + backHops.map { $0.num } + [fromNum]
		return nums.compactMap { byNum[$0]?.coordinate }
	}

	/// Forward path as `(coordinate, altitude)` for the 3D flyover; drops hops without a position
	/// snapshot so the two stay aligned. Altitude is meters above sea level (0 when unknown).
	var forwardLocationPath: [(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance)] {
		let byNum = nodePositionsByNum
		return hops.filter { !$0.back }
			.sorted { $0.index < $1.index }
			.compactMap { hop in
				byNum[hop.num].flatMap { pos in
					pos.coordinate.map { (coordinate: $0, altitude: CLLocationDistance(pos.altitude)) }
				}
			}
	}

	/// Return path as `(coordinate, altitude)` for the flyover, bracketed with target/originator.
	var backLocationPath: [(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance)] {
		let backHops = hops.filter { $0.back }.sorted { $0.index < $1.index }
		guard !backHops.isEmpty else { return [] }
		let byNum = nodePositionsByNum
		let nums = [toNum] + backHops.map { $0.num } + [fromNum]
		return nums.compactMap { num in
			byNum[num].flatMap { pos in
				pos.coordinate.map { (coordinate: $0, altitude: CLLocationDistance(pos.altitude)) }
			}
		}
	}
}
