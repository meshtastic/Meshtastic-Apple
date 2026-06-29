//
//  WaypointEntity.swift
//  Meshtastic
//
//  SwiftData model for waypoints.
//

import Foundation
import SwiftData

@Model
final class WaypointEntity {
	var created: Date?
	var createdBy: Int64 = 0
	var expire: Date?
	var icon: Int64 = 0
	var id: Int64 = 0
	var lastUpdated: Date?
	var lastUpdatedBy: Int64 = 0
	var latitudeI: Int32 = 0
	var locked: Bool = false
	var longDescription: String?
	var longitudeI: Int32 = 0
	var name: String?

	// MARK: Geofence (mirrors the Waypoint protobuf geofence fields)

	/// Circular geofence radius in meters, centred on the waypoint's own location. 0 = no circle.
	var geofenceRadius: Int = 0
	/// Whether a rectangular bounding-box geofence is set (mirrors Waypoint.hasBoundingBox).
	var hasBoundingBox: Bool = false
	/// Bounding-box corners as degrees × 1e7 (sfixed32), matching latitudeI / longitudeI.
	var boundingBoxLatitudeNorthI: Int32 = 0
	var boundingBoxLatitudeSouthI: Int32 = 0
	var boundingBoxLongitudeEastI: Int32 = 0
	var boundingBoxLongitudeWestI: Int32 = 0
	/// Raise a local notification when a tracked node enters / exits this geofence.
	var notifyOnEnter: Bool = false
	var notifyOnExit: Bool = false
	/// When set, only raise enter/exit notifications for nodes marked as favorites on this receiver.
	var notifyFavoritesOnly: Bool = false

	init() {}
}
