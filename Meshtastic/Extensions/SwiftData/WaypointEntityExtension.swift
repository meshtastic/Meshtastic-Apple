//
//  WaypointEntityExtension.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 1/13/23.
//
@preconcurrency import SwiftData
import CoreLocation
import MapKit
import MeshtasticProtobufs
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
		waypointCoordinate ?? LocationsHandler.DefaultLocation
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

// MARK: - Geofence

extension WaypointEntity {

	/// Copies the geofence fields from a received `Waypoint` protobuf into this entity.
	func applyGeofence(from waypoint: Waypoint) {
		geofenceRadius = Int(waypoint.geofenceRadius)
		notifyOnEnter = waypoint.notifyOnEnter
		notifyOnExit = waypoint.notifyOnExit
		notifyFavoritesOnly = waypoint.notifyFavoritesOnly
		hasBoundingBox = waypoint.hasBoundingBox
		if waypoint.hasBoundingBox {
			boundingBoxLatitudeNorthI = waypoint.boundingBox.latitudeNorthI
			boundingBoxLatitudeSouthI = waypoint.boundingBox.latitudeSouthI
			boundingBoxLongitudeEastI = waypoint.boundingBox.longitudeEastI
			boundingBoxLongitudeWestI = waypoint.boundingBox.longitudeWestI
		} else {
			boundingBoxLatitudeNorthI = 0
			boundingBoxLatitudeSouthI = 0
			boundingBoxLongitudeEastI = 0
			boundingBoxLongitudeWestI = 0
		}
	}

	/// True when the waypoint defines any geofence (circular radius and/or bounding box).
	var hasGeofence: Bool {
		geofenceRadius > 0 || hasBoundingBox
	}

	/// The bounding-box corners as a closed rectangle (SW, SE, NE, NW) suitable for an
	/// `MKPolygon`, or `nil` when no bounding box is set.
	var boundingBoxCoordinates: [CLLocationCoordinate2D]? {
		guard hasBoundingBox else { return nil }
		let north = Double(boundingBoxLatitudeNorthI) / 1e7
		let south = Double(boundingBoxLatitudeSouthI) / 1e7
		let east = Double(boundingBoxLongitudeEastI) / 1e7
		let west = Double(boundingBoxLongitudeWestI) / 1e7
		return [
			CLLocationCoordinate2D(latitude: south, longitude: west),
			CLLocationCoordinate2D(latitude: south, longitude: east),
			CLLocationCoordinate2D(latitude: north, longitude: east),
			CLLocationCoordinate2D(latitude: north, longitude: west)
		]
	}

	/// Whether `location` falls inside this waypoint's geofence, or `nil` when it has none.
	/// A point inside either the circular radius or the bounding box counts as inside.
	func contains(location: CLLocation) -> Bool? {
		guard hasGeofence else { return nil }
		if geofenceRadius > 0, let center = waypointCoordinate {
			let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
			if location.distance(from: centerLocation) <= CLLocationDistance(geofenceRadius) {
				return true
			}
		}
		if hasBoundingBox {
			let lat = location.coordinate.latitude
			let lon = location.coordinate.longitude
			let north = Double(boundingBoxLatitudeNorthI) / 1e7
			let south = Double(boundingBoxLatitudeSouthI) / 1e7
			let east = Double(boundingBoxLongitudeEastI) / 1e7
			let west = Double(boundingBoxLongitudeWestI) / 1e7
			if lat >= south && lat <= north && lon >= west && lon <= east {
				return true
			}
		}
		return false
	}
}
