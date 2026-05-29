//
//  RouteModels.swift
//  Meshtastic
//
//  SwiftData models for routes and locations.
//

import Foundation
import SwiftData

@Model
final class RouteEntity {
	var color: Int64 = 0
	var date: Date?
	var distance: Double = 0
	var elevationGain: Double = 0
	var enabled: Bool = false
	var endDate: Date?
	var id: Int32 = 0
	var name: String?
	var notes: String?

	@Relationship(deleteRule: .cascade, inverse: \LocationEntity.routeLocation)
	var locations: [LocationEntity] = []

	init() {}
}

@Model
final class LocationEntity {
	var altitude: Int32 = 0
	var heading: Int32 = 0
	var id: Int32 = 0
	var latitudeI: Int32 = 0
	var longitudeI: Int32 = 0
	var speed: Int32 = 0

	var routeLocation: RouteEntity?

	init() {}
}

@Model
final class PaxCounterEntity {
	var ble: Int32 = 0
	var time: Date?
	var uptime: Int32 = 0
	var wifi: Int32 = 0

	var paxNode: NodeInfoEntity?

	init() {}
}
