//
//  MeshEnvironmentWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
//  One node's environment readings as node details' tiles (meshtastic/design#179).
//  Small shows the first two readings, medium the first three, large four at a time
//  with a page button when more are picked; the extra large portrait size (iOS
//  27 and Vision Pro) fits up to six and pages beyond that, and Vision Pro's
//  extra large board shows all eight. It reads the snapshot the app writes and never sends anything
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
	/// The page as stored; each paging size wraps it to its own page count.
	let storedPage: Int

	var environment: EnvironmentSnapshot? { node?.environment }

	var isStale: Bool { environment?.isStale(at: date) ?? false }

	func pageCount(pageSize: Int) -> Int {
		EnvironmentWidgetPage.pageCount(for: metrics.count, pageSize: pageSize)
	}

	func page(pageSize: Int) -> Int {
		EnvironmentWidgetPage.wrap(storedPage, pageCount: pageCount(pageSize: pageSize))
	}
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
		let storedPage = configured?.nodeNum.map(EnvironmentWidgetPage.storedPage(for:)) ?? 0
		return EnvironmentEntry(date: date, configured: configured, node: node, metrics: metrics, storedPage: storedPage)
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
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .systemExtraLargePortrait])
		.supportedMountingStyles([.elevated, .recessed])
		#else
		.supportedFamilies(Self.families)
		#endif
	}

	#if !os(visionOS)
	/// The extra large portrait size arrived on iPhone in iOS 27.
	private static var families: [WidgetFamily] {
		var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
		if #available(iOS 27.0, *) {
			families.append(.systemExtraLargePortrait)
		}
		return families
	}
	#endif
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
						.padding(.horizontal, usesEvenEdges ? 0 : Self.margin)
					if showsDetail {
						EnvironmentFooter(entry: entry, page: page, pageCount: pageCount)
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
		if isExtraLargePortrait {
			if pageCount > 1 {
				// Pages keep three rows, so the last page's tiles stay the size of the first's.
				grid(EnvironmentWidgetPage.metrics(entry.metrics, page: page, pageSize: pageSize), columns: 2, rows: 3, evenEdges: true, environment: environment)
			} else {
				bestFitGrid(entry.metrics, environment: environment)
			}
		} else {
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
				if pageCount > 1 {
					// Pages keep two rows, so a short last page keeps its tiles' size.
					grid(EnvironmentWidgetPage.metrics(entry.metrics, page: page, pageSize: pageSize), columns: 2, rows: 2, evenEdges: true, environment: environment)
				} else {
					bestFitGrid(entry.metrics, environment: environment)
				}
			}
		}
	}

	/// The tall size on iOS 27 and Vision Pro, with room for every reading.
	private var isExtraLargePortrait: Bool {
		if #available(iOS 27.0, visionOS 26.0, *) {
			return family == .systemExtraLargePortrait
		}
		return false
	}

	/// Readings on one page of this size.
	private var pageSize: Int {
		isExtraLargePortrait ? EnvironmentWidgetPage.extraLargePortraitPageSize : EnvironmentWidgetPage.pageSize
	}

	/// Pages for the sizes that page: large, and extra large portrait with more than six readings.
	private var pageCount: Int {
		usesEvenEdges ? entry.pageCount(pageSize: pageSize) : 1
	}

	private var page: Int {
		entry.page(pageSize: pageSize)
	}

	/// The sizes whose tiles are spaced from the widget's side edges by the grid itself.
	private var usesEvenEdges: Bool {
		family == .systemLarge || isExtraLargePortrait
	}

	/// Rows of `columns` square tiles, as large as the widget allows and centered.
	/// With `rows`, empty slots are kept so the tiles stay the size of a full page.
	/// With `evenEdges`, the spaces from the widget's side edges to the tiles and
	/// between them are all equal; the caller leaves the grid no side margin.
	@ViewBuilder
	private func grid(_ metrics: [EnvironmentMetric], columns: Int, rows: Int? = nil, evenEdges: Bool = false, environment: EnvironmentSnapshot) -> some View {
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
								cell(metrics, index: row * columns + column, environment: environment)
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
								cell(metrics, index: index, environment: environment)
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
	private func bestFitGrid(_ metrics: [EnvironmentMetric], environment: EnvironmentSnapshot) -> some View {
		GeometryReader { geometry in
			let size = geometry.size
			let spacing: CGFloat = 8
			let fit = EnvironmentWidgetPage.bestFit(count: metrics.count, in: size, spacing: spacing)
			let gap = (size.width - fit.side * CGFloat(fit.columns)) / CGFloat(fit.columns + 1)
			VStack(spacing: spacing) {
				ForEach(0..<fit.rows, id: \.self) { row in
					HStack(spacing: gap) {
						ForEach(0..<fit.columns, id: \.self) { column in
							let index = row * fit.columns + column
							if index < metrics.count {
								EnvironmentCompactTile(metric: metrics[index], environment: environment)
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
	private func cell(_ metrics: [EnvironmentMetric], index: Int, environment: EnvironmentSnapshot) -> some View {
		if index < metrics.count {
			EnvironmentCompactTile(metric: metrics[index], environment: environment)
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
	/// The page shown, and how many there are; one page shows no button.
	let page: Int
	let pageCount: Int

	var body: some View {
		HStack(spacing: 6) {
			if let time = entry.environment?.time {
				// An old reading isn't dimmed, which made the tiles hard to read; the line
				// turns orange and says so instead.
				Group {
					if entry.isStale {
						Label("Over 2 hours old · \(time, style: .relative) ago", systemImage: "clock.badge.exclamationmark")
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
				Button(intent: EnvironmentPageIntent(nodeNum: nodeNum, pageCount: pageCount)) {
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
