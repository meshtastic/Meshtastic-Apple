//
//  TraceRouteModels.swift
//  Meshtastic
//
//  SwiftData models for trace routes and hops.
//

import Foundation
import SwiftData

@Model
final class TraceRouteEntity {
	var hasPositions: Bool = false
	var hopsBack: Int32 = 0
	var hopsTowards: Int32 = 0
	var id: Int64 = 0
	var response: Bool = false
	var routeBackText: String?
	var routeText: String?
	var sent: Bool = false
	var snr: Float = 0.0
	var time: Date?

	@Relationship(deleteRule: .cascade, inverse: \TraceRouteHopEntity.traceRoute)
	var hops: [TraceRouteHopEntity] = []

	var node: NodeInfoEntity?

	init() {}
}

@Model
final class TraceRouteHopEntity {
	var altitude: Int32 = 0
	var back: Bool = false
	var latitudeI: Int32 = 0
	var longitudeI: Int32 = 0
	var name: String?
	var num: Int64 = 0
	var snr: Float = 0.0
	var time: Date?

	var traceRoute: TraceRouteEntity?

	init() {}
}
