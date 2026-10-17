//
//  MeshNodeMapWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  A map of the mesh in the trace route share image's look: node circles on
//  dark tiles, the radio's name, and how many nodes are on the map, how many
//  are online and how far the farthest one is. The app renders the map image
//  only when a pin moves; the counts cover the drawn nodes, read from the
//  live snapshot where it still lists them.
//

import SwiftUI
import WidgetKit

private typealias Style = ShareCardStyle

// MARK: - Timeline

/// What the widget says about the nodes on the map.
struct NodeMapSummary {
	let title: String
	let onMap: Int
	let online: Int
	let favorites: Int
	/// Meters from the radio to the farthest node on the map, when the radio
	/// has a position.
	let farthest: Double?
	let updatedAt: Date?
	let connectionState: WidgetConnectionState

	init(meta: WidgetMapMeta, snapshot: WidgetSnapshot?) {
		let stats = WidgetMapStats(meta: meta, snapshot: snapshot)
		title = snapshot?.radioLongName ?? String(localized: "Meshtastic")
		onMap = stats.onMap
		online = stats.online
		favorites = stats.favorites
		farthest = stats.farthest
		updatedAt = snapshot?.generatedAt ?? meta.generatedAt
		connectionState = snapshot?.connectionState ?? .disconnected
	}

	private init(title: String, onMap: Int, online: Int, favorites: Int, farthest: Double?) {
		self.title = title
		self.onMap = onMap
		self.online = online
		self.favorites = favorites
		self.farthest = farthest
		self.updatedAt = Date(timeIntervalSinceNow: -120)
		self.connectionState = .connected
	}

	/// Gallery content to go with the bundled sample map.
	static let preview = NodeMapSummary(title: "Capitol Hill Relay", onMap: 24, online: 19, favorites: 5, farthest: 21_400)
}

struct MeshNodeMapEntry: TimelineEntry {
	let date: Date
	let meta: WidgetMapMeta?
	let summary: NodeMapSummary?
	let isPreview: Bool

	/// The mesh data, not the image, decides staleness: a mesh where nothing
	/// moved has an old image and current data.
	var isStale: Bool {
		guard let updatedAt = summary?.updatedAt else { return false }
		return date.timeIntervalSince(updatedAt) >= 2 * 3600
	}
}

struct MeshNodeMapProvider: TimelineProvider {
	func placeholder(in context: Context) -> MeshNodeMapEntry {
		entry(at: .now, isPreview: true)
	}

	func getSnapshot(in context: Context, completion: @escaping (MeshNodeMapEntry) -> Void) {
		completion(entry(at: .now, isPreview: context.isPreview))
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<MeshNodeMapEntry>) -> Void) {
		let first = entry(at: .now, isPreview: false)
		let now = Date()
		// The stale flip belongs two hours after the data was written, not two
		// hours after this reload.
		var secondDate = now.addingTimeInterval(2 * 3600)
		if let updatedAt = first.summary?.updatedAt {
			let staleDate = updatedAt.addingTimeInterval(2 * 3600)
			if staleDate > now {
				secondDate = staleDate
			}
		}
		let entries = [
			first,
			MeshNodeMapEntry(date: secondDate, meta: first.meta, summary: first.summary, isPreview: false)
		]
		completion(Timeline(entries: entries, policy: .atEnd))
	}

	private func entry(at date: Date, isPreview: Bool) -> MeshNodeMapEntry {
		let meta = WidgetMapStore.loadMeta()
		let summary = meta.map { NodeMapSummary(meta: $0, snapshot: WidgetSnapshotStore.load()) }
		return MeshNodeMapEntry(date: date, meta: meta, summary: summary, isPreview: isPreview)
	}
}

// MARK: - Widget

struct MeshNodeMapWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "MeshNodeMap", provider: MeshNodeMapProvider()) { entry in
			MeshNodeMapWidgetView(entry: entry)
				.containerBackground(for: .widget) { Style.background }
				.environment(\.colorScheme, .dark)
				.widgetURL(URL(string: "meshtastic:///map"))
		}
		.configurationDisplayName("Node Map")
		.description("Your mesh's nodes on a map.")
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
		.contentMarginsDisabled()
	}
}

// MARK: - Views

struct MeshNodeMapWidgetView: View {
	@Environment(\.widgetFamily) private var family
	let entry: MeshNodeMapEntry

	var body: some View {
		if let summary = entry.summary, let map = mapImage {
			content(summary: summary, map: map)
		} else if entry.isPreview, let sample = UIImage(named: family == .systemLarge ? "widget-map-preview-wide" : "widget-map-preview") {
			// Any preview that can't load a real image shows the bundled sample.
			content(summary: .preview, map: sample)
		} else if entry.meta?.nodeCount == 0 {
			placeholder(icon: "mappin.slash", text: "No node positions yet")
		} else {
			placeholder(icon: "map", text: "Open Meshtastic to render the map")
		}
	}

	@ViewBuilder
	private func content(summary: NodeMapSummary, map: UIImage) -> some View {
		// Data over two hours old dims the map; the age line says how old.
		let mapView = ShareMapImage(image: map).opacity(entry.isStale ? 0.55 : 1)
		switch family {
		case .systemLarge:
			MapLargeView(summary: summary, map: mapView)
		case .systemMedium:
			MapMediumView(summary: summary, map: mapView)
		default:
			MapSmallView(summary: summary, map: mapView)
		}
	}

	/// The rendered map. The square one serves small and medium, the wide one
	/// large.
	private var mapImage: UIImage? {
		WidgetMapStore.loadImageData(wide: family == .systemLarge).flatMap(UIImage.init(data:))
	}

	private func placeholder(icon: String, text: LocalizedStringKey) -> some View {
		VStack(spacing: 6) {
			Image(systemName: icon)
				.font(.title2)
				.foregroundStyle(Style.brand)
				.widgetAccentable()
			Text(text)
				.font(.caption2)
				.multilineTextAlignment(.center)
				.foregroundStyle(Style.secondaryText)
		}
		.padding(12)
	}
}

// MARK: Families

private struct MapSmallView<Map: View>: View {
	let summary: NodeMapSummary
	let map: Map

	var body: some View {
		VStack(alignment: .leading, spacing: 5) {
			HStack(spacing: 4) {
				MapHeader(summary: summary, compact: true)
				Spacer(minLength: 2)
				AgeLine(summary: summary)
			}
			map
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			HStack(spacing: 4) {
				Text("\(summary.onMap) on map")
					.foregroundStyle(.white)
				Spacer(minLength: 2)
				// Disconnected, the online count is stale; say why instead. Down
				// here so the age line up top keeps its room.
				if summary.connectionState == .connected {
					Text("\(summary.online) online")
						.foregroundStyle(Style.brand)
				} else {
					Text(stateText(summary.connectionState))
						.foregroundStyle(Style.secondaryText)
				}
			}
			.font(.caption2.weight(.semibold))
			.lineLimit(1)
		}
		.padding(12)
	}
}

private struct MapMediumView<Map: View>: View {
	let summary: NodeMapSummary
	let map: Map

	var body: some View {
		HStack(spacing: 12) {
			map
			VStack(alignment: .leading, spacing: 5) {
				MapHeader(summary: summary, compact: false)
				Text(summary.title)
					.font(.subheadline.weight(.semibold))
					.lineLimit(2)
					.minimumScaleFactor(0.7)
				Spacer(minLength: 0)
				HStack(spacing: 8) {
					Text("\(summary.onMap) on map")
						.foregroundStyle(.white)
					// Disconnected, the online count is stale; the header's tag
					// says why.
					if summary.connectionState == .connected {
						Text("\(summary.online) online")
							.foregroundStyle(Style.brand)
					}
				}
				.font(.caption2.weight(.semibold))
				.lineLimit(1)
				if let farthest = summary.farthest {
					Text("Farthest \(shareDistanceText(farthest))")
						.font(.caption2)
						.foregroundStyle(Style.secondaryText)
						.lineLimit(1)
				}
				AgeLine(summary: summary)
			}
			Spacer(minLength: 0)
		}
		.padding(12)
	}
}

private struct MapLargeView<Map: View>: View {
	let summary: NodeMapSummary
	let map: Map

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			MapHeader(summary: summary, compact: false)
			Text(summary.title)
				.font(.headline)
				.lineLimit(2)
				.minimumScaleFactor(0.7)
			map
				.frame(maxWidth: .infinity)
			HStack(spacing: 6) {
				ShareStatTile(title: "On Map", value: "\(summary.onMap)")
				// Disconnected, the online count is stale; the header's tag says why.
				ShareStatTile(
					title: "Online",
					value: summary.connectionState == .connected ? "\(summary.online)" : "—",
					color: summary.connectionState == .connected ? Style.brand : Style.secondaryText
				)
				ShareStatTile(title: "Farthest", value: summary.farthest.map(shareDistanceText) ?? "—")
				ShareStatTile(title: "Favorites", value: "\(summary.favorites)", color: .yellow)
			}
			Spacer(minLength: 0)
			AgeLine(summary: summary)
		}
		.padding(14)
	}
}

// MARK: Pieces

/// The Meshtastic mark, "Node Map" in brand green and, when the radio isn't
/// connected, a tag saying so.
private struct MapHeader: View {
	let summary: NodeMapSummary
	let compact: Bool

	var body: some View {
		HStack(spacing: 5) {
			MeshLogo(height: 10)
			if !compact {
				Text("Node Map")
					.font(.caption.weight(.semibold))
					.foregroundStyle(Style.brand)
					.lineLimit(1)
					.fixedSize()
			}
			// The small widget shows the state in its bottom line instead.
			if !compact, summary.connectionState != .connected {
				Text(stateText(summary.connectionState))
					.font(.system(size: 10, weight: .semibold))
					.foregroundStyle(Style.secondaryText)
					.padding(.horizontal, 5)
					.padding(.vertical, 1)
					.background(Style.panel, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
					.lineLimit(1)
					.fixedSize()
			}
		}
	}
}

private struct AgeLine: View {
	let summary: NodeMapSummary

	var body: some View {
		if let updatedAt = summary.updatedAt {
			Text("\(updatedAt, style: .relative) ago")
				.font(.caption2)
				.foregroundStyle(Style.tertiaryText)
				.lineLimit(1)
		}
	}
}
