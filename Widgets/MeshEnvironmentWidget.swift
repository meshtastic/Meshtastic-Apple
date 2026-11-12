//
//  MeshEnvironmentWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
//  One node's environment readings as tiles (meshtastic/design#179). Small
//  shows the first reading, medium the first two, large four at a time with a
//  page button when more are picked; on Vision Pro the extra large board shows
//  all eight. It reads the snapshot the app writes and never sends anything
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
		.description("Temperature, humidity and other readings from a node you pick.")
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
	let entry: EnvironmentEntry
	let family: WidgetFamily

	var body: some View {
		if let configured = entry.configured {
			VStack(alignment: .leading, spacing: 8) {
				if showsDetail {
					EnvironmentHeader(configured: configured)
				}
				if let environment = entry.environment, !entry.metrics.isEmpty {
					tiles(environment)
						.opacity(entry.isStale ? 0.55 : 1)
					if showsDetail {
						EnvironmentFooter(entry: entry, showsPageButton: family == .systemLarge)
					}
				} else {
					Spacer(minLength: 0)
					Text(entry.node == nil ? "Not in recent nodes" : "No environment readings from this node")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
					Spacer(minLength: 0)
				}
			}
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
		}
	}

	@ViewBuilder
	private func tiles(_ environment: EnvironmentSnapshot) -> some View {
		switch family {
		case .systemSmall:
			EnvironmentTile(metric: entry.metrics[0], environment: environment, size: .large)
		case .systemMedium:
			HStack(spacing: 8) {
				ForEach(entry.metrics.prefix(2)) { metric in
					EnvironmentTile(metric: metric, environment: environment, size: .large)
				}
			}
		#if os(visionOS)
		case .systemExtraLarge:
			grid(Array(entry.metrics.prefix(EnvironmentMetric.maximumCount)), columns: 4, environment: environment)
		#endif
		default:
			grid(EnvironmentWidgetPage.metrics(entry.metrics, page: entry.page), columns: 2, environment: environment)
		}
	}

	/// Rows of `columns` tiles. A short last page keeps its tiles the size of a
	/// full one, so flipping pages doesn't resize them.
	private func grid(_ metrics: [EnvironmentMetric], columns: Int, environment: EnvironmentSnapshot) -> some View {
		let rows = max(1, (metrics.count + columns - 1) / columns)
		let fullRows = family == .systemLarge ? 2 : rows
		return VStack(spacing: 8) {
			ForEach(0..<fullRows, id: \.self) { row in
				HStack(spacing: 8) {
					ForEach(0..<columns, id: \.self) { column in
						let index = row * columns + column
						if index < metrics.count {
							EnvironmentTile(metric: metrics[index], environment: environment, size: .medium)
						} else {
							Color.clear
						}
					}
				}
			}
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

/// One reading: its icon and name, then the value and unit. A reading the
/// node no longer reports shows a dash, never zero.
struct EnvironmentTile: View {
	enum Size {
		case medium
		case large
	}

	let metric: EnvironmentMetric
	let environment: EnvironmentSnapshot
	let size: Size

	var body: some View {
		let reading = metric.reading(in: environment)
		VStack(alignment: .leading, spacing: 2) {
			HStack(spacing: 4) {
				Image(systemName: metric.systemImage)
					.font(.caption2.weight(.semibold))
					.widgetAccentable()
				Text(metric.title)
					.textCase(.uppercase)
					.font(.system(size: 10, weight: .semibold))
					.lineLimit(1)
					.minimumScaleFactor(0.6)
			}
			.foregroundStyle(.secondary)
			Spacer(minLength: 0)
			HStack(alignment: .firstTextBaseline, spacing: 2) {
				Text(reading?.value ?? Constants.nilValueIndicator)
					.font(.system(size: size == .large ? 34 : 28, weight: .semibold, design: .rounded))
					.foregroundStyle(reading?.color ?? Color(uiColor: .label))
				if let unit = reading?.unit {
					Text(unit)
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
			}
			.lineLimit(1)
			.minimumScaleFactor(0.5)
			if let detail = reading?.detail {
				Text(detail)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.minimumScaleFactor(0.6)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.padding(8)
		.background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.accessibilityElement(children: .combine)
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
