//
//  SpatialMapArea.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation

/// Which circle the spatial map shows. The circle is rebuilt only when it has to be: a node
/// outside it, or the mesh having shrunk well inside it, so the terrain is not rebuilt on every refresh.
enum SpatialMapArea {
	/// Nodes farther than this from the anchor are left out: a mesh with MQTT nodes on another
	/// continent cannot be a one-meter model.
	static let maxRadiusMeters: Double = 125_000
	static let shrinkRatio = 0.5
	static let minimumRebuildInterval: TimeInterval = 30

	struct Selection {
		let coordinates: [CLLocationCoordinate2D]
		let outsideCount: Int
	}

	/// The coordinates that fit around the anchor (the connected radio, else the centroid).
	static func select(_ coordinates: [CLLocationCoordinate2D], anchor: CLLocationCoordinate2D?) -> Selection {
		guard !coordinates.isEmpty else { return Selection(coordinates: [], outsideCount: 0) }
		let center = anchor ?? CLLocationCoordinate2D(
			latitude: coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count),
			longitude: coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
		)
		let frame = SpatialFrame(bounds: GeoBounds(minLon: center.longitude, minLat: center.latitude, maxLon: center.longitude, maxLat: center.latitude))
		let inside = coordinates.filter { c in
			let p = frame.localPosition(c, altitude: 0)
			return Double((p.x * p.x + p.z * p.z).squareRoot()) <= maxRadiusMeters
		}
		return Selection(coordinates: inside, outsideCount: coordinates.count - inside.count)
	}

	/// With no node positions, the circle around the newest offline map the user downloaded, so the
	/// table shows that place. The map the app keeps for the mesh itself is left out.
	static func downloadedMapCircle(_ regions: [OfflineMapRegion]) -> SpatialCircle? {
		guard let newest = regions.filter({ $0.managedBy == nil }).max(by: { $0.createdDate < $1.createdDate }) else { return nil }
		let corners = [
			CLLocationCoordinate2D(latitude: newest.minLatitude, longitude: newest.minLongitude),
			CLLocationCoordinate2D(latitude: newest.maxLatitude, longitude: newest.maxLongitude)
		]
		guard let circle = SpatialCircle.around(corners, padding: 0) else { return nil }
		return SpatialCircle(latitude: circle.latitude, longitude: circle.longitude, radiusMeters: min(circle.radiusMeters, maxRadiusMeters))
	}

	/// The circle to use next: nil to keep the current one.
	static func next(current: SpatialCircle?, candidate: SpatialCircle, nodes: [CLLocationCoordinate2D], lastChange: Date?, now: Date) -> SpatialCircle? {
		guard let current else { return candidate }
		if nodes.contains(where: { !current.contains($0) }) { return candidate }
		if candidate.radiusMeters < current.radiusMeters * shrinkRatio,
		   lastChange.map({ now.timeIntervalSince($0) >= minimumRebuildInterval }) ?? true {
			return candidate
		}
		return nil
	}

	/// The nodes the map shows: when some are too far from the connected radio, those are left
	/// out, except `pinned` ones. With no connected radio every node stays.
	static func fit(_ nodes: [SpatialNodeSnapshot], pinned: Set<Int64> = []) -> (nodes: [SpatialNodeSnapshot], outsideCount: Int) {
		let anchor = nodes.first { $0.isConnectedRadio }?.coordinate
		guard select(nodes.map(\.coordinate), anchor: anchor).outsideCount > 0, let anchor else { return (nodes, 0) }
		let frame = SpatialFrame(bounds: GeoBounds(minLon: anchor.longitude, minLat: anchor.latitude, maxLon: anchor.longitude, maxLat: anchor.latitude))
		let kept = nodes.filter { node in
			if pinned.contains(node.id) { return true }
			let p = frame.localPosition(node.coordinate, altitude: 0)
			return Double((p.x * p.x + p.z * p.z).squareRoot()) <= maxRadiusMeters
		}
		return (kept, nodes.count - kept.count)
	}

	/// The circle around the whole mesh, before any zoom: what terrain downloads cover.
	static func meshCircle(_ nodes: [SpatialNodeSnapshot]) -> SpatialCircle? {
		SpatialCircle.around(fit(nodes).nodes.map(\.coordinate))
	}
}
