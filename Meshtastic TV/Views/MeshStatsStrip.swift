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

	@ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 30
	@ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 64

	var body: some View {
		HStack(spacing: 56) {
			cell(label: "Nodes", value: nodesText)

			divider
			cell(label: "Ch Util", value: percentText(stats?.channelUtilization), color: channelUtilColor)

			divider
			cell(label: "Air TX", value: percentText(stats?.airUtilTx), color: airTxColor)

			divider
			cell(label: "Packets", value: packetsText)

			if let dupes = stats?.packetsRxDupe {
				divider
				cell(label: "Dupes", value: dupes.formatted())
			}

			if let receivedAt = stats?.receivedAt {
				divider
				VStack(alignment: .leading, spacing: 6) {
					Text("Updated")
						.font(.system(size: labelSize, weight: .medium))
						.tracking(1.2)
						.textCase(.uppercase)
						.foregroundStyle(Color.gray)
					Text(receivedAt, style: .relative)
						.font(.system(size: valueSize, weight: .semibold, design: .rounded).monospacedDigit())
				}
			}
		}
		.padding(.horizontal, 64)
		.padding(.vertical, 36)
		.background(
			RoundedRectangle(cornerRadius: 24, style: .continuous)
				.fill(.regularMaterial)
		)
		.overlay(
			RoundedRectangle(cornerRadius: 24, style: .continuous)
				.stroke(.white.opacity(0.15), lineWidth: 1)
		)
		.shadow(color: .black.opacity(0.4), radius: 18, y: 8)
		.fixedSize()
	}

	// MARK: Cells

	private func cell(label: String, value: String, color: Color = .primary) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(label)
				.font(.system(size: labelSize, weight: .medium))
				.tracking(1.2)
				.textCase(.uppercase)
				.foregroundStyle(Color.gray)
			Text(value)
				.font(.system(size: valueSize, weight: .semibold, design: .rounded).monospacedDigit())
				.foregroundStyle(color)
		}
	}

	private var divider: some View {
		Rectangle()
			.fill(.secondary.opacity(0.4))
			.frame(width: 1, height: 104)
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

	private var packetsText: String {
		guard let tx = stats?.packetsTx, let rx = stats?.packetsRx else { return "—" }
		return "\(tx.formatted()) ↑ · \(rx.formatted()) ↓"
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

#Preview("All cells", traits: .fixedLayout(width: 1400, height: 300)) {
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

#Preview("No telemetry yet", traits: .fixedLayout(width: 1400, height: 300)) {
	ZStack {
		Color.gray
		MeshStatsStrip(stats: nil, storeOnlineCount: 12, storeTotalCount: 40)
	}
}
