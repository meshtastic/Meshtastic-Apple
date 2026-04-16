//
//  WaypointEntityExtension.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 1/13/23.
//
import SwiftData
import CoreLocation
import MapKit
import SwiftUI

extension WaypointEntity {

	@MainActor
	static func allWaypointsFetchDescriptor() -> FetchDescriptor<WaypointEntity> {
		let now = Date()
		return FetchDescriptor<WaypointEntity>(
			predicate: #Predicate<WaypointEntity> { wp in
				wp.expire == nil || wp.expire! >= now
			},
			sortBy: [SortDescriptor(\.name, order: .reverse)]
		)
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

extension WaypointEntity {
	@MainActor
	var mapCoordinate: CLLocationCoordinate2D {
		get {
			waypointCoordinate ?? LocationsHandler.DefaultLocation
		}
	}

	var mapTitle: String? {
		name ?? "Dropped Pin"
	}

	var mapSubtitle: String? {
		(longDescription ?? "") +
		String(expire != nil ? "\n⌛ Expires \(String(describing: expire?.formatted()))" : "") +
		String(locked ? "\n🔒 Locked" : "")
	}
}

class WaypointAnnotation: NSObject, MKAnnotation {
	let waypointEntity: WaypointEntity
	@objc dynamic var coordinate: CLLocationCoordinate2D
	var title: String?
	var subtitle: String?

	@MainActor
	init(waypoint: WaypointEntity) {
		self.waypointEntity = waypoint
		self.coordinate = waypoint.mapCoordinate
		self.title = waypoint.mapTitle
		self.subtitle = waypoint.mapSubtitle
		super.init()
	}
}

struct WaypointCoordinate: Identifiable {
	let id: UUID
	let coordinate: CLLocationCoordinate2D?
	let waypointId: Int64
}
