//
//  MeshNode.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Persistent, tvOS-local model for a mesh node. Deliberately NOT the iOS
//  `NodeInfoEntity` — that entity's relationship graph is a single connected
//  component of ~39 tables (messages, channels, traceroutes, every config), so it
//  can't be subsetted for a map. This is a slim, map-scoped SwiftData store: the
//  map is populated on relaunch from the last session, before the radio's node-DB
//  dump completes.
//

import CoreLocation
import Foundation
import SwiftData

@Model
final class MeshNode {

	/// Node number. Stored as `Int` (Int64-backed — SwiftData/Core Data has no
	/// native `UInt32`); the full `UInt32` range fits losslessly and is recovered
	/// by `num`. Upserts key on this via `MeshClient.node(for:)`.
	var numRaw: Int = 0

	var longName: String = ""
	var shortName: String = ""

	var latitude: Double?
	var longitude: Double?

	var lastHeard: Date?
	var batteryLevel: Int?
	var snr: Float?
	var role: String?
	var hwModel: String?

	init(num: UInt32) {
		self.numRaw = Int(num)
	}

	// MARK: - Derived

	var num: UInt32 { UInt32(truncatingIfNeeded: numRaw) }

	var hasLocation: Bool { latitude != nil && longitude != nil }

	var coordinate: CLLocationCoordinate2D? {
		guard let latitude, let longitude else { return nil }
		return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}

	/// Fallback display name so a node with no user record still shows something stable.
	var displayName: String {
		if !longName.isEmpty { return longName }
		if !shortName.isEmpty { return shortName }
		return String(format: "!%08x", num)
	}
}
