//
//  MeshNodeMapWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  A map of the mesh: node chips on a pre-rendered map image. The app renders
//  the images (square for small/large, wide for medium, light and dark) with
//  MKMapSnapshotter and writes them to the app group — this process only
//  loads a PNG, so it stays inside the widget memory cap and never touches
//  the network.
//

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct MeshNodeMapEntry: TimelineEntry {
	let date: Date
	let meta: WidgetMapMeta?
	/// When the mesh data was last written — the image may be much older for
	/// a mesh whose nodes simply have not moved, and that is not staleness.
	let dataGeneratedAt: Date?
	/// Gallery and placeholder contexts show a bundled sample render, since
	/// the preview process may have no access to the rendered images.
	let isPreview: Bool

	var isStale: Bool {
		guard let reference = dataGeneratedAt ?? meta?.generatedAt else { return false }
		return date.timeIntervalSince(reference) >= 2 * 3600
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
		// The stale flip belongs two hours after the data was generated, not
		// two hours after this reload.
		var secondDate = now.addingTimeInterval(2 * 3600)
		if let reference = first.dataGeneratedAt ?? first.meta?.generatedAt {
			let staleDate = reference.addingTimeInterval(2 * 3600)
			if staleDate > now {
				secondDate = staleDate
			}
		}
		let entries = [
			first,
			MeshNodeMapEntry(date: secondDate, meta: first.meta, dataGeneratedAt: first.dataGeneratedAt, isPreview: false)
		]
		completion(Timeline(entries: entries, policy: .atEnd))
	}

	private func entry(at date: Date, isPreview: Bool) -> MeshNodeMapEntry {
		MeshNodeMapEntry(
			date: date,
			meta: WidgetMapStore.loadMeta(),
			dataGeneratedAt: WidgetSnapshotStore.load()?.generatedAt,
			isPreview: isPreview
		)
	}
}

// MARK: - Widget

struct MeshNodeMapWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "MeshNodeMap", provider: MeshNodeMapProvider()) { entry in
			MeshNodeMapWidgetView(entry: entry)
				.containerBackground(Color(UIColor.systemBackground), for: .widget)
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
	@Environment(\.colorScheme) private var colorScheme
	let entry: MeshNodeMapEntry

	var body: some View {
		if let meta = entry.meta, let image = mapImage {
			ZStack(alignment: .bottomLeading) {
				// Color.clear contains the scaled image to the widget's own
				// bounds — scaledToFill alone can blow up the layout in the
				// gallery's preview pass.
				Color.clear
					.overlay(fullColorImage(image).opacity(entry.isStale ? 0.55 : 1))
				// The footer is the age cue, so the stale dim spares it.
				MapFooter(meta: meta, dataGeneratedAt: entry.dataGeneratedAt, compact: family == .systemSmall)
					.padding(6)
			}
			.clipped()
		} else if entry.isPreview, let sample = UIImage(named: "widget-map-preview") {
			// Any preview that cannot load a real image — no group access, no
			// render yet, a family's file missing — shows the bundled sample,
			// like the other widgets' canned preview data.
			Color.clear
				.overlay(fullColorImage(sample))
				.clipped()
		} else if entry.meta?.nodeCount == 0 {
			PlaceholderView(
				icon: "mappin.slash",
				text: "No node positions yet"
			)
		} else {
			PlaceholderView(
				icon: "map",
				text: "Open Meshtastic to render the map"
			)
		}
	}

	/// Keep the map full color on tinted home screens — a desaturated map
	/// with flattened chips tells the user nothing.
	@ViewBuilder
	private func fullColorImage(_ image: UIImage) -> some View {
		let base = Image(uiImage: image).resizable()
		if #available(iOS 18.0, *) {
			base.widgetAccentedRenderingMode(.fullColor)
				.scaledToFill()
		} else {
			base.scaledToFill()
		}
	}

	/// The widget process decodes a single pre-rendered PNG and nothing else.
	/// Medium has its own wide render; cropping the square cut off pins.
	private var mapImage: UIImage? {
		WidgetMapStore.loadImageData(dark: colorScheme == .dark, wide: family == .systemMedium)
			.flatMap(UIImage.init(data:))
	}
}

private struct PlaceholderView: View {
	let icon: String
	let text: LocalizedStringKey

	var body: some View {
		VStack(spacing: 6) {
			Image(systemName: icon)
				.font(.title2)
				.foregroundStyle(.secondary)
				.widgetAccentable()
			Text(text)
				.font(.caption2)
				.multilineTextAlignment(.center)
				.foregroundStyle(.secondary)
		}
		.padding(12)
	}
}

private struct MapFooter: View {
	let meta: WidgetMapMeta
	let dataGeneratedAt: Date?
	let compact: Bool

	var body: some View {
		HStack(spacing: 4) {
			MeshLogo(height: 9)
			// "on map" and not "nodes": the image shows the snapshot's capped,
			// positioned sample, not the mesh.
			if compact {
				Text("\(ageDate, style: .relative) ago")
			} else {
				Text("\(meta.nodeCount) on map · \(ageDate, style: .relative) ago")
			}
		}
		.font(.caption2)
		.foregroundStyle(.secondary)
		.lineLimit(1)
		.padding(.horizontal, 7)
		.padding(.vertical, 3)
		.background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.thinMaterial))
	}

	private var ageDate: Date {
		dataGeneratedAt ?? meta.generatedAt
	}
}
