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
	/// Raw protobuf role value (`Config.DeviceConfig.Role`), mapped for display by
	/// `nodeRole`. Stored as the raw Int so the slim tvOS store doesn't depend on the
	/// app's full `DeviceRoles` enum (which isn't in this target).
	var roleValue: Int?
	var hwModel: String?

	init(num: UInt32) {
		self.numRaw = Int(num)
		// Firmware/app default when we have no NodeInfo yet: "Meshtastic <last4>" and
		// "<last4>" (the last 4 hex of the node number). A real NodeInfo frame overwrites
		// these — this is what stops a packet-discovered node from rendering as "?".
		let last4 = String(String(format: "%08x", num).suffix(4))
		self.longName = "Meshtastic \(last4)"
		self.shortName = last4
	}

	// MARK: - Derived

	var num: UInt32 { UInt32(truncatingIfNeeded: numRaw) }

	var hasLocation: Bool { latitude != nil && longitude != nil }

	var coordinate: CLLocationCoordinate2D? {
		guard let latitude, let longitude else { return nil }
		return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}

	/// Heard within the last two hours — matches the iOS `NodeInfoEntity.isOnline`.
	var isOnline: Bool {
		guard let lastHeard else { return false }
		return Date().timeIntervalSince(lastHeard) < 120 * 60
	}

	/// Display role, mapped from the raw protobuf value.
	var nodeRole: NodeRole? { roleValue.flatMap(NodeRole.init(rawValue:)) }

	/// Fallback display name so a node with no user record still shows something stable.
	var displayName: String {
		if !longName.isEmpty { return longName }
		if !shortName.isEmpty { return shortName }
		return String(format: "!%08x", num)
	}
}

/// tvOS-local role lookup — a slim port of the app's `DeviceRoles` (name + icon only),
/// keyed by the protobuf role raw value. The full iOS enum isn't in this target.
enum NodeRole: Int {
	case client = 0
	case clientMute = 1
	case router = 2
	case tracker = 5
	case sensor = 6
	case tak = 7
	case clientHidden = 8
	case lostAndFound = 9
	case takTracker = 10
	case routerLate = 11
	case clientBase = 12

	var name: String {
		switch self {
		case .client: return "Client"
		case .clientMute: return "Client Mute"
		case .router: return "Router"
		case .tracker: return "Tracker"
		case .sensor: return "Sensor"
		case .tak: return "TAK"
		case .takTracker: return "TAK Tracker"
		case .clientHidden: return "Client Hidden"
		case .lostAndFound: return "Lost and Found"
		case .routerLate: return "Router Late"
		case .clientBase: return "Client Base"
		}
	}

	var systemName: String {
		switch self {
		case .client: return "apps.iphone"
		case .clientMute: return "speaker.slash"
		case .router, .routerLate: return "wifi.router"
		case .tracker: return "mappin.and.ellipse.circle"
		case .sensor: return "sensor"
		case .tak: return "shield.checkered"
		case .takTracker: return "dog"
		case .clientHidden: return "eye.slash"
		case .lostAndFound: return "map"
		case .clientBase: return "house"
		}
	}
}
