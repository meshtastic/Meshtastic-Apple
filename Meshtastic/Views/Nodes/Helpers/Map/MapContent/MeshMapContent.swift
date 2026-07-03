//
//  MeshMapContent.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/17/24.
//
//  Shared value types for the mesh map. The old SwiftUI `MeshMapContent`/`OfflineVectorMapContent`
//  renderers were retired with the SwiftUI map; the MKMapView map (`MeshMapMK` + `ClusterMapView`)
//  renders these snapshots itself. Only the lightweight, render-agnostic types live here now.
//

import CoreLocation

/// Dedup key for reduced-precision accuracy circles (one circle per location + precision).
struct ReducedPrecisionMapCircleKey: Hashable {
	let latitudeI: Int32
	let longitudeI: Int32
	let precisionBits: Int32
}

struct MeshMapSelectedNode: Identifiable, Equatable {
	let id: Int64
}

/// Lightweight snapshot of a position's node data, extracted outside the render pass so MapKit
/// reevaluations do not repeatedly fault SwiftData relationships.
struct MeshMapPositionSnapshot: Identifiable {
	let id: Int64
	let coordinate: CLLocationCoordinate2D
	let latitudeI: Int32
	let longitudeI: Int32
	let precisionBits: Int32
	let nodeNum: Int64
	let longName: String
	let shortName: String?
	let isOnline: Bool
	let viaMqtt: Bool
	let calculatedDelay: Double
}
