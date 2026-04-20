//
//  MeshNode.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import CoreLocation

/// Lightweight in-memory model for a mesh node seen by the watch.
/// Transferred from the companion iOS app via WatchConnectivity.
struct MeshNode: Identifiable, Equatable, Codable {
	/// Meshtastic node number (unique on the mesh).
	let num: UInt32
	/// Stable identifier derived from the node number.
	var id: UInt32 { num }

	var longName: String
	var shortName: String

	/// Latest known position (latitude / longitude in degrees, altitude in metres).
	var latitude: Double?
	var longitude: Double?
	var altitude: Int32?

	/// When the position was last updated.
	var lastPositionTime: Date?

	/// When we last heard *any* packet from this node.
	var lastHeard: Date?

	/// Signal-to-noise ratio of the last received packet (dB).
	var snr: Float?

	// MARK: - Derived helpers

	/// A coordinate suitable for bearing/distance calculations, or `nil` when we
	/// have no valid position.
	var coordinate: CLLocationCoordinate2D? {
		guard let lat = latitude, let lon = longitude,
			  lat != 0, lon != 0 else { return nil }
		return CLLocationCoordinate2D(latitude: lat, longitude: lon)
	}

	/// `CLLocation` wrapper – handy for `distance(from:)`.
	var location: CLLocation? {
		guard let coord = coordinate else { return nil }
		return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
	}

	/// Distance in metres from the given user location, or `nil` when there is
	/// no valid node position.
	func distance(from userLocation: CLLocation) -> CLLocationDistance? {
		guard let nodeLoc = location else { return nil }
		return userLocation.distance(from: nodeLoc)
	}

	/// `true` when the node has been heard in the last two hours.
	var isOnline: Bool {
		guard let lastHeard else { return false }
		return lastHeard.timeIntervalSinceNow > -7200
	}
}
