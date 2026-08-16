//
//  MeshStatsStrip.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 8/14/26.
//
//  Compact mesh health strip over the map: nodes online/total, radio load, packet
//  counters. Toggle and top/bottom position live in Settings ("tv.statsBar.*").
//
//  DISPLAY-ONLY by hard rule: no Button, no NavigationLink, no .focusable(). Any
//  focus target right of the side list re-creates the focus trap documented in
//  MeshTVMapView (the map column must hold nothing the focus engine can land on).
//

import SwiftUI

/// Where the strip sits over the map. String raw values so @AppStorage stores it directly.
enum StatsStripEdge: String, CaseIterable {
	case top
	case bottom
}

struct MeshStatsStrip: View {
	/// Latest stats from the connected node, nil until telemetry arrives.
	let stats: MeshClient.ConnectedNodeStats?
	/// Store-derived fallbacks so the node count renders before any telemetry.
	let storeOnlineCount: Int
	let storeTotalCount: Int

	@ScaledMetric(relativeTo: .caption2)
	private var metadataHeight: CGFloat = TVTheme.statsStripMetadataHeight

	var body: some View {
		HStack(spacing: TVTheme.statsStripColumnSpacing) {
			cell(label: "Nodes", value: nodesText)
				.frame(idealWidth: TVTheme.statsStripNodesWidth, maxWidth: TVTheme.statsStripNodesWidth)

			divider
			cell(label: "Ch Util", value: percentText(stats?.channelUtilization), color: channelUtilColor)
				.frame(idealWidth: TVTheme.statsStripUtilizationWidth, maxWidth: TVTheme.statsStripUtilizationWidth)

			divider
			cell(label: "Air TX", value: percentText(stats?.airUtilTx), color: airTxColor)
				.frame(idealWidth: TVTheme.statsStripUtilizationWidth, maxWidth: TVTheme.statsStripUtilizationWidth)

			divider
			packetsCell
				.frame(idealWidth: TVTheme.statsStripPacketsWidth, maxWidth: .infinity)
		}
		.padding(.horizontal, TVTheme.statsStripHorizontalPadding)
		.padding(.vertical, TVTheme.statsStripVerticalPadding)
		.frame(maxWidth: .infinity)
		.background(
			RoundedRectangle(cornerRadius: TVTheme.statsStripCornerRadius, style: .continuous)
				.fill(.regularMaterial)
		)
		.clipShape(RoundedRectangle(cornerRadius: TVTheme.statsStripCornerRadius, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: TVTheme.statsStripCornerRadius, style: .continuous)
				.stroke(.white.opacity(0.15), lineWidth: 1)
		)
		.shadow(color: .black.opacity(0.4), radius: 18, y: 8)
	}

	// MARK: Cells

	private func cell(label: LocalizedStringKey, value: String, color: Color = .primary) -> some View {
		VStack(alignment: .leading, spacing: TVTheme.statsStripMetricSpacing) {
			metricLabel(label)
			metricValue(value, color: color)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var packetsCell: some View {
		VStack(alignment: .leading, spacing: TVTheme.statsStripMetricSpacing) {
			metricLabel("Packets")
			packetCounts
			packetMetadata
				.font(.caption2.weight(.medium).monospacedDigit())
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
				.frame(height: metadataHeight)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder
	private var packetCounts: some View {
		if let tx = stats?.packetsTx, let rx = stats?.packetsRx {
			HStack(spacing: TVTheme.statsStripPacketSpacing) {
				packetCount(tx, arrow: "↑")
				packetCount(rx, arrow: "↓")
			}
		} else {
			metricValue("—", font: .title2)
		}
	}

	private func packetCount(_ value: UInt32, arrow: String) -> some View {
		Text("\(value.formatted()) \(arrow)")
			.font(.title2.weight(.semibold).monospacedDigit())
			.lineLimit(1)
			.minimumScaleFactor(0.3)
			.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder
	private var packetMetadata: some View {
		if let stats {
			HStack(spacing: TVTheme.statsStripPacketSpacing) {
				if let dupes = stats.packetsRxDupe {
					Text("\(dupes.formatted()) dupes")
					Text("·")
				}
				Text("Updated")
				Text(stats.receivedAt, style: .relative)
			}
		} else {
			Text("Updated —")
				.hidden()
		}
	}

	private func metricLabel(_ text: LocalizedStringKey) -> some View {
		Text(text)
			.font(.caption.weight(.medium))
			.tracking(1.2)
			.textCase(.uppercase)
			.foregroundStyle(Color.gray)
			.lineLimit(1)
			.minimumScaleFactor(0.8)
	}

	private func metricValue(_ text: String, color: Color = .primary, font: Font = .title) -> some View {
		Text(text)
			.font(font.weight(.semibold).monospacedDigit())
			.foregroundStyle(color)
			.lineLimit(1)
			.minimumScaleFactor(0.5)
	}

	private var divider: some View {
		Rectangle()
			.fill(.secondary.opacity(0.4))
			.frame(width: TVTheme.statsStripDividerWidth, height: TVTheme.statsStripDividerHeight)
	}

	// MARK: Values

	/// The radio's own node-DB view when LocalStats has arrived (authoritative for the
	/// mesh), otherwise what this app has stored so far.
	private var nodesText: String {
		if let online = stats?.onlineNodes, let total = stats?.totalNodes {
			return "\(online) / \(total)"
		}
		return "\(storeOnlineCount) / \(storeTotalCount)"
	}

	private func percentText(_ value: Float?) -> String {
		guard let value else { return "—" }
		return String(format: "%.1f%%", value)
	}

	/// Firmware treats sustained channel utilization above 25% as a congested mesh.
	private var channelUtilColor: Color {
		guard let value = stats?.channelUtilization else { return .primary }
		if value >= 50 { return Color("MeshtasticError") }
		if value >= 25 { return Color("MeshtasticWarning") }
		return .primary
	}

	/// 10% is the duty-cycle ceiling in most regions.
	private var airTxColor: Color {
		guard let value = stats?.airUtilTx, value >= 10 else { return .primary }
		return Color("MeshtasticWarning")
	}
}

#Preview("All cells", traits: .fixedLayout(width: 1240, height: 300)) {
	ZStack {
		Color.gray
		MeshStatsStrip(
			stats: MeshClient.ConnectedNodeStats(
				channelUtilization: 31.4,
				airUtilTx: 4.2,
				packetsTx: 12_340,
				packetsRx: 48_102,
				packetsRxDupe: 512,
				onlineNodes: 38,
				totalNodes: 154,
				receivedAt: Date().addingTimeInterval(-95)
			),
			storeOnlineCount: 30,
			storeTotalCount: 140
		)
	}
}

#Preview("No telemetry yet", traits: .fixedLayout(width: 1240, height: 300)) {
	ZStack {
		Color.gray
		MeshStatsStrip(stats: nil, storeOnlineCount: 12, storeTotalCount: 40)
	}
}

#Preview("Maximum packet counters", traits: .fixedLayout(width: 1240, height: 300)) {
	ZStack {
		Color.gray
		MeshStatsStrip(
			stats: MeshClient.ConnectedNodeStats(
				channelUtilization: 99.9,
				airUtilTx: 10,
				packetsTx: .max,
				packetsRx: .max,
				packetsRxDupe: .max,
				onlineNodes: 9_999,
				totalNodes: 9_999,
				receivedAt: Date()
			),
			storeOnlineCount: 9_999,
			storeTotalCount: 9_999
		)
	}
}
