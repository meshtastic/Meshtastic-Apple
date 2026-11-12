//
//  MeshTelemetryWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
//  One node's telemetry as node details' tiles (meshtastic/design#179): every
//  reading it reports, less any the person hides. Small shows the first, medium
//  the first four, large four at a time with a page button when there are more;
//  extra large portrait (iOS 27 and Vision Pro) fits up to six and pages beyond
//  that, and Vision Pro's extra large board shows eight at a time. It reads the
//  snapshot the app writes and never sends anything over the mesh.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct TelemetryEntry: TimelineEntry {
	let date: Date
	/// The configured node's names, even when it is not in the snapshot.
	let configured: TelemetryNodeEntity?
	/// The node's current data, nil when it dropped out of the snapshot.
	let node: NodeSnapshot?
	/// The readings to show, in order.
	let metrics: [TelemetryMetric]
	/// The page as stored; each paging size wraps it to its own page count.
	let storedPage: Int

	var telemetry: TelemetrySnapshot? { node?.telemetry }

	var isStale: Bool { telemetry?.isStale(at: date) ?? false }

	func pageCount(pageSize: Int) -> Int {
		TelemetryWidgetPage.pageCount(for: metrics.count, pageSize: pageSize)
	}

	func page(pageSize: Int) -> Int {
		TelemetryWidgetPage.wrap(storedPage, pageCount: pageCount(pageSize: pageSize))
	}
}

struct TelemetryProvider: AppIntentTimelineProvider {
	func placeholder(in context: Context) -> TelemetryEntry {
		entry(for: TelemetryWidgetIntent(), at: .now, snapshot: .telemetryPreview)
	}

	func snapshot(for configuration: TelemetryWidgetIntent, in context: Context) async -> TelemetryEntry {
		var snapshot = WidgetSnapshotStore.load()
		if context.isPreview, TelemetryNodeQuery.telemetryNodes(in: snapshot).isEmpty {
			snapshot = .telemetryPreview
		}
		return entry(for: configuration, at: .now, snapshot: snapshot)
	}

	func timeline(for configuration: TelemetryWidgetIntent, in context: Context) async -> Timeline<TelemetryEntry> {
		let now = Date()
		let snapshot = WidgetSnapshotStore.load()
		let first = entry(for: configuration, at: now, snapshot: snapshot)
		// The second entry lands when the reading turns two hours old, so it dims
		// on time; once that has passed it only sets the reload cadence.
		var secondDate = now.addingTimeInterval(2 * 3600)
		if let time = first.telemetry?.time {
			let staleDate = time.addingTimeInterval(2 * 3600)
			if staleDate > now {
				secondDate = staleDate
			}
		}
		return Timeline(entries: [first, entry(for: configuration, at: secondDate, snapshot: snapshot)], policy: .atEnd)
	}

	private func entry(for configuration: TelemetryWidgetIntent, at date: Date, snapshot: WidgetSnapshot?) -> TelemetryEntry {
		// Unconfigured: the connected radio when it reports environment readings,
		// otherwise the first node that does — the picker's default.
		let configured = configuration.node
			?? TelemetryNodeQuery.telemetryNodes(in: snapshot).first.map(TelemetryNodeEntity.init)
		let node = snapshot?.nodes.first { String($0.num) == configured?.id }
		let metrics = TelemetryMetric.shown(in: node?.telemetry, hiding: (configuration.hidden ?? []).map(\.metric))
		let storedPage = configured?.nodeNum.map(TelemetryWidgetPage.storedPage(for:)) ?? 0
		return TelemetryEntry(date: date, configured: configured, node: node, metrics: metrics, storedPage: storedPage)
	}
}

// MARK: - Widget

struct MeshTelemetryWidget: Widget {
	var body: some WidgetConfiguration {
		AppIntentConfiguration(kind: TelemetryWidgetPage.kind, intent: TelemetryWidgetIntent.self, provider: TelemetryProvider()) { entry in
			TelemetryWidgetFamilyReader(entry: entry)
				.containerBackground(Color(UIColor.systemBackground), for: .widget)
				.widgetURL(entry.configured?.nodeNum.flatMap { URL(string: "meshtastic:///nodes?nodenum=\($0)&metrics=environment") }
					?? URL(string: "meshtastic:///nodes"))
		}
		.configurationDisplayName("Telemetry")
		.description("Environment, air quality and power readings from a node you pick.")
		// The view sets its own margins, so the large size can space its tiles from the edges.
		.contentMarginsDisabled()
		#if os(visionOS)
		// On a wall it can stand off it or sit in it like a weather panel, and the
		// board size has room for every reading at once.
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .systemExtraLargePortrait])
		.supportedMountingStyles([.elevated, .recessed])
		#else
		.supportedFamilies(Self.families)
		#endif
	}

	#if !os(visionOS)
	/// The extra large portrait size arrived on iPhone in iOS 27.
	private static var families: [WidgetFamily] {
		WidgetFamily.addingExtraLargePortrait(to: [.systemSmall, .systemMedium, .systemLarge])
	}
	#endif
}

// MARK: - Views

/// Hands the widget's size to the view, which takes it as a value so it can
/// also be drawn outside a widget.
private struct TelemetryWidgetFamilyReader: View {
	@Environment(\.widgetFamily) private var family
	let entry: TelemetryEntry

	var body: some View {
		TelemetryWidgetView(entry: entry, family: family)
	}
}

struct TelemetryWidgetView: View {
	/// The widget's margin, in place of the system's, which the widget turns off.
	static let margin: CGFloat = 16

	let entry: TelemetryEntry
	let family: WidgetFamily

	var body: some View {
		if let configured = entry.configured {
			VStack(alignment: .leading, spacing: 8) {
				if showsDetail {
					TelemetryHeader(configured: configured)
						.padding(.horizontal, Self.margin)
				}
				if let telemetry = entry.telemetry, !entry.metrics.isEmpty {
					tiles(telemetry)
						// The large size spaces its tiles from the edges itself.
						.padding(.horizontal, usesEvenEdges ? 0 : Self.margin)
					if showsDetail {
						TelemetryFooter(entry: entry, page: page, pageCount: pageCount)
							.padding(.horizontal, Self.margin)
					}
				} else {
					Spacer(minLength: 0)
					Text(entry.node == nil ? "Not in recent nodes" : "No telemetry from this node")
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
				Text("No nodes have reported telemetry yet")
					.font(.caption2)
					.multilineTextAlignment(.center)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.padding(Self.margin)
		}
	}

	@ViewBuilder
	private func tiles(_ telemetry: TelemetrySnapshot) -> some View {
		if isExtraLargePortrait {
			if pageCount > 1 {
				// Pages keep three rows, so the last page's tiles stay the size of the first's.
				grid(TelemetryWidgetPage.metrics(entry.metrics, page: page, pageSize: pageSize), columns: 2, rows: 3, evenEdges: true, telemetry: telemetry)
			} else {
				bestFitGrid(entry.metrics, telemetry: telemetry)
			}
		} else {
			switch family {
			case .systemSmall:
				grid(Array(entry.metrics.prefix(1)), columns: 1, telemetry: telemetry)
			case .systemMedium:
				bestFitGrid(Array(entry.metrics.prefix(4)), telemetry: telemetry)
			#if os(visionOS)
			case .systemExtraLarge:
				grid(TelemetryWidgetPage.metrics(entry.metrics, page: page, pageSize: pageSize), columns: 4, telemetry: telemetry)
			#endif
			default:
				if pageCount > 1 {
					// Pages keep two rows, so a short last page keeps its tiles' size.
					grid(TelemetryWidgetPage.metrics(entry.metrics, page: page, pageSize: pageSize), columns: 2, rows: 2, evenEdges: true, telemetry: telemetry)
				} else {
					bestFitGrid(entry.metrics, telemetry: telemetry)
				}
			}
		}
	}

	/// The tall size on iOS 27 and Vision Pro, with room for every reading.
	private var isExtraLargePortrait: Bool {
		family.isExtraLargePortrait
	}

	/// Readings on one page of this size.
	private var pageSize: Int {
		if isExtraLargePortrait { return TelemetryWidgetPage.extraLargePortraitPageSize }
		if isExtraLarge { return TelemetryWidgetPage.extraLargePageSize }
		return TelemetryWidgetPage.pageSize
	}

	/// Vision Pro's board size.
	private var isExtraLarge: Bool {
		#if os(visionOS)
		family == .systemExtraLarge
		#else
		false
		#endif
	}

	/// Pages for the sizes that page: large, and extra large portrait with more than six readings.
	private var pageCount: Int {
		family == .systemLarge || isExtraLargePortrait || isExtraLarge ? entry.pageCount(pageSize: pageSize) : 1
	}

	private var page: Int {
		entry.page(pageSize: pageSize)
	}

	/// The sizes whose tiles are spaced from the widget's side edges by the grid itself.
	private var usesEvenEdges: Bool {
		family == .systemMedium || family == .systemLarge || isExtraLargePortrait
	}

	/// Rows of `columns` square tiles, as large as the widget allows and centered.
	/// With `rows`, empty slots are kept so the tiles stay the size of a full page.
	/// With `evenEdges`, the spaces from the widget's side edges to the tiles and
	/// between them are all equal; the caller leaves the grid no side margin.
	@ViewBuilder
	private func grid(_ metrics: [TelemetryMetric], columns: Int, rows: Int? = nil, evenEdges: Bool = false, telemetry: TelemetrySnapshot) -> some View {
		let rowCount = rows ?? max(1, (metrics.count + columns - 1) / columns)
		let spacing: CGFloat = 8
		if evenEdges {
			GeometryReader { geometry in
				let size = geometry.size
				let side = max(0, min(
					(size.height - spacing * CGFloat(rowCount - 1)) / CGFloat(rowCount),
					(size.width - spacing * CGFloat(columns + 1)) / CGFloat(columns)
				))
				let gap = (size.width - side * CGFloat(columns)) / CGFloat(columns + 1)
				VStack(spacing: spacing) {
					ForEach(0..<rowCount, id: \.self) { row in
						HStack(spacing: gap) {
							ForEach(0..<columns, id: \.self) { column in
								cell(metrics, index: row * columns + column, telemetry: telemetry)
									.frame(width: side, height: side)
							}
						}
					}
				}
				.frame(width: size.width, height: size.height)
			}
		} else {
			VStack(spacing: spacing) {
				ForEach(0..<rowCount, id: \.self) { row in
					HStack(spacing: spacing) {
						ForEach(0..<columns, id: \.self) { column in
							let index = row * columns + column
							if index < metrics.count || rows != nil {
								cell(metrics, index: index, telemetry: telemetry)
							}
						}
					}
				}
			}
			.frame(maxWidth: .infinity)
		}
	}

	/// The readings in whichever columns and rows make their tiles largest, spaced
	/// evenly from the side edges like the large size's pages.
	private func bestFitGrid(_ metrics: [TelemetryMetric], telemetry: TelemetrySnapshot) -> some View {
		GeometryReader { geometry in
			let size = geometry.size
			let spacing: CGFloat = 8
			let fit = TelemetryWidgetPage.bestFit(count: metrics.count, in: size, spacing: spacing)
			let gap = (size.width - fit.side * CGFloat(fit.columns)) / CGFloat(fit.columns + 1)
			VStack(spacing: spacing) {
				ForEach(0..<fit.rows, id: \.self) { row in
					HStack(spacing: gap) {
						ForEach(0..<fit.columns, id: \.self) { column in
							let index = row * fit.columns + column
							if index < metrics.count {
								TelemetryCompactTile(metric: metrics[index], telemetry: telemetry)
									.frame(width: fit.side, height: fit.side)
							}
						}
					}
				}
			}
			.frame(width: size.width, height: size.height)
		}
	}

	@ViewBuilder
	private func cell(_ metrics: [TelemetryMetric], index: Int, telemetry: TelemetrySnapshot) -> some View {
		if index < metrics.count {
			TelemetryCompactTile(metric: metrics[index], telemetry: telemetry)
		} else {
			Color.clear
				.aspectRatio(1, contentMode: .fit)
		}
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

private struct TelemetryHeader: View {
	let configured: TelemetryNodeEntity

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

private struct TelemetryFooter: View {
	let entry: TelemetryEntry
	/// The page shown, and how many there are; one page shows no button.
	let page: Int
	let pageCount: Int

	var body: some View {
		HStack(spacing: 6) {
			if let time = entry.telemetry?.time {
				// An old reading isn't dimmed, which made the tiles hard to read; the line
				// turns orange and says so instead.
				Group {
					if entry.isStale {
						Label("Over 2 hours old · \(time, style: .relative) ago", systemImage: "clock.badge.exclamationmark")
							.font(.system(size: 9))
							.foregroundStyle(.orange)
					} else {
						Text("Updated \(time, style: .relative) ago")
							.foregroundStyle(.secondary)
					}
				}
				.font(.caption2)
				.lineLimit(1)
				.minimumScaleFactor(0.7)
			}
			Spacer(minLength: 4)
			if pageCount > 1, let nodeNum = entry.configured?.nodeNum {
				Button(intent: TelemetryPageIntent(nodeNum: nodeNum, pageCount: pageCount)) {
					HStack(spacing: 3) {
						Text("\(page + 1)/\(pageCount)")
							.monospacedDigit()
						Image(systemName: "chevron.right")
					}
					.font(.caption2.weight(.semibold))
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.background(.fill.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Next readings, page \(page + 1) of \(pageCount)")
			}
		}
	}
}

// MARK: Preview data

extension WidgetSnapshot {
	/// Gallery and placeholder content — never written to the store.
	static var telemetryPreview: WidgetSnapshot {
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
		node.telemetry = TelemetrySnapshot(
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
