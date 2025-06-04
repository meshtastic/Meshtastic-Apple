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

	static func allWaypointssFetchRequest() -> NSFetchRequest<WaypointEntity> {
		let request: NSFetchRequest<WaypointEntity> = WaypointEntity.fetchRequest()
		request.fetchLimit = 50
		request.returnsDistinctResults = true
		request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: false)]
		request.predicate = NSPredicate(format: "expire == nil || expire >= %@", Date() as NSDate)
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
	@MainActor
	public var coordinate: CLLocationCoordinate2D {
		get {
			waypointCoordinate ?? LocationsHandler.currentLocation
		}
		set {
			latitudeI = Int32(newValue.latitude * 1e7)
			longitudeI = Int32(newValue.longitude * 1e7)
		}
	}

	public var title: String? {
		name ?? "Dropped Pin"
	}

	public var subtitle: String? {
		(longDescription ?? "") +
		String(expire != nil ? "\n⌛ Expires \(String(describing: expire?.formatted()))" : "") +
		String(locked > 0 ? "\n🔒 Locked" : "")
	}
}

struct WaypointCoordinate: Identifiable {
	let id: UUID
	let coordinate: CLLocationCoordinate2D?
	let waypointId: Int64
}
