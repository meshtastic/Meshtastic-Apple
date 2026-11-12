//
//  TelemetryWidgetIntent.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
//  The Telemetry widget's configuration: a node that reports environment,
//  air quality or power telemetry and up to eight of its metrics, in order. Shared with the app so
//  it can ask iOS which nodes the widgets are set to and keep them in the
//  snapshot.
//

import AppIntents
import Foundation
import WidgetKit

// MARK: - Node

/// A node with environment readings. Like `TrackedNodeEntity`, `entities(for:)`
/// answers every identifier it's asked for, so a saved node never dissolves.
struct TelemetryNodeEntity: AppEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Node")
	static let defaultQuery = TelemetryNodeQuery()

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

struct TelemetryNodeQuery: EntityQuery {
	func entities(for identifiers: [String]) async throws -> [TelemetryNodeEntity] {
		// The tracker's query already falls back to the missing list and hex names.
		try await TrackedNodeQuery().entities(for: identifiers).map(TelemetryNodeEntity.init)
	}

	/// The nodes that have reported environment telemetry, the connected radio first.
	func suggestedEntities() async throws -> [TelemetryNodeEntity] {
		Self.telemetryNodes(in: WidgetSnapshotStore.load()).map(TelemetryNodeEntity.init)
	}

	func defaultResult() async -> TelemetryNodeEntity? {
		try? await suggestedEntities().first
	}

	static func telemetryNodes(in snapshot: WidgetSnapshot?) -> [NodeSnapshot] {
		guard let snapshot else { return [] }
		let nodes = snapshot.nodes.filter { $0.telemetry != nil }
		let radio = nodes.filter { $0.num == snapshot.radioNodeNum }
		return radio + nodes.filter { $0.num != snapshot.radioNodeNum }
	}
}

// MARK: - Metrics

struct TelemetryMetricEntity: AppEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")
	static let defaultQuery = TelemetryMetricQuery()

	let metric: TelemetryMetric

	var id: String { metric.rawValue }

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: metric.title, image: .init(systemName: metric.systemImage))
	}
}

struct TelemetryMetricQuery: EntityQuery {
	@IntentParameterDependency<TelemetryWidgetIntent>(\.$node)
	var intent

	func entities(for identifiers: [String]) async throws -> [TelemetryMetricEntity] {
		identifiers.compactMap(TelemetryMetric.init(rawValue:)).map(TelemetryMetricEntity.init)
	}

	/// The metrics the chosen node has reported, or every metric before a node is chosen.
	func suggestedEntities() async throws -> [TelemetryMetricEntity] {
		let snapshot = WidgetSnapshotStore.load()
		let nodeID = intent?.node.id ?? TelemetryNodeQuery.telemetryNodes(in: snapshot).first.map { String($0.num) }
		let telemetry = snapshot?.nodes.first { String($0.num) == nodeID }?.telemetry
		let metrics = telemetry?.reportedMetrics ?? TelemetryMetric.allCases
		return metrics.map(TelemetryMetricEntity.init)
	}
}

// MARK: - Intent

struct TelemetryWidgetIntent: WidgetConfigurationIntent {
	static let title: LocalizedStringResource = "Telemetry"
	static let description = IntentDescription("Pick a node, and any of its readings to leave out.")

	@Parameter(title: "Node")
	var node: TelemetryNodeEntity?

	/// The widget shows every reading the node reports except these. Settings can't start with
	/// a list filled in from the node, so the list is of readings to leave out rather than to show.
	@Parameter(title: "Hidden Readings")
	var hidden: [TelemetryMetricEntity]?
}
