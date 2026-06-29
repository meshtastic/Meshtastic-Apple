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
	/// Node num that originated the trace route request (our connected node for requests we
	/// initiated, otherwise the requester of a trace route we observed on the mesh).
	var fromNum: Int64 = 0
	/// Node num of the trace route target/responder (matches `node.num` for requests we initiated).
	var toNum: Int64 = 0

	@Relationship(deleteRule: .cascade, inverse: \TraceRouteHopEntity.traceRoute)
	var hops: [TraceRouteHopEntity] = []

	/// Point-in-time snapshot of each involved node's position, captured when the response was
	/// received. One entry per unique node num (see `TraceRouteNodePositionEntity`).
	@Relationship(deleteRule: .cascade, inverse: \TraceRouteNodePositionEntity.traceRoute)
	var nodePositions: [TraceRouteNodePositionEntity] = []

	var node: NodeInfoEntity?

	/// True when this trace route was observed on the mesh rather than initiated by us.
	var observed: Bool { !sent }

	init() {}
}

@Model
final class TraceRouteHopEntity {
	var back: Bool = false
	/// Position of this hop within its direction's ordered path (the `hops` relationship is
	/// unordered, so this preserves the originator → … → target sequence for rendering).
	var index: Int32 = 0
	var name: String?
	var num: Int64 = 0
	var snr: Float = 0.0
	var time: Date?

	var traceRoute: TraceRouteEntity?

	init() {}
}

/// A snapshot of a single node's position at the moment a trace route response was received.
/// Mirrors the meaningful fields of `PositionEntity` so the route can be mapped using the
/// positions nodes had *when the trace route ran*, independent of their later movement.
@Model
final class TraceRouteNodePositionEntity {
	var num: Int64 = 0
	var altitude: Int32 = 0
	var heading: Int32 = 0
	var latitudeI: Int32 = 0
	var longitudeI: Int32 = 0
	var precisionBits: Int32 = 32
	var satsInView: Int32 = 0
	var seqNo: Int32 = 0
	var snr: Float = 0.0
	var speed: Int32 = 0
	var time: Date?

	var traceRoute: TraceRouteEntity?

	init() {}
}
