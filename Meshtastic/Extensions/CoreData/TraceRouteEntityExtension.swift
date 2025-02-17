//
//  TraceRouteEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 12/7/23.
//

import CoreData
import CoreLocation
import MapKit
import SwiftUI

extension TraceRouteHopEntity {
	var latitude: Double? {
		latitudeI == 0 ? 0 : Double(latitudeI) / 1e7
	}
	
	var longitude: Double? {
		longitudeI == 0 ? 0 : Double(longitudeI) / 1e7
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
