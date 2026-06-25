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
}
