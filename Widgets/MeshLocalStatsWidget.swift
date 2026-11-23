//
//  MeshLocalStatsWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  The mesh status widget: the connected radio's local stats at a glance.
//  Reads the shared WidgetSnapshot; the app decides when to reload. The
//  systemSmall family also appears in StandBy and (iOS 26) CarPlay, so the
//  background stays removable and the content stays glanceable.
//

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct MeshStatusEntry: TimelineEntry {
	let date: Date
	let snapshot: WidgetSnapshot?
	/// The small size's readings, in order, as set in Edit Widget.
	var readings: [MeshStatusReading] = MeshStatusReading.standard

	/// Staleness is the snapshot's age at the entry's own date — never the
	/// entry's position in a timeline. A position-based flag reset on every
	/// .atEnd reload, re-presenting hours-old data as fresh.
	var isStale: Bool {
		guard let snapshot else { return false }
		return date.timeIntervalSince(snapshot.generatedAt) >= 2 * 3600
	}
}

struct MeshStatusProvider: AppIntentTimelineProvider {
	func placeholder(in context: Context) -> MeshStatusEntry {
		MeshStatusEntry(date: .now, snapshot: .widgetPreview)
	}

	func snapshot(for configuration: MeshStatusWidgetIntent, in context: Context) async -> MeshStatusEntry {
		let snapshot = context.isPreview ? (WidgetSnapshotStore.load() ?? .widgetPreview) : WidgetSnapshotStore.load()
		return MeshStatusEntry(date: .now, snapshot: snapshot, readings: configuration.readings)
	}

	func timeline(for configuration: MeshStatusWidgetIntent, in context: Context) async -> Timeline<MeshStatusEntry> {
		let snapshot = WidgetSnapshotStore.load()
		let now = Date()
		// The stale flip belongs two hours after the snapshot was generated, not
		// two hours after this reload — an already-old snapshot must not read
		// fresh for longer. Once that moment has passed (or there is no snapshot)
		// the tail entry only sets the .atEnd reload cadence.
		var secondDate = now.addingTimeInterval(2 * 3600)
		if let generatedAt = snapshot?.generatedAt {
			let staleDate = generatedAt.addingTimeInterval(2 * 3600)
			if staleDate > now {
				secondDate = staleDate
			}
		}
		let entries = [
			MeshStatusEntry(date: now, snapshot: snapshot, readings: configuration.readings),
			MeshStatusEntry(date: secondDate, snapshot: snapshot, readings: configuration.readings)
		]
		return Timeline(entries: entries, policy: .atEnd)
	}
}

// MARK: - Widget

struct MeshLocalStatsWidget: Widget {
	var body: some WidgetConfiguration {
		AppIntentConfiguration(kind: "MeshLocalStats", intent: MeshStatusWidgetIntent.self, provider: MeshStatusProvider()) { entry in
			MeshStatusWidgetView(entry: entry)
				.containerBackground(Color(UIColor.systemBackground), for: .widget)
				.widgetURL(URL(string: "meshtastic:///connect"))
		}
		.configurationDisplayName("Mesh Status")
		.description("Connection, nodes online and your radio's local stats.")
		// The Lock Screen sizes don't exist on Vision Pro.
		#if os(iOS)
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
		#else
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
		#endif
	}
}

// MARK: - Views

struct MeshStatusWidgetView: View {
	@Environment(\.widgetFamily) private var family
	let entry: MeshStatusEntry

	var body: some View {
		if let snapshot = entry.snapshot {
			content(snapshot)
				// Snapshot data older than the stale tail entry reads as history,
				// not live state.
				.opacity(entry.isStale ? 0.55 : 1)
		} else {
			noDataView
		}
	}

	@ViewBuilder
	private func content(_ snapshot: WidgetSnapshot) -> some View {
		switch family {
		#if os(iOS)
		case .accessoryInline:
			InlineView(snapshot: snapshot)
		case .accessoryCircular:
			CircularView(snapshot: snapshot)
		case .accessoryRectangular:
			RectangularView(snapshot: snapshot)
		#endif
		case .systemMedium:
			MediumView(snapshot: snapshot)
		case .systemLarge:
			LargeView(snapshot: snapshot)
		default:
			SmallView(snapshot: snapshot, readings: entry.readings)
		}
	}

	@ViewBuilder
	private var noDataView: some View {
		switch family {
		#if os(iOS)
		case .accessoryInline:
			Text("Open Meshtastic")
		case .accessoryCircular:
			// Two lines of caption text clip in the ~58pt circle; the icon alone reads.
			Image(systemName: "antenna.radiowaves.left.and.right.slash")
				.font(.title2)
				.widgetAccentable()
				.accessibilityLabel("Open Meshtastic to load mesh data")
		#endif
		default:
			VStack(spacing: 6) {
				Image(systemName: "antenna.radiowaves.left.and.right.slash")
					.font(.title2)
					.foregroundStyle(.secondary)
					.widgetAccentable()
				Text("Open Meshtastic to load mesh data")
					.font(.caption2)
					.multilineTextAlignment(.center)
					.foregroundStyle(.secondary)
			}
		}
	}
}

// MARK: System families

private struct SmallView: View {
	let snapshot: WidgetSnapshot
	let readings: [MeshStatusReading]

	// Two columns of short readings under the radio's name, so the square is
	// used top to bottom. Which readings, and their order, are set in Edit Widget.
	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			HStack(spacing: 6) {
				MeshLogo(height: 13)
				NodeChip(shortName: snapshot.radioShortName ?? "?", colorSeed: UInt32(truncatingIfNeeded: snapshot.radioNodeNum ?? 0), size: 26)
				Spacer(minLength: 2)
				// The footer says when it isn't connected.
				ConnectionDot(state: snapshot.connectionState, showsLabel: false)
			}
			if let name = snapshot.radioLongName {
				// Two lines rather than cutting a long name short.
				Text(name)
					.font(.caption.weight(.semibold))
					.lineLimit(2)
					.minimumScaleFactor(0.8)
					.fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: 2)
			// The chosen readings, two to a row; ones the radio hasn't reported are skipped.
			let shown = Array(readings.uniqued().filter { hasValue($0) }.prefix(6))
			Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
				ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { start in
					GridRow {
						ForEach(shown[start..<min(start + 2, shown.count)], id: \.self) { reading in
							cell(reading)
						}
					}
				}
			}
			UpdatedFooter(snapshot: snapshot)
		}
	}

	private func hasValue(_ reading: MeshStatusReading) -> Bool {
		switch reading {
		case .nodes, .unreadMessages: true
		case .battery: snapshot.radioBatteryLevel != nil
		case .uptime: snapshot.localStats?.uptimeSeconds != nil
		default: snapshot.localStats != nil
		}
	}

	@ViewBuilder
	private func cell(_ reading: MeshStatusReading) -> some View {
		let stats = snapshot.localStats
		switch reading {
		case .nodes:
			SmallStat(systemImage: "dot.radiowaves.left.and.right", value: nodesText(snapshot))
		case .battery:
			BatteryRow(level: snapshot.radioBatteryLevel, font: .caption.weight(.semibold), showsPoweredText: false)
		case .channelUtilization:
			SmallStat(label: "ChUtil", value: percentText(stats?.channelUtilization))
		case .airtime:
			SmallStat(label: "Air", value: percentText(stats?.airUtilTx))
		case .unreadMessages:
			SmallStat(systemImage: "bubble.left", value: "\(snapshot.unreadChannelMessages + snapshot.unreadDirectMessages)")
		case .uptime:
			SmallStat(systemImage: "clock.arrow.circlepath", value: stats?.uptimeSeconds.map(uptimeText(seconds:)) ?? "--")
		case .packetsSent:
			SmallStat(systemImage: "arrow.up", value: compactCount(stats?.packetsSent))
		case .packetsReceived:
			SmallStat(systemImage: "arrow.down", value: compactCount(stats?.packetsReceived))
		case .packetsRelayed:
			SmallStat(systemImage: "arrow.triangle.2.circlepath", value: compactCount(stats?.packetsRelayed))
		case .duplicates:
			SmallStat(systemImage: "square.on.square", value: compactCount(stats?.packetsReceivedDupe))
		}
	}
}

/// One short reading for the small widget: an icon or a short label, then the value.
private struct SmallStat: View {
	var systemImage: String?
	var label: LocalizedStringKey?
	let value: String

	var body: some View {
		HStack(spacing: 3) {
			if let systemImage {
				Image(systemName: systemImage)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.widgetAccentable()
			}
			if let label {
				Text(label)
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			Text(value)
				.font(.caption.weight(.semibold))
				.monospacedDigit()
		}
		.lineLimit(1)
		.fixedSize()
	}
}

private struct MediumView: View {
	let snapshot: WidgetSnapshot

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HeaderRow(snapshot: snapshot)
			if let stats = snapshot.localStats {
				HStack(spacing: 16) {
					UtilizationGauge(title: "ChUtil", value: stats.channelUtilization)
					UtilizationGauge(title: "Airtime", value: stats.airUtilTx)
					VStack(alignment: .leading, spacing: 3) {
						StatLine(label: "Sent", value: countText(stats.packetsSent))
						StatLine(label: "Received", value: countText(stats.packetsReceived))
						StatLine(label: "Duplicates", value: countText(stats.packetsReceivedDupe))
					}
				}
			} else {
				Text("No local stats yet")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 0)
			BottomBar(snapshot: snapshot)
		}
	}
}

private struct LargeView: View {
	let snapshot: WidgetSnapshot

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HeaderRow(snapshot: snapshot)
			if let stats = snapshot.localStats {
				HStack(spacing: 20) {
					UtilizationGauge(title: "ChUtil", value: stats.channelUtilization)
					UtilizationGauge(title: "Airtime", value: stats.airUtilTx)
					VStack(alignment: .leading, spacing: 4) {
						Label("\(nodesText(snapshot)) nodes", systemImage: "dot.radiowaves.left.and.right")
							.font(.callout.weight(.semibold))
							.widgetAccentable()
						if let uptime = stats.uptimeSeconds {
							Text("Up \(uptimeText(seconds: uptime))")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
					Spacer(minLength: 0)
				}
				Divider()
				// The full Android local-stats set, two labeled columns. The rows
				// spread over the height left, so the widget has no empty gap
				// above the footer.
				HStack(alignment: .top, spacing: 20) {
					VStack(spacing: 0) {
						StatLine(label: "Sent", value: countText(stats.packetsSent), font: .subheadline)
						Spacer(minLength: 6)
						StatLine(label: "Received", value: countText(stats.packetsReceived), font: .subheadline)
						Spacer(minLength: 6)
						StatLine(label: "Error Rate", value: errorRateText(stats), font: .subheadline)
						Spacer(minLength: 6)
						StatLine(label: "Duplicates", value: countText(stats.packetsReceivedDupe), font: .subheadline)
					}
					VStack(spacing: 0) {
						StatLine(label: "Relayed", value: countText(stats.packetsRelayed), font: .subheadline)
						Spacer(minLength: 6)
						StatLine(label: "Relay Canceled", value: countText(stats.packetsRelayCanceled), font: .subheadline)
						Spacer(minLength: 6)
						StatLine(label: "Bad Received", value: countText(stats.packetsReceivedBad), font: .subheadline)
						Spacer(minLength: 6)
						StatLine(label: "Nodes Online", value: nodesText(snapshot), font: .subheadline)
					}
				}
				.frame(maxHeight: .infinity)
				Divider()
			} else {
				Text("No local stats yet — they arrive about every 15 minutes while connected.")
					.font(.caption)
					.foregroundStyle(.secondary)
				Label("\(nodesText(snapshot)) nodes", systemImage: "dot.radiowaves.left.and.right")
					.font(.callout.weight(.semibold))
				Spacer(minLength: 0)
			}
			BottomBar(snapshot: snapshot)
		}
	}
}

/// One labeled stat: full words, grouped digits, never wrapped.
private struct StatLine: View {
	let label: LocalizedStringKey
	let value: String
	var font: Font = .caption

	var body: some View {
		HStack(spacing: 6) {
			Text(label)
				.foregroundStyle(.secondary)
			Spacer(minLength: 4)
			Text(value)
				.fontWeight(.semibold)
				.monospacedDigit()
		}
		.font(font)
		.lineLimit(1)
		.minimumScaleFactor(0.7)
	}
}

/// Footer: freshness on the left, battery bottom right.
private struct BottomBar: View {
	let snapshot: WidgetSnapshot

	var body: some View {
		HStack {
			UpdatedFooter(snapshot: snapshot)
			Spacer()
			BatteryRow(level: snapshot.radioBatteryLevel, font: .caption)
		}
	}
}

private func countText(_ value: Int32) -> String {
	Int(value).formatted(.number)
}

private func errorRateText(_ stats: LocalStatsSnapshot) -> String {
	let rate = stats.packetsReceived > 0
		? Double(stats.packetsReceivedBad) / Double(stats.packetsReceived)
		: 0
	return rate.formatted(.percent.precision(.fractionLength(1)))
}

// MARK: Accessory families

private struct InlineView: View {
	let snapshot: WidgetSnapshot

	var body: some View {
		if snapshot.connectionState == .connected {
			Text("\(nodesText(snapshot)) nodes\(batterySuffix)")
		} else {
			Text("Mesh \(stateText(snapshot.connectionState))")
		}
	}

	private var batterySuffix: String {
		guard let level = snapshot.radioBatteryLevel else { return "" }
		return level > 100 ? " · ⚡︎" : " · \(level)%"
	}
}

private struct CircularView: View {
	@Environment(\.isLuminanceReduced) private var isLuminanceReduced
	let snapshot: WidgetSnapshot

	var body: some View {
		if let stats = snapshot.localStats, snapshot.connectionState == .connected {
			Gauge(value: Double(stats.nodesOnline), in: 0...Double(max(stats.nodesTotal, 1))) {
				MeshLogo(height: 8)
			} currentValueLabel: {
				VStack(spacing: -2) {
					Text("\(stats.nodesOnline)")
						.font(.headline)
					Text("nodes")
						.font(.system(size: 8, weight: .semibold))
						.foregroundStyle(.secondary)
				}
			}
			.gaugeStyle(.accessoryCircular)
			.opacity(isLuminanceReduced ? 0.6 : 1)
			.widgetAccentable()
		} else {
			VStack(spacing: 2) {
				Image(systemName: snapshot.connectionState == .connected
					? "antenna.radiowaves.left.and.right"
					: "antenna.radiowaves.left.and.right.slash")
					.font(.title3)
					.widgetAccentable()
				Text(snapshot.radioShortName ?? "?")
					.font(.caption2)
					.lineLimit(1)
			}
		}
	}
}

private struct RectangularView: View {
	let snapshot: WidgetSnapshot

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			HStack(spacing: 4) {
				MeshLogo(height: 9)
				Text(snapshot.radioLongName ?? "Meshtastic")
					.font(.headline)
					.lineLimit(1)
			}
			.widgetAccentable()
			HStack(spacing: 6) {
				Text("\(nodesText(snapshot)) nodes")
				if let level = snapshot.radioBatteryLevel {
					Text(level > 100 ? "Powered" : "\(level)%")
				}
			}
			.font(.caption)
			if snapshot.connectionState == .connected {
				if let util = snapshot.localStats?.channelUtilization {
					Text("ChUtil \(util, specifier: "%.1f")%")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			} else {
				Text(stateText(snapshot.connectionState))
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}
}

// MARK: Shared pieces

private struct HeaderRow: View {
	let snapshot: WidgetSnapshot

	// Battery lives in the bottom bar; the header keeps the room so the
	// radio's name shows whole, scaling down before it ever truncates.
	var body: some View {
		HStack(spacing: 8) {
			MeshLogo(height: 13)
			NodeChip(shortName: snapshot.radioShortName ?? "?", colorSeed: UInt32(truncatingIfNeeded: snapshot.radioNodeNum ?? 0), size: 26)
			Text(snapshot.radioLongName ?? "Meshtastic")
				.font(.headline)
				.lineLimit(1)
				.minimumScaleFactor(0.6)
				.layoutPriority(1)
			Spacer()
			ConnectionDot(state: snapshot.connectionState)
		}
	}
}

private struct UtilizationGauge: View {
	let title: String
	let value: Float?

	var body: some View {
		VStack(spacing: 2) {
			Gauge(value: Double(min(max(value ?? 0, 0), 100)), in: 0...100) {
				Text(title)
			} currentValueLabel: {
				// nil means the radio did not report this measurement — showing
				// 0% would claim a reading that never arrived.
				Text(value.map { String(format: "%.0f%%", $0) } ?? "--")
					.font(.caption2)
			}
			.gaugeStyle(.accessoryCircularCapacity)
			.widgetAccentable()
			Text(title)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
	}
}

private struct UpdatedFooter: View {
	let snapshot: WidgetSnapshot

	// Live age text can't sit in a ViewThatFits (the widget draws black), so the
	// wording is picked up front: with the state in front there's no room for "Updated".
	var body: some View {
		HStack(spacing: 3) {
			if snapshot.connectionState != .connected {
				Text(stateText(snapshot.connectionState))
				Text("·")
				ageText(snapshot.generatedAt)
			} else {
				Text("Updated \(ageText(snapshot.generatedAt))")
			}
		}
		.font(.caption2)
		.foregroundStyle(.secondary)
		.lineLimit(1)
		.minimumScaleFactor(0.8)
	}
}

// MARK: Helpers

private func nodesText(_ snapshot: WidgetSnapshot) -> String {
	// Without stats there is no online count — `nodes` is a capped sample, so
	// only the real database total is honest.
	guard let stats = snapshot.localStats else {
		return "\(snapshot.totalNodeCount)"
	}
	return "\(stats.nodesOnline)/\(stats.nodesTotal)"
}

private extension Array where Element: Hashable {
	/// The elements in order, each once: a reading picked twice shows once.
	func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}

/// A packet count short enough for half the small widget's width: 8.4K, 1.2M.
private func compactCount(_ value: Int32?) -> String {
	guard let value else { return "--" }
	return Int(value).formatted(.number.notation(.compactName))
}

/// nil means the radio did not report it; 0% would claim a reading that never arrived.
private func percentText(_ value: Float?) -> String {
	value.map { String(format: "%.0f%%", $0) } ?? "--"
}

private func uptimeText(seconds: Int32) -> String {
	let days = seconds / 86_400
	let hours = (seconds % 86_400) / 3_600
	let minutes = (seconds % 3_600) / 60
	if days > 0 { return "\(days)d \(hours)h" }
	if hours > 0 { return "\(hours)h \(minutes)m" }
	return "\(minutes)m"
}

// MARK: Preview data

extension WidgetSnapshot {
	/// Gallery and placeholder content — never written to the store.
	static var widgetPreview: WidgetSnapshot {
		WidgetSnapshot(
			generatedAt: Date(timeIntervalSinceNow: -120),
			connectionState: .connected,
			radioNodeNum: 0x67EA94,
			radioLongName: "Meshtastic 5fac",
			radioShortName: "5fac",
			radioBatteryLevel: 87,
			localStats: LocalStatsSnapshot(
				statsAt: Date(timeIntervalSinceNow: -300),
				uptimeSeconds: 93_600,
				channelUtilization: 12.4,
				airUtilTx: 3.1,
				packetsSent: 1_284,
				packetsReceived: 8_412,
				packetsReceivedBad: 12,
				packetsReceivedDupe: 96,
				packetsRelayed: 412,
				packetsRelayCanceled: 18,
				nodesOnline: 23,
				nodesTotal: 87
			),
			nodes: [],
			totalNodeCount: 87,
			unreadChannelMessages: 2,
			unreadDirectMessages: 1,
			recentMessages: []
		)
	}
}
