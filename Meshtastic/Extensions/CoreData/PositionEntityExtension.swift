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
}

extension PositionEntity: MKAnnotation {
	public var coordinate: CLLocationCoordinate2D { nodeCoordinate ?? LocationsHandler.DefaultLocation }
	public var title: String? {  nodePosition?.user?.shortName ?? "Unknown".localized }
	public var subtitle: String? {  time?.formatted() }
}
