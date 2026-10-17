//
//  MeshLiveActivityAttributes.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//
//  The Live Activity's data. The user picks what it shows when starting it:
//  a glance at the mesh, or one node. The mode is fixed for the activity's
//  life; switching modes ends it and starts a new one.
//

import Foundation

/// What a Live Activity shows. Outside the ActivityKit guard so the app can
/// name a mode on every platform, including ones without Live Activities.
enum LiveActivityMode: Codable, Hashable {
	/// Connection, nodes online, unread messages and the radio's battery.
	case meshStatus
	/// One node: battery, signal, when it was last heard and how far away.
	case trackNode(num: Int64)

	var trackedNodeNum: Int64? {
		if case .trackNode(let num) = self { return num }
		return nil
	}
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
import ActivityKit

struct MeshLiveActivityAttributes: ActivityAttributes {
	let mode: LiveActivityMode
	/// When it started. The system ends a Live Activity after 8 hours, so the
	/// views can say when updates stop.
	let startedAt: Date
	/// The connected radio when it started.
	let radioNum: Int64
	let radioShortName: String
	let radioLongName: String
	/// The tracked node's names; nil in mesh status mode.
	let nodeShortName: String?
	let nodeLongName: String?

	/// How long the system keeps a Live Activity updating.
	static let maximumDuration: TimeInterval = 8 * 3600

	var updatesEndAt: Date { startedAt.addingTimeInterval(Self.maximumDuration) }

	struct ContentState: Codable, Hashable {
		var connection: WidgetConnectionState
		/// When this content was built.
		var updatedAt: Date

		// Mesh status
		var nodesOnline: Int32?
		var nodesTotal: Int32?
		/// When the radio's LocalStats behind the node counts were taken; the
		/// counts can be older than the content.
		var statsAt: Date?
		var unreadCount: Int?
		var radioBattery: Int32?

		// Track a node
		var nodeBattery: Int32?
		/// Signal quality 0 (none) to 3 (good), as on the node's detail screen.
		var signalRating: Int?
		var lastHeard: Date?
		var hopsAway: Int32?
		/// Meters from the connected radio, when both have a position.
		var distanceMeters: Double?

		/// The same content ignoring when it was built, so an update is only
		/// sent when something a person would see changed.
		func sameReadings(as other: ContentState) -> Bool {
			var lhs = self
			var rhs = other
			lhs.updatedAt = .distantPast
			rhs.updatedAt = .distantPast
			return lhs == rhs
		}
	}
}
#endif
