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
		return date.timeIntervalSince(snapshot.generatedAt) > 2 * 3600
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
		let entries = [
			MeshStatusEntry(date: now, snapshot: snapshot),
			MeshStatusEntry(date: now.addingTimeInterval(2 * 3600), snapshot: snapshot)
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
					VStack(alignment: .leading, spacing: 2) {
						TrafficLine(label: "TX", value: stats.packetsSent)
						TrafficLine(label: "RX", value: stats.packetsReceived)
						TrafficLine(label: "Dupe", value: stats.packetsReceivedDupe)
					}
					Spacer()
				}
			} else {
				Text("No local stats yet")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			UpdatedFooter(snapshot: snapshot)
		}
	}
}

private struct LargeView: View {
	let snapshot: WidgetSnapshot

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HeaderRow(snapshot: snapshot)
			if let stats = snapshot.localStats {
				HStack(spacing: 20) {
					UtilizationGauge(title: "ChUtil", value: stats.channelUtilization)
					UtilizationGauge(title: "Airtime", value: stats.airUtilTx)
					VStack(alignment: .leading, spacing: 2) {
						TrafficLine(label: "TX", value: stats.packetsSent)
						TrafficLine(label: "RX", value: stats.packetsReceived)
						TrafficLine(label: "Bad", value: stats.packetsReceivedBad)
						TrafficLine(label: "Dupe", value: stats.packetsReceivedDupe)
					}
					VStack(alignment: .leading, spacing: 2) {
						TrafficLine(label: "Relayed", value: stats.packetsRelayed)
						TrafficLine(label: "Canceled", value: stats.packetsRelayCanceled)
						if let uptime = stats.uptimeSeconds {
							Text("Up \(uptimeText(seconds: uptime))")
								.font(.caption2)
								.foregroundStyle(.secondary)
						}
					}
					Spacer()
				}
				Divider()
				HStack {
					Label(nodesText(snapshot), systemImage: "dot.radiowaves.left.and.right")
						.font(.callout.weight(.semibold))
						.widgetAccentable()
					Spacer()
					Text("Stats \(stats.statsAt, style: .relative) ago")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			} else {
				Text("No local stats yet — they arrive about every 15 minutes while connected.")
					.font(.caption)
					.foregroundStyle(.secondary)
				Label(nodesText(snapshot), systemImage: "dot.radiowaves.left.and.right")
					.font(.callout.weight(.semibold))
			}
			Spacer(minLength: 0)
			UpdatedFooter(snapshot: snapshot)
		}
	}
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

/// The Meshtastic mark, picked for the color scheme. The asset is about 2:1,
/// so it is sized by height.
private struct MeshLogo: View {
	@Environment(\.colorScheme) private var colorScheme
	let height: CGFloat

	var body: some View {
		Image(colorScheme == .dark ? "m-logo-white" : "m-logo-black")
			.resizable()
			.aspectRatio(contentMode: .fit)
			.frame(height: height)
	}
}

private struct HeaderRow: View {
	let snapshot: WidgetSnapshot

	var body: some View {
		HStack(spacing: 8) {
			MeshLogo(height: 13)
			NodeChip(shortName: snapshot.radioShortName ?? "?", colorSeed: UInt32(truncatingIfNeeded: snapshot.radioNodeNum ?? 0), size: 26)
			Text(snapshot.radioLongName ?? "Meshtastic")
				.font(.headline)
				.lineLimit(1)
			Spacer()
			BatteryRow(level: snapshot.radioBatteryLevel, font: .caption)
			ConnectionDot(state: snapshot.connectionState)
		}
	}
}

private struct ConnectionDot: View {
	let state: WidgetConnectionState

	var body: some View {
		HStack(spacing: 3) {
			Circle()
				.fill(state == .connected ? Color.green : (state == .connecting ? Color.orange : Color.secondary))
				.frame(width: 7, height: 7)
			if state != .connected {
				Text(stateText(state))
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
		.accessibilityLabel(stateText(state))
	}
}

private struct BatteryRow: View {
	let level: Int32?
	let font: Font

	var body: some View {
		if let level {
			HStack(spacing: 3) {
				// BatteryIcon crashes on nil in builds without the icon fix, so it
				// is only instantiated with a real value.
				BatteryIcon(batteryLevel: level, font: font, color: .accentColor)
					.widgetAccentable()
				Text(level > 100 ? "Powered" : "\(level)%")
					.font(font)
			}
		}
	}
}

private struct NodeChip: View {
	let shortName: String
	let colorSeed: UInt32
	let size: CGFloat

	// Accented rendering is left off: tinting flattens the opaque capsule and
	// its text to one alpha, leaving an unreadable solid pill.
	var body: some View {
		Text(shortName)
			.font(.system(size: size * 0.38, weight: .bold))
			.minimumScaleFactor(0.5)
			.lineLimit(1)
			.foregroundStyle(isLight ? Color.black : Color.white)
			.frame(width: size * 1.6, height: size)
			.background(Capsule().fill(Color(red: red, green: green, blue: blue)))
	}

	// Same derivation the app uses: the node number's low 24 bits as RRGGBB.
	private var red: Double { Double((colorSeed >> 16) & 0xFF) / 255 }
	private var green: Double { Double((colorSeed >> 8) & 0xFF) / 255 }
	private var blue: Double { Double(colorSeed & 0xFF) / 255 }

	// WCAG relative luminance, matching the app's Color.isLight(), so chip text
	// flips black/white at the same colors as in the app.
	private var isLight: Bool {
		func linearize(_ channel: Double) -> Double {
			channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
		}
		let luminance = 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
		return luminance > 0.179
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
				Text("\(value ?? 0, specifier: "%.0f")%")
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

private struct TrafficLine: View {
	let label: String
	let value: Int32

	var body: some View {
		HStack(spacing: 4) {
			Text(label)
				.foregroundStyle(.secondary)
			Text("\(value)")
				.fontWeight(.medium)
		}
		.font(.caption2)
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

private func stateText(_ state: WidgetConnectionState) -> String {
	switch state {
	case .connected: return "Connected"
	case .connecting: return "Connecting"
	case .disconnected: return "Disconnected"
	}
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
