//
//  MeshNode.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Lightweight, in-memory model for a mesh node. Intentionally NOT the SwiftData
//  `NodeInfoEntity` from the iOS app — the tvOS v1 client keeps everything in memory
//  and rebuilds it from the FromRadio stream on each connect.
//

import CoreLocation
import Foundation

struct MeshNode: Identifiable, Hashable {
	let num: UInt32

	var longName: String
	var shortName: String

	var latitude: Double?
	var longitude: Double?

	var lastHeard: Date?
	var batteryLevel: Int?
	var snr: Float?
	var role: String?
	var hwModel: String?

	var id: UInt32 { num }

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

	init(num: UInt32,
	     longName: String = "",
	     shortName: String = "",
	     latitude: Double? = nil,
	     longitude: Double? = nil,
	     lastHeard: Date? = nil,
	     batteryLevel: Int? = nil,
	     snr: Float? = nil,
	     role: String? = nil,
	     hwModel: String? = nil) {
		self.num = num
		self.longName = longName
		self.shortName = shortName
		self.latitude = latitude
		self.longitude = longitude
		self.lastHeard = lastHeard
		self.batteryLevel = batteryLevel
		self.snr = snr
		self.role = role
		self.hwModel = hwModel
	}
}
