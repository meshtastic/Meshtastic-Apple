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

	// MARK: Send-to destination

	/// Channel index this waypoint was broadcast on (0 = primary). Only meaningful when
	/// `destinationNodeNum` is 0 — a DM'd waypoint's channel is irrelevant to where it's routed.
	/// `private(set)`: write only through `destination` below, which keeps this and `destinationNodeNum`
	/// mutually exclusive — setting them individually could otherwise leave both non-zero at once, an
	/// invalid state `destination`'s getter would then have to silently pick a winner for.
	private(set) var destinationChannel: Int32 = 0
	/// Node this waypoint was privately sent to (or received from) as a DM. 0 means it's a channel
	/// broadcast; see `destinationChannel`.
	private(set) var destinationNodeNum: Int64 = 0

	/// The recipient this waypoint is associated with, for re-opening it in the editor or resending it
	/// (e.g. "delete for everyone") to the same destination it was originally exchanged on.
	var destination: WaypointDestination {
		get { destinationNodeNum > 0 ? .user(destinationNodeNum) : .channel(destinationChannel) }
		set {
			switch newValue {
			case let .channel(index):
				destinationChannel = index
				destinationNodeNum = 0
			case let .user(num):
				destinationChannel = 0
				destinationNodeNum = num
			}
		}
	}

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
