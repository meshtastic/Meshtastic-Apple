//
//  TrackNodeIntent.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
//  The Node Tracker widget's configuration. Shared with the app so it can ask
//  iOS which nodes the trackers are set to, and keep those nodes in the
//  snapshot.
//

import AppIntents
import Foundation

// MARK: - Configuration

/// A node the user can pick in the widget's configuration. AppIntents stores
/// only the entity's identifier and rehydrates it through the query, so the
/// name fields do not persist on their own — `entities(for:)` must answer
/// every identifier it is asked for, or the stored configuration dissolves
/// and the widget silently retargets.
struct TrackedNodeEntity: AppEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Node")
	static let defaultQuery = TrackedNodeQuery()

	/// The node number as a string.
	let id: String
	let longName: String
	let shortName: String

	var nodeNum: Int64? { Int64(id) }

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(longName)", subtitle: "\(shortName)")
	}

	init(node: NodeSnapshot) {
		self.id = String(node.num)
		self.longName = node.longName
		self.shortName = node.shortName
	}

	init(missing node: MissingNodeSnapshot) {
		self.id = String(node.num)
		self.longName = node.longName
		self.shortName = node.shortName
	}

	/// A node that is no longer in the snapshot: keep its identity and fall
	/// back to the hex naming the app uses for nodes without user info.
	init(identifier: String) {
		self.id = identifier
		if let num = Int64(identifier) {
			let hex = String(format: "%08x", UInt32(truncatingIfNeeded: num))
			self.longName = "Node \(hex)"
			self.shortName = String(hex.suffix(4))
		} else {
			self.longName = "Unknown node"
			self.shortName = "?"
		}
	}
}

struct TrackedNodeQuery: EntityQuery {
	func entities(for identifiers: [String]) async throws -> [TrackedNodeEntity] {
		let snapshot = WidgetSnapshotStore.load()
		let nodes = snapshot?.nodes ?? []
		let missing = snapshot?.missingTrackedNodes ?? []
		return identifiers.map { id in
			if let node = nodes.first(where: { String($0.num) == id }) {
				return TrackedNodeEntity(node: node)
			}
			// Gone from the node database: keep the name it had.
			if let node = missing.first(where: { String($0.num) == id }) {
				return TrackedNodeEntity(missing: node)
			}
			return TrackedNodeEntity(identifier: id)
		}
	}

	/// The picker list: the snapshot's nodes, favorites first — the same order
	/// the app wrote them in.
	func suggestedEntities() async throws -> [TrackedNodeEntity] {
		(WidgetSnapshotStore.load()?.nodes ?? []).map(TrackedNodeEntity.init)
	}

	func defaultResult() async -> TrackedNodeEntity? {
		try? await suggestedEntities().first
	}
}

struct TrackNodeIntent: WidgetConfigurationIntent {
	static let title: LocalizedStringResource = "Track Node"
	static let description = IntentDescription("Pick a node to keep an eye on.")

	@Parameter(title: "Node")
	var node: TrackedNodeEntity?
}
