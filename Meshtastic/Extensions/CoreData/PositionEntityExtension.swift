//
//  PersistenceEntityExtenstion.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/28/21.
//

import CoreData
import CoreLocation
import MapKit
import MeshtasticProtobufs
import SwiftUI

extension PositionEntity {

	@MainActor
	static func allPositionsFetchRequest() -> NSFetchRequest<PositionEntity> {
		
		let request: NSFetchRequest<PositionEntity> = PositionEntity.fetchRequest()
		request.sortDescriptors = [NSSortDescriptor(key: "time", ascending: false)]
		let positionPredicate = NSPredicate(format: "nodePosition != nil AND nodePosition.user != nil AND latest == true AND nodePosition.user.shortName != ''")
		request.predicate = positionPredicate

		// Distance Predicate
		if let cl = LocationsHandler.currentLocation {
			
			let d: Double = UserDefaults.meshMapDistance * 1.1
			let r: Double = 6371009 // Earth's mean radius in meters
			
			// Calculate Bounding Box
			let meanLatitidue = cl.latitude * .pi / 180
			let deltaLatitude = d / r * 180 / .pi
			let deltaLongitude = d / (r * cos(meanLatitidue)) * 180 / .pi
			
			let minLatitude: Double = cl.latitude - deltaLatitude
			let maxLatitude: Double = cl.latitude + deltaLatitude
			let minLongitude: Double = cl.longitude - deltaLongitude
			let maxLongitude: Double = cl.longitude + deltaLongitude
			
			// Scale bounding box values by 1e7 and use integer attributes (longitudeI, latitudeI)
			let scale: Double = 1e7
			let minLongitudeI = Int(minLongitude * scale)
			let maxLongitudeI = Int(maxLongitude * scale)
			let minLatitudeI = Int(minLatitude * scale)
			let maxLatitudeI = Int(maxLatitude * scale)
			
			// Use integer comparison in the predicate
			let distancePredicate = NSPredicate(format: "(%ld <= longitudeI) AND (longitudeI <= %ld) AND (%ld <= latitudeI) AND (latitudeI <= %ld)",
											   minLongitudeI, maxLongitudeI, minLatitudeI, maxLatitudeI)
			
			request.predicate = NSCompoundPredicate(type: .and, subpredicates: [positionPredicate, distancePredicate])
		}
		
		return request
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

	var nodeCoordinate: CLLocationCoordinate2D? {
		if latitudeI != 0 && longitudeI != 0 {
			let coord = CLLocationCoordinate2D(latitude: latitude!, longitude: longitude!)
			return coord
		} else {
		   return nil
		}
	}

	var nodeLocation: CLLocation? {
		if latitudeI != 0 && longitudeI != 0 {
			let location = CLLocation(latitude: latitude!, longitude: longitude!)
			return location
		} else {
		   return nil
		}
	}

	var annotaton: MKPointAnnotation {
		let pointAnn = MKPointAnnotation()
		if nodeCoordinate != nil {
			pointAnn.coordinate = nodeCoordinate!
		}
		return pointAnn
	}

	var isPreciseLocation: Bool {
		precisionBits == 32 || precisionBits == 0
	}

	var fuzzedNodeCoordinate: CLLocationCoordinate2D? {
		// With reduced precisionBits, many nodes can overlap on the map, making them unclickable.
		// Use a hash of the position ID to fuzz coordinate slightly so that these nodes can be distinguished at the higest zoom levels. This allows them to be clicked individually.
		if latitudeI != 0 && longitudeI != 0 {
			// Derive two uniform pseudorandom numbers [0,1) from id.hashValue
			let u1 = Double(id.hashValue & 0xFFFF) / 65536.0
			let u2 = Double((id.hashValue >> 16) & 0xFFFF) / 65536.0

			// Angle and radius
			let offsetAngle = 2.0 * .pi * u1
			let offsetRadius = 0.00001 * sqrt(u2) // 1.0e-5 degrees at equator is about 1.11 m or 4 ft

			let dLat = sin(offsetAngle) * offsetRadius
			let dLon = cos(offsetAngle) * offsetRadius

			let coord = CLLocationCoordinate2D(
				latitude: latitude! + dLat,
				longitude: longitude! + dLon
			)
			return coord
		} else {
			return nil
		}
	}
}

extension PositionEntity: MKAnnotation {
	public var coordinate: CLLocationCoordinate2D { nodeCoordinate ?? LocationsHandler.DefaultLocation }
	public var fuzzedCoordinate: CLLocationCoordinate2D { fuzzedNodeCoordinate ?? LocationsHandler.DefaultLocation }
	public var title: String? {  nodePosition?.user?.shortName ?? "Unknown".localized }
	public var subtitle: String? {  time?.formatted() }
}
