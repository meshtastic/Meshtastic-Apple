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

	/// Staleness is the snapshot's age at the entry's own date — never the
	/// entry's position in a timeline. A position-based flag reset on every
	/// .atEnd reload, re-presenting hours-old data as fresh.
	var isStale: Bool {
		guard let snapshot else { return false }
		return date.timeIntervalSince(snapshot.generatedAt) >= 2 * 3600
	}
}

struct MeshStatusProvider: TimelineProvider {
	func placeholder(in context: Context) -> MeshStatusEntry {
		MeshStatusEntry(date: .now, snapshot: .widgetPreview)
	}

	func getSnapshot(in context: Context, completion: @escaping (MeshStatusEntry) -> Void) {
		let snapshot = context.isPreview ? (WidgetSnapshotStore.load() ?? .widgetPreview) : WidgetSnapshotStore.load()
		completion(MeshStatusEntry(date: .now, snapshot: snapshot))
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<MeshStatusEntry>) -> Void) {
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
			MeshStatusEntry(date: now, snapshot: snapshot),
			MeshStatusEntry(date: secondDate, snapshot: snapshot)
		]
		completion(Timeline(entries: entries, policy: .atEnd))
	}
}

// MARK: - Widget

struct MeshLocalStatsWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "MeshLocalStats", provider: MeshStatusProvider()) { entry in
			MeshStatusWidgetView(entry: entry)
				.containerBackground(Color(UIColor.systemBackground), for: .widget)
				.widgetURL(URL(string: "meshtastic:///connect"))
		}
		.configurationDisplayName("Mesh Status")
		.description("Connection, nodes online and your radio's local stats.")
		.supportedFamilies([
			.systemSmall, .systemMedium, .systemLarge,
			.accessoryInline, .accessoryCircular, .accessoryRectangular
		])
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
		case .accessoryInline:
			InlineView(snapshot: snapshot)
		case .accessoryCircular:
			CircularView(snapshot: snapshot)
		case .accessoryRectangular:
			RectangularView(snapshot: snapshot)
		case .systemMedium:
			MediumView(snapshot: snapshot)
		case .systemLarge:
			LargeView(snapshot: snapshot)
		default:
			SmallView(snapshot: snapshot)
		}
	}

	@ViewBuilder
	private var noDataView: some View {
		switch family {
		case .accessoryInline:
			Text("Open Meshtastic")
		case .accessoryCircular:
			// Two lines of caption text clip in the ~58pt circle; the icon alone reads.
			Image(systemName: "antenna.radiowaves.left.and.right.slash")
				.font(.title2)
				.widgetAccentable()
				.accessibilityLabel("Open Meshtastic to load mesh data")
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

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 6) {
				MeshLogo(height: 13)
				NodeChip(shortName: snapshot.radioShortName ?? "?", colorSeed: UInt32(truncatingIfNeeded: snapshot.radioNodeNum ?? 0), size: 28)
				Spacer()
				ConnectionDot(state: snapshot.connectionState)
			}
			Spacer(minLength: 2)
			BatteryRow(level: snapshot.radioBatteryLevel, font: .callout)
			HStack(spacing: 4) {
				Image(systemName: "dot.radiowaves.left.and.right")
					.font(.caption2)
					.widgetAccentable()
				Text(nodesText(snapshot))
					.font(.callout.weight(.semibold))
			}
			UpdatedFooter(snapshot: snapshot)
		}
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
				// The full Android local-stats set, two labeled columns.
				HStack(alignment: .top, spacing: 20) {
					VStack(spacing: 7) {
						StatLine(label: "Sent", value: countText(stats.packetsSent))
						StatLine(label: "Received", value: countText(stats.packetsReceived))
						StatLine(label: "Error Rate", value: errorRateText(stats))
						StatLine(label: "Duplicates", value: countText(stats.packetsReceivedDupe))
					}
					VStack(spacing: 7) {
						StatLine(label: "Relayed", value: countText(stats.packetsRelayed))
						StatLine(label: "Relay Canceled", value: countText(stats.packetsRelayCanceled))
						StatLine(label: "Bad Received", value: countText(stats.packetsReceivedBad))
						StatLine(label: "Nodes Online", value: nodesText(snapshot))
					}
				}
			} else {
				Text("No local stats yet — they arrive about every 15 minutes while connected.")
					.font(.caption)
					.foregroundStyle(.secondary)
				Label("\(nodesText(snapshot)) nodes", systemImage: "dot.radiowaves.left.and.right")
					.font(.callout.weight(.semibold))
			}
			Spacer(minLength: 0)
			BottomBar(snapshot: snapshot)
		}
	}
}

/// One labeled stat: full words, grouped digits, never wrapped.
private struct StatLine: View {
	let label: LocalizedStringKey
	let value: String

	var body: some View {
		HStack(spacing: 6) {
			Text(label)
				.foregroundStyle(.secondary)
			Spacer(minLength: 4)
			Text(value)
				.fontWeight(.semibold)
				.monospacedDigit()
		}
		.font(.caption)
		.lineLimit(1)
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

	var body: some View {
		HStack(spacing: 3) {
			if snapshot.connectionState != .connected {
				Text(stateText(snapshot.connectionState))
				Text("·")
			}
			Text("Updated \(snapshot.generatedAt, style: .relative) ago")
		}
		.font(.caption2)
		.foregroundStyle(.secondary)
		.lineLimit(1)
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
