//
//  SpatialNodeSnapshot.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation
import SwiftData

/// What the spatial map needs to know about one node, copied out of SwiftData so the scene never
/// holds a model object.
struct SpatialNodeSnapshot: Identifiable, Equatable, Sendable {
	let id: Int64
	let coordinate: CLLocationCoordinate2D
	/// Reported altitude in meters, nil when the position has none.
	let altitude: Double?
	let isPrecise: Bool
	let longName: String
	let shortName: String
	let isOnline: Bool
	let lastHeard: Date?
	let isFavorite: Bool
	let viaMqtt: Bool
	let hopsAway: Int
	let snr: Float
	let isConnectedRadio: Bool
	/// The node's role, nil when unknown. Routers, repeaters and client bases stand as towers.
	let role: DeviceRoles?

	/// How tall the node's tower stands, nil for a node drawn as a pin.
	var towerHeight: Float? { SpatialTower.height(for: role) }

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.id == rhs.id
			&& lhs.coordinate.latitude == rhs.coordinate.latitude
			&& lhs.coordinate.longitude == rhs.coordinate.longitude
			&& lhs.altitude == rhs.altitude
			&& lhs.longName == rhs.longName && lhs.shortName == rhs.shortName
			&& lhs.isOnline == rhs.isOnline && lhs.lastHeard == rhs.lastHeard
			&& lhs.isFavorite == rhs.isFavorite && lhs.viaMqtt == rhs.viaMqtt
			&& lhs.hopsAway == rhs.hopsAway && lhs.snr == rhs.snr
			&& lhs.isConnectedRadio == rhs.isConnectedRadio
			&& lhs.role == rhs.role
	}
}

/// Builds the node list for the spatial map the same way the 2D map builds its pins: latest
/// positions only, the map filters applied, and a cap that keeps the connected radio and favorites
/// first when the mesh is large.
enum SpatialMapNodeSource {
	static let limit = 500

	@MainActor
	static func snapshots(
		context: ModelContext,
		filters: NodeFilterParameters,
		preciseOnly: Bool,
		connectedNodeNum: Int64?
	) -> [SpatialNodeSnapshot] {
		let searchText = filters.searchText.lowercased()
		let onlineThreshold = filters.isOnline ? Date().addingTimeInterval(-7_200) : nil
		let distanceBounds = filters.currentDistanceBounds
		let filtering = filters.isFiltering || !searchText.isEmpty
		let all = try? snapshots(context: context, preciseOnly: preciseOnly, connectedNodeNum: connectedNodeNum) { node, position in
			!filtering || filters.matches(node, latestPosition: position, normalizedSearchText: searchText,
										  onlineThreshold: onlineThreshold, distanceBounds: distanceBounds)
		}
		return all ?? []
	}

	/// The same list with no map filters, or with `include` deciding which nodes stay. Works on
	/// any context, so a background reader can use it. Throws when the positions can't be read.
	static func snapshots(
		context: ModelContext,
		preciseOnly: Bool,
		connectedNodeNum: Int64?,
		include: (NodeInfoEntity, PositionEntity) -> Bool = { _, _ in true }
	) throws -> [SpatialNodeSnapshot] {
		let positions = try context.fetch(PositionEntity.allPositionsFetchDescriptor())
		var pinned: [SpatialNodeSnapshot] = []
		var online: [SpatialNodeSnapshot] = []
		var rest: [SpatialNodeSnapshot] = []
		for position in positions {
			guard let node = position.nodePosition, !node.ignored else { continue }
			guard position.isPreciseLocation || (!preciseOnly && position.isReducedPrecision) else { continue }
			guard include(node, position) else { continue }
			let coordinate: CLLocationCoordinate2D? = position.isPreciseLocation ? position.nodeCoordinate : position.fuzzedNodeCoordinate
			guard let coordinate else { continue }
			let snapshot = SpatialNodeSnapshot(
				id: node.num,
				coordinate: coordinate,
				altitude: position.altitude == 0 ? nil : Double(position.altitude),
				isPrecise: position.isPreciseLocation,
				longName: node.user?.longName ?? "?",
				shortName: node.user?.shortName ?? "?",
				isOnline: node.isOnline,
				lastHeard: node.lastHeard,
				isFavorite: node.favorite,
				viaMqtt: node.viaMqtt,
				hopsAway: Int(node.hopsAway),
				snr: node.snr,
				isConnectedRadio: node.num == connectedNodeNum,
				role: node.user.flatMap { DeviceRoles(rawValue: Int($0.role)) }
			)
			if snapshot.isConnectedRadio || snapshot.isFavorite {
				pinned.append(snapshot)
			} else if snapshot.isOnline {
				online.append(snapshot)
			} else {
				rest.append(snapshot)
			}
		}
		var result = pinned
		for group in [online, rest] where result.count < limit {
			result.append(contentsOf: group.prefix(limit - result.count))
		}
		return result
	}
}
