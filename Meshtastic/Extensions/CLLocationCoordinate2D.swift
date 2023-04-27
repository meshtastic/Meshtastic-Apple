//
//  CLLocationCoordinate2D.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation
import MapKit

extension CLLocationCoordinate2D {
	/// Returns distance from coordianate in meters.
	/// - Parameter from: coordinate which will be used as end point.
	/// - Returns: distance in meters.
	func distance(from: CLLocationCoordinate2D) -> CLLocationDistance {
		let from = CLLocation(latitude: from.latitude, longitude: from.longitude)
		let to = CLLocation(latitude: self.latitude, longitude: self.longitude)
		return from.distance(from: to)
	}
}
