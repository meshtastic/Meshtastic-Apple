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

	init() {}
}
