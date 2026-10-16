//
//  WidgetSnapshot.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  The data contract between the app and the widget extension. The app writes a
//  snapshot to the shared app group whenever mesh state changes; widgets only
//  read it. Versioned like MeshShareSnapshot: readers reject other versions and
//  show their placeholder instead of guessing at stale fields.
//

import Foundation

struct WidgetSnapshot: Codable {
	static let currentVersion = 1

	var version: Int = WidgetSnapshot.currentVersion
	let generatedAt: Date

	let connectionState: WidgetConnectionState
	let radioNodeNum: Int64?
	let radioLongName: String?
	let radioShortName: String?
	/// From device metrics — LocalStats telemetry does not carry battery.
	let radioBatteryLevel: Int32?

	/// The connected radio's most recent LocalStats telemetry.
	let localStats: LocalStatsSnapshot?

	/// Favorites first, then most recently heard. Capped small — this feeds the
	/// node-tracker widget picker and rows, not a full node database.
	let nodes: [NodeSnapshot]
	/// The real node-database size, so widgets never present the capped `nodes`
	/// list as the mesh.
	let totalNodeCount: Int

	let unreadChannelMessages: Int
	let unreadDirectMessages: Int

	/// Newest first, capped small.
	let recentMessages: [MessageSnapshot]
}

enum WidgetConnectionState: String, Codable {
	case connected
	case connecting
	case disconnected
}

struct LocalStatsSnapshot: Codable {
	let statsAt: Date
	let uptimeSeconds: Int32?
	let channelUtilization: Float?
	let airUtilTx: Float?
	let packetsSent: Int32
	let packetsReceived: Int32
	let packetsReceivedBad: Int32
	let packetsReceivedDupe: Int32
	let packetsRelayed: Int32
	let packetsRelayCanceled: Int32
	let nodesOnline: Int32
	let nodesTotal: Int32
}

struct NodeSnapshot: Codable, Identifiable {
	let num: Int64
	let longName: String
	let shortName: String
	/// The node number as the color seed — widgets derive the same node color
	/// the app does without needing the app's color extensions.
	let colorSeed: UInt32
	let batteryLevel: Int32?
	let snr: Float?
	let rssi: Int32?
	/// Precomputed in the app (needs ModemPresets): 0 none … 3 good.
	let signalRating: Int?
	let lastHeard: Date?
	let isOnline: Bool
	let hopsAway: Int32
	let latitude: Double?
	let longitude: Double?
	let isFavorite: Bool

	var id: Int64 { num }
}

struct MessageSnapshot: Codable, Identifiable {
	enum Kind: Codable {
		case channel(index: Int32, name: String)
		case directMessage(userNum: Int64)
	}

	let messageId: Int64
	let kind: Kind
	let senderShortName: String
	let senderLongName: String
	let senderColorSeed: UInt32
	let text: String
	let timestamp: Date
	let isUnread: Bool

	var id: Int64 { messageId }
}
