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

extension TraceRouteEntity {

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
}
