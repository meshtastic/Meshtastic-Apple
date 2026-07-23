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

/// Single source of truth for the map's coincident-node threshold, shared by both tap paths
/// (cluster tap in `ClusterMapView`, plain pin tap in `MeshMapMK`) and the grouping tests so the
/// value can't drift between them.
enum MapColocation {
	/// Ground distance (meters) within which two nodes are treated as an un-splittable coincident
	/// stack that zooming can't separate — below this, the map offers the "Select a Node" picker
	/// instead of a max-zoom lurch (clustering on) or selecting only the topmost pin (clustering off).
	static let spreadMeters = 5.0
}

/// Dedup key for reduced-precision accuracy circles (one circle per location + precision).
struct ReducedPrecisionMapCircleKey: Hashable {
	let latitudeI: Int32
	let longitudeI: Int32
	let precisionBits: Int32
}

struct MeshMapSelectedNode: Identifiable, Equatable {
	let id: Int64
}

/// A tapped coincident stack of nodes (same location, can't be split by zoom), presented in the
/// map's disambiguation picker. Carries its own nodes so the sheet reads them via `.sheet(item:)`
/// rather than a separately-updated `@State` array (which can present before the array is observed).
struct ColocatedNodeStack: Identifiable {
	let id = UUID()
	let nodes: [MeshMapPositionSnapshot]
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

extension MeshMapPositionSnapshot {
	/// The nodes in `snapshots` that sit within `spreadMeters` (ground distance) of `origin`,
	/// including `origin` itself.
	///
	/// Drives the map's coincident-stack disambiguation on a plain pin tap: when clustering is off,
	/// MapKit forms no `MKClusterAnnotation`, so a tap lands only on the topmost of a set of
	/// overlapping pins. Grouping the tapped node with its coincident neighbors here lets the map
	/// offer the same "Select a Node" picker instead of leaving the occluded nodes untappable.
	/// A free/static function so this policy is unit-testable without a live SwiftUI view.
	static func colocated(
		with origin: MeshMapPositionSnapshot,
		in snapshots: [MeshMapPositionSnapshot],
		withinMeters spreadMeters: Double
	) -> [MeshMapPositionSnapshot] {
		let originLocation = CLLocation(latitude: origin.coordinate.latitude, longitude: origin.coordinate.longitude)
		return snapshots.filter {
			CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
				.distance(from: originLocation) < spreadMeters
		}
	}

	/// The picker-ready ordering of a coincident group: de-duplicated by `nodeNum` (the disambiguation
	/// `List`'s identity is `snapshot.id`, which equals `nodeNum`, so two snapshots sharing a num —
	/// e.g. positions whose node is nil, both 0 — would collide into duplicate List IDs and mis-render)
	/// then sorted by display name. Keeps the first snapshot seen for each num.
	static func dedupedByNodeNumSortedByName(_ snapshots: [MeshMapPositionSnapshot]) -> [MeshMapPositionSnapshot] {
		var seenNodeNums = Set<Int64>()
		return snapshots
			.filter { seenNodeNums.insert($0.nodeNum).inserted }
			.sorted { $0.longName < $1.longName }
	}
}
