//
//  EnvironmentWidgetIntent.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
//  The Environment widget's configuration: a node that reports environment
//  telemetry and up to eight of its metrics, in order. Shared with the app so
//  it can ask iOS which nodes the widgets are set to and keep them in the
//  snapshot.
//

import AppIntents
import Foundation
import WidgetKit

// MARK: - Node

/// A node with environment readings. Like `TrackedNodeEntity`, `entities(for:)`
/// answers every identifier it's asked for, so a saved node never dissolves.
struct EnvironmentNodeEntity: AppEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Node")
	static let defaultQuery = EnvironmentNodeQuery()

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

	init(tracked: TrackedNodeEntity) {
		self.id = tracked.id
		self.longName = tracked.longName
		self.shortName = tracked.shortName
	}
}

struct EnvironmentNodeQuery: EntityQuery {
	func entities(for identifiers: [String]) async throws -> [EnvironmentNodeEntity] {
		// The tracker's query already falls back to the missing list and hex names.
		try await TrackedNodeQuery().entities(for: identifiers).map(EnvironmentNodeEntity.init)
	}

	/// The nodes that have reported environment telemetry, the connected radio first.
	func suggestedEntities() async throws -> [EnvironmentNodeEntity] {
		Self.environmentNodes(in: WidgetSnapshotStore.load()).map(EnvironmentNodeEntity.init)
	}

	func defaultResult() async -> EnvironmentNodeEntity? {
		try? await suggestedEntities().first
	}

	static func environmentNodes(in snapshot: WidgetSnapshot?) -> [NodeSnapshot] {
		guard let snapshot else { return [] }
		let nodes = snapshot.nodes.filter { $0.environment != nil }
		let radio = nodes.filter { $0.num == snapshot.radioNodeNum }
		return radio + nodes.filter { $0.num != snapshot.radioNodeNum }
	}
}

// MARK: - Metrics

struct EnvironmentMetricEntity: AppEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")
	static let defaultQuery = EnvironmentMetricQuery()

	let metric: EnvironmentMetric

	var id: String { metric.rawValue }

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: metric.title, image: .init(systemName: metric.systemImage))
	}
}

struct EnvironmentMetricQuery: EntityQuery {
	@IntentParameterDependency<EnvironmentWidgetIntent>(\.$node)
	var intent

	func entities(for identifiers: [String]) async throws -> [EnvironmentMetricEntity] {
		identifiers.compactMap(EnvironmentMetric.init(rawValue:)).map(EnvironmentMetricEntity.init)
	}

	/// The metrics the chosen node has reported, or every metric before a node is chosen.
	func suggestedEntities() async throws -> [EnvironmentMetricEntity] {
		let snapshot = WidgetSnapshotStore.load()
		let nodeID = intent?.node.id ?? EnvironmentNodeQuery.environmentNodes(in: snapshot).first.map { String($0.num) }
		let environment = snapshot?.nodes.first { String($0.num) == nodeID }?.environment
		let metrics = environment?.reportedMetrics ?? EnvironmentMetric.allCases
		return metrics.map(EnvironmentMetricEntity.init)
	}
}

// MARK: - Intent

struct EnvironmentWidgetIntent: WidgetConfigurationIntent {
	static let title: LocalizedStringResource = "Environment"
	static let description = IntentDescription("Pick a node and the readings to show.")

	@Parameter(title: "Node")
	var node: EnvironmentNodeEntity?

	/// Every size takes the full list, so shrinking a widget keeps the first ones.
	/// The literal is `EnvironmentMetric.maximumCount`.
	@Parameter(title: "Readings", size: 8)
	var metrics: [EnvironmentMetricEntity]?
}
