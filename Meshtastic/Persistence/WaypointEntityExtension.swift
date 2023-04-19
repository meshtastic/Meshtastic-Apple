//
//  WaypointEntityExtension.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 1/13/23.
//
import CoreData
import CoreLocation
import MapKit
import SwiftUI

extension WaypointEntity {

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

	var waypointCoordinate: CLLocationCoordinate2D? {
		if latitudeI != 0 && longitudeI != 0 {
			let coord = CLLocationCoordinate2D(latitude: latitude!, longitude: longitude!)
			return coord
		} else {
		   return nil
		}
	}

	var annotaton: MKPointAnnotation {
		let pointAnn = MKPointAnnotation()
		if waypointCoordinate != nil {
			pointAnn.coordinate = waypointCoordinate!
		}
		return pointAnn
	}
}

extension WaypointEntity: MKAnnotation {
	public var coordinate: CLLocationCoordinate2D { waypointCoordinate ?? LocationHelper.DefaultLocation.coordinate }
	public var title: String? { name ?? "Dropped Pin" }
	public var subtitle: String? {
		(longDescription ?? "") +
		String(expire != nil ? "\n⌛ Expires \(String(describing: expire?.formatted()))" : "") +
		String(locked > 0 ? "\n🔒 Locked" : "") }
}
