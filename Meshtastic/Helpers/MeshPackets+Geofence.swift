//
//  MeshPackets+Geofence.swift
//  Meshtastic
//
//  Evaluates received node positions against waypoint geofences and raises local
//  enter/exit notifications. Backed entirely by the Waypoint protobuf geofence
//  fields (geofenceRadius / boundingBox / notifyOnEnter / notifyOnExit /
//  notifyFavoritesOnly) — there is no separate geofence model.
//

@preconcurrency import SwiftData
import CoreLocation
import Foundation
import OSLog

/// Thread-safe, in-memory record of whether each (waypoint, node) pair was last seen
/// inside its geofence. Not persisted: the first observation of a pair only establishes
/// a baseline and never notifies, so an app relaunch cannot produce spurious alerts.
final class GeofenceCrossingStore: @unchecked Sendable {
	static let shared = GeofenceCrossingStore()
	private let queue = DispatchQueue(label: "com.meshtastic.geofence.crossing")
	private var states: [String: Bool] = [:]

	/// Records the new inside/outside state and returns the previous one
	/// (`nil` the first time a pair is seen).
	func update(key: String, isInside: Bool) -> Bool? {
		queue.sync {
			let previous = states[key]
			states[key] = isInside
			return previous
		}
	}
}

extension MeshPackets {

	/// Evaluate a newly received node position against every notifying waypoint geofence.
	/// Call from `upsertPositionPacket` once a valid position has been stored.
	func evaluateGeofences(nodeNum: Int64, latitudeI: Int32, longitudeI: Int32, nodeName: String) {
		guard latitudeI != 0 || longitudeI != 0 else { return }
		let location = CLLocation(latitude: Double(latitudeI) / 1e7, longitude: Double(longitudeI) / 1e7)

		// Only consider waypoints that actually want enter/exit notifications.
		let descriptor = FetchDescriptor<WaypointEntity>(
			predicate: #Predicate<WaypointEntity> { $0.notifyOnEnter || $0.notifyOnExit }
		)
		guard let waypoints = try? modelContext.fetch(descriptor) else { return }

		// Resolved lazily once per call: whether this node is a favorite on THIS receiver, used by
		// waypoints set to notify for favorites only.
		var nodeIsFavorite: Bool?

		for waypoint in waypoints {
			guard let isInside = waypoint.contains(location: location) else { continue }
			// Key on the geofence geometry as well as the waypoint/node pair: if the radius or
			// bounding box changes, the new key re-establishes a baseline rather than reusing the
			// stale inside/outside state, which would otherwise fire a spurious enter/exit alert.
			let key = "\(waypoint.id)-\(nodeNum)-\(waypoint.geofenceRadius)-\(waypoint.boundingBoxLatitudeNorthI)-\(waypoint.boundingBoxLatitudeSouthI)-\(waypoint.boundingBoxLongitudeEastI)-\(waypoint.boundingBoxLongitudeWestI)"
			let previous = GeofenceCrossingStore.shared.update(key: key, isInside: isInside)
			// First observation establishes a baseline; only a genuine change notifies.
			guard let wasInside = previous, wasInside != isInside else { continue }

			// Favorites-only: only alert for nodes the receiver has marked as favorite. Applies to
			// both enter and exit; favorite status is resolved locally on this device.
			if waypoint.notifyFavoritesOnly {
				if nodeIsFavorite == nil { nodeIsFavorite = isFavoriteNode(nodeNum) }
				if nodeIsFavorite == false { continue }
			}

			let name = waypoint.name ?? "Geofence"
			if isInside && waypoint.notifyOnEnter {
				scheduleGeofenceNotification(waypointId: waypoint.id, waypointName: name, nodeNum: nodeNum, nodeName: nodeName, entered: true)
			} else if !isInside && waypoint.notifyOnExit {
				scheduleGeofenceNotification(waypointId: waypoint.id, waypointName: name, nodeNum: nodeNum, nodeName: nodeName, entered: false)
			}
		}
	}

	/// Whether `nodeNum` is marked as a favorite on this device (resolved locally per receiver).
	private func isFavoriteNode(_ nodeNum: Int64) -> Bool {
		var descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate<NodeInfoEntity> { $0.num == nodeNum })
		descriptor.fetchLimit = 1
		return ((try? modelContext.fetch(descriptor))?.first?.favorite) ?? false
	}

	private func scheduleGeofenceNotification(waypointId: Int64, waypointName: String, nodeNum: Int64, nodeName: String, entered: Bool) {
		let title = entered
			? String.localizedStringWithFormat("Entered %@".localized, waypointName)
			: String.localizedStringWithFormat("Left %@".localized, waypointName)
		let body = entered
			? String.localizedStringWithFormat("%@ entered %@".localized, nodeName, waypointName)
			: String.localizedStringWithFormat("%@ left %@".localized, nodeName, waypointName)
		Task { @MainActor in
			let manager = LocalNotificationManager()
			manager.notifications = [
				Notification(
					id: "geofence.\(waypointId).\(nodeNum).\(entered ? "enter" : "exit")",
					title: title,
					subtitle: "",
					content: body,
					target: "map",
					path: "meshtastic:///map?waypointid=\(waypointId)"
				)
			]
			manager.schedule()
			// Enter/exit reveals a node's movement relative to a named place; keep the event
			// visible but redact the node and waypoint names from logs.
			Logger.services.info("🔔 [Geofence] \(nodeName, privacy: .private) \(entered ? "entered" : "left", privacy: .public) \(waypointName, privacy: .private)")
		}
	}
}
