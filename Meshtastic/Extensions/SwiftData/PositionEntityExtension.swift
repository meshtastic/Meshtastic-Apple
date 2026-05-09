//
//  PersistenceEntityExtenstion.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/28/21.
//

import SwiftData
import CoreLocation
import MapKit
import MeshtasticProtobufs
import SwiftUI

extension PositionEntity {

	@MainActor
	static func allPositionsFetchDescriptor() -> FetchDescriptor<PositionEntity> {
		var descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> { pos in
				pos.nodePosition != nil && pos.latest == true
			},
			sortBy: [SortDescriptor(\.time, order: .reverse)]
		)
		return descriptor
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

class PositionAnnotation: NSObject, MKAnnotation {
	let positionEntity: PositionEntity
	@objc dynamic var coordinate: CLLocationCoordinate2D
	var fuzzedCoordinate: CLLocationCoordinate2D
	var title: String?
	var subtitle: String?

	init(position: PositionEntity) {
		self.positionEntity = position
		self.coordinate = position.nodeCoordinate ?? LocationsHandler.DefaultLocation
		self.fuzzedCoordinate = position.fuzzedNodeCoordinate ?? LocationsHandler.DefaultLocation
		self.title = position.nodePosition?.user?.shortName ?? "Unknown".localized
		self.subtitle = position.time?.formatted()
		super.init()
	}
}
