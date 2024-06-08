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
	convenience init(
		context: NSManagedObjectContext,
		nodeInfo: NodeInfo
	) {
		self.init(context: context)
		self.latest = true
		self.seqNo = Int32(nodeInfo.position.seqNumber)
		self.latitudeI = nodeInfo.position.latitudeI
		self.longitudeI = nodeInfo.position.longitudeI
		self.altitude = nodeInfo.position.altitude
		self.satsInView = Int32(nodeInfo.position.satsInView)
		self.speed = Int32(nodeInfo.position.groundSpeed)
		self.heading = Int32(nodeInfo.position.groundTrack)
		self.time = Date(timeIntervalSince1970: TimeInterval(Int64(nodeInfo.position.time)))
	}
	
	static func allPositionsFetchRequest() -> NSFetchRequest<PositionEntity> {
		let request: NSFetchRequest<PositionEntity> = PositionEntity.fetchRequest()
		request.fetchLimit = 1000
		request.returnsObjectsAsFaults = false
		request.includesSubentities = true
		request.returnsDistinctResults = true
		request.sortDescriptors = [NSSortDescriptor(key: "time", ascending: false)]
		let positionPredicate = NSPredicate(format: "nodePosition != nil && (nodePosition.user.shortName != nil || nodePosition.user.shortName != '') && latest == true")

		let pointOfInterest = LocationHelper.currentLocation

		if pointOfInterest.latitude != LocationHelper.DefaultLocation.latitude && pointOfInterest.longitude != LocationHelper.DefaultLocation.longitude {
			let d: Double = UserDefaults.meshMapDistance * 1.1
			let r: Double = 6371009
			let meanLatitidue = pointOfInterest.latitude * .pi / 180
			let deltaLatitude = d / r * 180 / .pi
			let deltaLongitude = d / (r * cos(meanLatitidue)) * 180 / .pi
			let minLatitude: Double = pointOfInterest.latitude - deltaLatitude
			let maxLatitude: Double = pointOfInterest.latitude + deltaLatitude
			let minLongitude: Double = pointOfInterest.longitude - deltaLongitude
			let maxLongitude: Double = pointOfInterest.longitude + deltaLongitude
			let distancePredicate = NSPredicate(format: "(%lf <= (longitudeI / 1e7)) AND ((longitudeI / 1e7) <= %lf) AND (%lf <= (latitudeI / 1e7)) AND ((latitudeI / 1e7) <= %lf)", minLongitude, maxLongitude, minLatitude, maxLatitude)
			request.predicate = NSCompoundPredicate(type: .and, subpredicates: [positionPredicate, distancePredicate])
		} else {
			request.predicate = positionPredicate
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
	public var coordinate: CLLocationCoordinate2D { nodeCoordinate ?? LocationHelper.DefaultLocation }
	public var title: String? {  nodePosition?.user?.shortName ?? "unknown".localized }
	public var subtitle: String? {  time?.formatted() }
}
