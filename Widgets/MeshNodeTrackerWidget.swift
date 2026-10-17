//
//  MeshNodeTrackerWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  A configurable widget that tracks one node: battery, signal, when it was
//  last heard and how far away it is. The node picker reads the shared
//  snapshot — the widget process never touches the database.
//

import AppIntents
import CoreLocation
import SwiftUI
import WidgetKit

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
		let nodes = WidgetSnapshotStore.load()?.nodes ?? []
		return identifiers.map { id in
			if let node = nodes.first(where: { String($0.num) == id }) {
				return TrackedNodeEntity(node: node)
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

// MARK: - Timeline

struct NodeTrackerEntry: TimelineEntry {
	let date: Date
	/// The configured node's names, even when it is not in the snapshot.
	let configured: TrackedNodeEntity?
	/// The node's current data, nil when it dropped out of the snapshot.
	let node: NodeSnapshot?
	let snapshot: WidgetSnapshot?

	var isStale: Bool {
		guard let snapshot else { return false }
		return date.timeIntervalSince(snapshot.generatedAt) >= 2 * 3600
	}

	/// Smart Stacks surface the widget when the node is reachable.
	var relevance: TimelineEntryRelevance? {
		guard let node else { return nil }
		return TimelineEntryRelevance(score: node.isOnline ? 50 : 0)
	}
}

struct NodeTrackerProvider: AppIntentTimelineProvider {
	func placeholder(in context: Context) -> NodeTrackerEntry {
		let snapshot = WidgetSnapshot.trackerPreview
		return NodeTrackerEntry(date: .now, configured: snapshot.nodes.first.map(TrackedNodeEntity.init), node: snapshot.nodes.first, snapshot: snapshot)
	}

	func snapshot(for configuration: TrackNodeIntent, in context: Context) async -> NodeTrackerEntry {
		entry(for: configuration, at: .now, preview: context.isPreview)
	}

	func timeline(for configuration: TrackNodeIntent, in context: Context) async -> Timeline<NodeTrackerEntry> {
		let now = Date()
		// The stale flip belongs two hours after the snapshot was generated, not
		// two hours after this reload. Once that moment has passed (or there is
		// no snapshot) the tail entry only sets the .atEnd reload cadence.
		let first = entry(for: configuration, at: now, preview: false)
		var secondDate = now.addingTimeInterval(2 * 3600)
		if let generatedAt = first.snapshot?.generatedAt {
			let staleDate = generatedAt.addingTimeInterval(2 * 3600)
			if staleDate > now {
				secondDate = staleDate
			}
		}
		return Timeline(
			entries: [
				first,
				entry(for: configuration, at: secondDate, preview: false)
			],
			policy: .atEnd
		)
	}

	private func entry(for configuration: TrackNodeIntent, at date: Date, preview: Bool) -> NodeTrackerEntry {
		var snapshot = WidgetSnapshotStore.load()
		if snapshot == nil, preview {
			snapshot = .trackerPreview
		}
		// An unconfigured widget falls back to the snapshot's first node, the
		// same default the picker offers.
		let configured = configuration.node ?? snapshot?.nodes.first.map(TrackedNodeEntity.init)
		let node = snapshot?.nodes.first { String($0.num) == configured?.id }
		return NodeTrackerEntry(date: date, configured: configured, node: node, snapshot: snapshot)
	}
}

// MARK: - Widget

struct MeshNodeTrackerWidget: Widget {
	var body: some WidgetConfiguration {
		AppIntentConfiguration(kind: "MeshNodeTracker", intent: TrackNodeIntent.self, provider: NodeTrackerProvider()) { entry in
			NodeTrackerWidgetView(entry: entry)
				.containerBackground(Color(UIColor.systemBackground), for: .widget)
				.widgetURL(entry.configured?.nodeNum.flatMap { URL(string: "meshtastic:///nodes?nodenum=\($0)") })
		}
		.configurationDisplayName("Node Tracker")
		.description("Battery, signal and last heard for a node you pick.")
		.supportedFamilies([
			.systemSmall, .systemMedium,
			.accessoryInline, .accessoryCircular, .accessoryRectangular
		])
	}
}

// MARK: - Views

struct NodeTrackerWidgetView: View {
	@Environment(\.widgetFamily) private var family
	let entry: NodeTrackerEntry

	var body: some View {
		if let configured = entry.configured {
			content(configured)
				.opacity(entry.isStale ? 0.55 : 1)
		} else {
			noNodeView
		}
	}

	@ViewBuilder
	private func content(_ configured: TrackedNodeEntity) -> some View {
		switch family {
		case .accessoryInline:
			TrackerInlineView(configured: configured, node: entry.node)
		case .accessoryCircular:
			TrackerCircularView(configured: configured, node: entry.node)
		case .accessoryRectangular:
			TrackerRectangularView(configured: configured, node: entry.node)
		case .systemMedium:
			TrackerMediumView(configured: configured, node: entry.node, snapshot: entry.snapshot)
		default:
			TrackerSmallView(configured: configured, node: entry.node)
		}
	}

	@ViewBuilder
	private var noNodeView: some View {
		switch family {
		case .accessoryInline:
			Text("Choose a node")
		case .accessoryCircular:
			Image(systemName: "person.crop.circle.badge.questionmark")
				.font(.title2)
				.widgetAccentable()
				.accessibilityLabel("Choose a node to track")
		default:
			VStack(spacing: 6) {
				Image(systemName: "person.crop.circle.badge.questionmark")
					.font(.title2)
					.foregroundStyle(.secondary)
					.widgetAccentable()
				Text("Touch and hold to choose a node")
					.font(.caption2)
					.multilineTextAlignment(.center)
					.foregroundStyle(.secondary)
			}
		}
	}
}

// MARK: System families

private struct TrackerSmallView: View {
	let configured: TrackedNodeEntity
	let node: NodeSnapshot?

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 6) {
				MeshLogo(height: 13)
				Spacer()
				OnlineDot(node: node)
			}
			NodeChip(shortName: configured.shortName, colorSeed: UInt32(truncatingIfNeeded: configured.nodeNum ?? 0), size: 30)
			Text(configured.longName)
				.font(.callout.weight(.semibold))
				.lineLimit(1)
			Spacer(minLength: 2)
			if let node {
				HStack(spacing: 8) {
					BatteryRow(level: node.batteryLevel, font: .caption)
					SignalBars(rating: node.signalRating)
				}
				HeardFooter(node: node)
			} else {
				Text("Not in recent nodes")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}
}

private struct TrackerMediumView: View {
	let configured: TrackedNodeEntity
	let node: NodeSnapshot?
	let snapshot: WidgetSnapshot?

	var body: some View {
		HStack(spacing: 12) {
			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 6) {
					MeshLogo(height: 13)
					NodeChip(shortName: configured.shortName, colorSeed: UInt32(truncatingIfNeeded: configured.nodeNum ?? 0), size: 26)
					if node?.isFavorite == true {
						Image(systemName: "star.fill")
							.font(.caption)
							.foregroundStyle(.yellow)
					}
				}
				Text(configured.longName)
					.font(.headline)
					.lineLimit(1)
				Spacer(minLength: 2)
				if let node {
					HeardFooter(node: node)
				} else {
					Text("Not in recent nodes")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
			Spacer()
			if let node {
				VStack(alignment: .trailing, spacing: 4) {
					OnlineDot(node: node)
					BatteryRow(level: node.batteryLevel, font: .caption)
					SignalBars(rating: node.signalRating)
					HopsLine(hopsAway: node.hopsAway)
					if let distance = distanceText(node: node, snapshot: snapshot) {
						Label(distance, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
							.font(.caption2)
							.foregroundStyle(.secondary)
					}
				}
			}
		}
	}
}

// MARK: Accessory families

private struct TrackerInlineView: View {
	let configured: TrackedNodeEntity
	let node: NodeSnapshot?

	var body: some View {
		if let node, let lastHeard = node.lastHeard {
			Text("\(configured.shortName) · \(lastHeard, style: .relative) ago")
		} else {
			Text("\(configured.shortName) · not seen")
		}
	}
}

private struct TrackerCircularView: View {
	@Environment(\.isLuminanceReduced) private var isLuminanceReduced
	let configured: TrackedNodeEntity
	let node: NodeSnapshot?

	var body: some View {
		Gauge(value: Double(node?.signalRating ?? 0), in: 0...3) {
			MeshLogo(height: 8)
		} currentValueLabel: {
			VStack(spacing: -2) {
				Text(configured.shortName)
					.font(.headline)
					.minimumScaleFactor(0.5)
					.lineLimit(1)
				Text("signal")
					.font(.system(size: 8, weight: .semibold))
					.foregroundStyle(.secondary)
			}
		}
		.gaugeStyle(.accessoryCircular)
		.opacity(isLuminanceReduced ? 0.6 : 1)
		.widgetAccentable()
	}
}

private struct TrackerRectangularView: View {
	let configured: TrackedNodeEntity
	let node: NodeSnapshot?

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			HStack(spacing: 4) {
				MeshLogo(height: 9)
				Text(configured.longName)
					.font(.headline)
					.lineLimit(1)
			}
			.widgetAccentable()
			if let node {
				HStack(spacing: 6) {
					if let level = node.batteryLevel {
						Text(level > 100 ? "Powered" : "\(level)%")
					}
					SignalBars(rating: node.signalRating)
				}
				.font(.caption)
				HeardFooter(node: node)
			} else {
				Text("Not in recent nodes")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}
}

// MARK: Pieces

private struct OnlineDot: View {
	let node: NodeSnapshot?

	// Shape as well as hue: on monochrome surfaces (vibrant lock screen,
	// tinted home screen) green and gray render the same, so offline is an
	// open ring, online a filled dot.
	var body: some View {
		if node?.isOnline == true {
			Circle()
				.fill(Color.green)
				.frame(width: 7, height: 7)
				.accessibilityLabel("Online")
		} else {
			Circle()
				.strokeBorder(Color.secondary, lineWidth: 1.5)
				.frame(width: 7, height: 7)
				.accessibilityLabel("Offline")
		}
	}
}

private struct HopsLine: View {
	let hopsAway: Int32

	var body: some View {
		Text(hopsAway == 0 ? "Direct" : (hopsAway == 1 ? "1 hop" : "\(hopsAway) hops"))
			.font(.caption2)
			.foregroundStyle(.secondary)
	}
}

private struct HeardFooter: View {
	let node: NodeSnapshot

	var body: some View {
		if let lastHeard = node.lastHeard {
			Text("Heard \(lastHeard, style: .relative) ago")
				.font(.caption2)
				.foregroundStyle(.secondary)
				.lineLimit(1)
		} else {
			Text("Never heard")
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
	}
}

/// Distance from the connected radio, when both ends have a position. A
/// disconnected snapshot keeps the last radio's identity, and a distance from
/// a radio that is no longer attached would read as live — so connected only.
private func distanceText(node: NodeSnapshot?, snapshot: WidgetSnapshot?) -> String? {
	guard let node, let snapshot,
		  snapshot.connectionState == .connected,
		  let lat = node.latitude, let lon = node.longitude,
		  let radioNum = snapshot.radioNodeNum, radioNum != node.num,
		  let radio = snapshot.nodes.first(where: { $0.num == radioNum }),
		  let radioLat = radio.latitude, let radioLon = radio.longitude else {
		return nil
	}
	let meters = CLLocation(latitude: lat, longitude: lon)
		.distance(from: CLLocation(latitude: radioLat, longitude: radioLon))
	let formatter = MeasurementFormatter()
	formatter.unitOptions = .naturalScale
	formatter.numberFormatter.maximumFractionDigits = 1
	return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
}

// MARK: Preview data

extension WidgetSnapshot {
	/// Gallery and placeholder content — never written to the store.
	static var trackerPreview: WidgetSnapshot {
		WidgetSnapshot(
			generatedAt: Date(timeIntervalSinceNow: -120),
			connectionState: .connected,
			radioNodeNum: 0x67EA94,
			radioLongName: "Meshtastic 5fac",
			radioShortName: "5fac",
			radioBatteryLevel: 87,
			localStats: nil,
			nodes: [
				NodeSnapshot(
					num: 0x43B2A1,
					longName: "Basecamp Solar",
					shortName: "BCS1",
					colorSeed: 0x43B2A1,
					batteryLevel: 76,
					snr: 9.5,
					rssi: -85,
					signalRating: 3,
					lastHeard: Date(timeIntervalSinceNow: -480),
					isOnline: true,
					hopsAway: 0,
					latitude: 47.61,
					longitude: -122.35,
					isFavorite: true
				)
			],
			totalNodeCount: 87,
			unreadChannelMessages: 0,
			unreadDirectMessages: 0,
			recentMessages: []
		)
	}
}
