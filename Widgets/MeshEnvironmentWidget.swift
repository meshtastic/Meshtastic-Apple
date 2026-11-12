//
//  MeshEnvironmentWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
//  One node's environment readings as node details' tiles (meshtastic/design#179).
//  Small shows the first two readings, medium the first three, large four at a time
//  with a page button when more are picked; on Vision Pro the extra large
//  board shows all eight. It reads the snapshot the app writes and never sends anything
//  over the mesh.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct EnvironmentEntry: TimelineEntry {
	let date: Date
	/// The configured node's names, even when it is not in the snapshot.
	let configured: EnvironmentNodeEntity?
	/// The node's current data, nil when it dropped out of the snapshot.
	let node: NodeSnapshot?
	/// The readings to show, in order.
	let metrics: [EnvironmentMetric]
	/// The large size's page.
	let page: Int

	var environment: EnvironmentSnapshot? { node?.environment }

	var isStale: Bool { environment?.isStale(at: date) ?? false }

	var pageCount: Int { EnvironmentWidgetPage.pageCount(for: metrics.count) }
}

struct EnvironmentProvider: AppIntentTimelineProvider {
	func placeholder(in context: Context) -> EnvironmentEntry {
		entry(for: EnvironmentWidgetIntent(), at: .now, snapshot: .environmentPreview)
	}

	func snapshot(for configuration: EnvironmentWidgetIntent, in context: Context) async -> EnvironmentEntry {
		var snapshot = WidgetSnapshotStore.load()
		if context.isPreview, EnvironmentNodeQuery.environmentNodes(in: snapshot).isEmpty {
			snapshot = .environmentPreview
		}
		return entry(for: configuration, at: .now, snapshot: snapshot)
	}

	func timeline(for configuration: EnvironmentWidgetIntent, in context: Context) async -> Timeline<EnvironmentEntry> {
		let now = Date()
		let snapshot = WidgetSnapshotStore.load()
		let first = entry(for: configuration, at: now, snapshot: snapshot)
		// The second entry lands when the reading turns two hours old, so it dims
		// on time; once that has passed it only sets the reload cadence.
		var secondDate = now.addingTimeInterval(2 * 3600)
		if let time = first.environment?.time {
			let staleDate = time.addingTimeInterval(2 * 3600)
			if staleDate > now {
				secondDate = staleDate
			}
		}
		return Timeline(entries: [first, entry(for: configuration, at: secondDate, snapshot: snapshot)], policy: .atEnd)
	}

	private func entry(for configuration: EnvironmentWidgetIntent, at date: Date, snapshot: WidgetSnapshot?) -> EnvironmentEntry {
		// Unconfigured: the connected radio when it reports environment readings,
		// otherwise the first node that does — the picker's default.
		let configured = configuration.node
			?? EnvironmentNodeQuery.environmentNodes(in: snapshot).first.map(EnvironmentNodeEntity.init)
		let node = snapshot?.nodes.first { String($0.num) == configured?.id }
		let picked = (configuration.metrics ?? []).map(\.metric)
		let metrics = picked.isEmpty ? EnvironmentMetric.defaults(for: node?.environment) : Array(picked.prefix(EnvironmentMetric.maximumCount))
		let pageCount = EnvironmentWidgetPage.pageCount(for: metrics.count)
		let page = configured?.nodeNum.map { EnvironmentWidgetPage.page(for: $0, pageCount: pageCount) } ?? 0
		return EnvironmentEntry(date: date, configured: configured, node: node, metrics: metrics, page: page)
	}
}

// MARK: - Widget

struct MeshEnvironmentWidget: Widget {
	var body: some WidgetConfiguration {
		AppIntentConfiguration(kind: EnvironmentWidgetPage.kind, intent: EnvironmentWidgetIntent.self, provider: EnvironmentProvider()) { entry in
			EnvironmentWidgetFamilyReader(entry: entry)
				.containerBackground(Color(UIColor.systemBackground), for: .widget)
				.widgetURL(entry.configured?.nodeNum.flatMap { URL(string: "meshtastic:///nodes?nodenum=\($0)&metrics=environment") }
					?? URL(string: "meshtastic:///nodes"))
		}
		.configurationDisplayName("Environment")
		.description("Environment, air quality and power readings from a node you pick.")
		// The view sets its own margins, so the large size can space its tiles from the edges.
		.contentMarginsDisabled()
		#if os(visionOS)
		// On a wall it can stand off it or sit in it like a weather panel, and the
		// board size has room for every reading at once.
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
		.supportedMountingStyles([.elevated, .recessed])
		#else
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
		#endif
	}
}

// MARK: - Views

/// Hands the widget's size to the view, which takes it as a value so it can
/// also be drawn outside a widget.
private struct EnvironmentWidgetFamilyReader: View {
	@Environment(\.widgetFamily) private var family
	let entry: EnvironmentEntry

	var body: some View {
		EnvironmentWidgetView(entry: entry, family: family)
	}
}

struct EnvironmentWidgetView: View {
	/// The widget's margin, in place of the system's, which the widget turns off.
	static let margin: CGFloat = 16

	let entry: EnvironmentEntry
	let family: WidgetFamily

	var body: some View {
		if let configured = entry.configured {
			VStack(alignment: .leading, spacing: 8) {
				if showsDetail {
					EnvironmentHeader(configured: configured)
						.padding(.horizontal, Self.margin)
				}
				if let environment = entry.environment, !entry.metrics.isEmpty {
					tiles(environment)
						// The large size spaces its tiles from the edges itself.
						.padding(.horizontal, family == .systemLarge ? 0 : Self.margin)
						.opacity(entry.isStale ? 0.55 : 1)
					if showsDetail {
						EnvironmentFooter(entry: entry, showsPageButton: family == .systemLarge)
							.padding(.horizontal, Self.margin)
					}
				} else {
					Spacer(minLength: 0)
					Text(entry.node == nil ? "Not in recent nodes" : "No environment readings from this node")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
						.padding(.horizontal, Self.margin)
					Spacer(minLength: 0)
				}
			}
			.padding(.vertical, Self.margin)
		} else {
			VStack(spacing: 6) {
				Image(systemName: "thermometer.sun")
					.font(.title2)
					.foregroundStyle(.secondary)
					.widgetAccentable()
				Text("No nodes have reported environment readings yet")
					.font(.caption2)
					.multilineTextAlignment(.center)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.padding(Self.margin)
		}
	}

	@ViewBuilder
	private func tiles(_ environment: EnvironmentSnapshot) -> some View {
		switch family {
		case .systemSmall:
			grid(Array(entry.metrics.prefix(2)), columns: 2, environment: environment)
		case .systemMedium:
			grid(Array(entry.metrics.prefix(3)), columns: 3, environment: environment)
		#if os(visionOS)
		case .systemExtraLarge:
			grid(Array(entry.metrics.prefix(EnvironmentMetric.maximumCount)), columns: 4, environment: environment)
		#endif
		default:
			// Pages keep two rows, so a short last page keeps its tiles' size.
			grid(EnvironmentWidgetPage.metrics(entry.metrics, page: entry.page), columns: 2, rows: 2, evenEdges: true, environment: environment)
		}
	}

	/// Rows of `columns` square tiles, as large as the widget allows and centered.
	/// With `rows`, empty slots are kept so the tiles stay the size of a full page.
	/// With `evenEdges`, the space from the widget's side edges to the tiles is the
	/// same as the space between them; the caller leaves the grid no side margin.
	private func grid(_ metrics: [EnvironmentMetric], columns: Int, rows: Int? = nil, evenEdges: Bool = false, environment: EnvironmentSnapshot) -> some View {
		let rowCount = rows ?? max(1, (metrics.count + columns - 1) / columns)
		return VStack(spacing: 8) {
			ForEach(0..<rowCount, id: \.self) { row in
				HStack(spacing: evenEdges ? 0 : 8) {
					ForEach(0..<columns, id: \.self) { column in
						if evenEdges {
							Spacer(minLength: 0)
						}
						let index = row * columns + column
						if index < metrics.count {
							FittedTile {
								EnvironmentCompactTile(metric: metrics[index], environment: environment)
							}
						} else if rows != nil {
							Color.clear
								.aspectRatio(1, contentMode: .fit)
						}
					}
					if evenEdges {
						Spacer(minLength: 0)
					}
				}
			}
		}
		.frame(maxWidth: .infinity)
	}

	/// Seen from across the room on Vision Pro, the widget keeps the readings
	/// and drops the header and footer.
	private var showsDetail: Bool {
		#if os(visionOS)
		levelOfDetail != .simplified
		#else
		true
		#endif
	}

	#if os(visionOS)
	@Environment(\.levelOfDetail) private var levelOfDetail
	#endif
}

/// Lays a tile out at a fixed size, then scales it to its square slot, so the
/// widget's tiles keep node details' layout rather than reflowing smaller.
private struct FittedTile<Content: View>: View {
	/// Smaller than a tile on node details (about 165 points), so the reading
	/// fills more of the widget's smaller squares.
	private static var layoutSize: CGFloat { 125 }

	@ViewBuilder let content: Content

	var body: some View {
		GeometryReader { geometry in
			let size = geometry.size
			let scale = max(0.1, min(size.width, size.height) / Self.layoutSize)
			content
				.frame(width: size.width / scale, height: size.height / scale)
				.scaleEffect(scale)
				.frame(width: size.width, height: size.height)
		}
		.aspectRatio(1, contentMode: .fit)
	}
}

private struct EnvironmentHeader: View {
	let configured: EnvironmentNodeEntity

	var body: some View {
		HStack(spacing: 6) {
			NodeChip(shortName: configured.shortName, colorSeed: UInt32(truncatingIfNeeded: configured.nodeNum ?? 0), size: 24)
			Text(configured.longName)
				.font(.caption.weight(.semibold))
				.lineLimit(1)
				.minimumScaleFactor(0.7)
			Spacer(minLength: 4)
			MeshLogo(height: 11)
		}
	}
}

private struct EnvironmentFooter: View {
	let entry: EnvironmentEntry
	let showsPageButton: Bool

	var body: some View {
		HStack(spacing: 6) {
			if let time = entry.environment?.time {
				Group {
					if entry.isStale {
						Text("Over 2 hours old · \(time, style: .relative) ago")
					} else {
						Text("Updated \(time, style: .relative) ago")
					}
				}
				.font(.caption2)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.7)
			}
			Spacer(minLength: 4)
			if showsPageButton, entry.pageCount > 1, let nodeNum = entry.configured?.nodeNum {
				Button(intent: EnvironmentPageIntent(nodeNum: nodeNum, pageCount: entry.pageCount)) {
					HStack(spacing: 3) {
						Text("\(entry.page + 1)/\(entry.pageCount)")
							.monospacedDigit()
						Image(systemName: "chevron.right")
					}
					.font(.caption2.weight(.semibold))
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.background(.fill.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Next readings, page \(entry.page + 1) of \(entry.pageCount)")
			}
		}
	}
}

// MARK: Preview data

extension WidgetSnapshot {
	/// Gallery and placeholder content — never written to the store.
	static var environmentPreview: WidgetSnapshot {
		var node = NodeSnapshot(
			num: 0x43B2A1,
			longName: "Greenhouse",
			shortName: "GRN",
			colorSeed: 0x43B2A1,
			batteryLevel: 92,
			snr: 8,
			rssi: -80,
			signalRating: 3,
			lastHeard: Date(timeIntervalSinceNow: -300),
			isOnline: true,
			hopsAway: 1,
			latitude: nil,
			longitude: nil,
			isFavorite: true
		)
		node.environment = EnvironmentSnapshot(
			time: Date(timeIntervalSinceNow: -300),
			temperature: 22.4,
			relativeHumidity: 61,
			barometricPressure: 1016.2,
			iaq: 42,
			soilTemperature: 18.1,
			soilMoisture: 37
		)
		return WidgetSnapshot(
			generatedAt: Date(timeIntervalSinceNow: -120),
			connectionState: .connected,
			radioNodeNum: 0x67EA94,
			radioLongName: "Meshtastic 5fac",
			radioShortName: "5fac",
			radioBatteryLevel: 87,
			localStats: nil,
			nodes: [node],
			totalNodeCount: 87,
			unreadChannelMessages: 0,
			unreadDirectMessages: 0,
			recentMessages: []
		)
	}
}
