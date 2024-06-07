//
//  LocationEntityExtension.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 11/21/23.
//

import CoreData
import CoreLocation
import MapKit
import SwiftUI

extension LocationEntity {
	
	convenience init(
		context: NSManagedObjectContext,
		route: RouteEntity,
		id: Int32,
		location: CLLocation
	) {
		self.init(context: context)
		self.routeLocation = route
		self.id = id
		self.altitude = Int32(location.altitude)
		self.heading = Int32(location.course)
		self.speed = Int32(location.speed)
		self.latitudeI = Int32(location.coordinate.latitude * 1e7)
		self.longitudeI = Int32(location.coordinate.longitude * 1e7)
	}

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

	var locationCoordinate: CLLocationCoordinate2D? {
		if latitudeI != 0 && longitudeI != 0 {
			let coord = CLLocationCoordinate2D(latitude: latitude!, longitude: longitude!)
			return coord
		} else {
		   return nil
		}
	}
}
