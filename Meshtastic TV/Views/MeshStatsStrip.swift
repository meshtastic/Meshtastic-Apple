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
	/// Event firmware on the connected radio, or nil for a stock radio.
	var edition: EventEdition?

	@ScaledMetric(relativeTo: .caption2)
	private var metadataHeight: CGFloat = TVTheme.statsStripMetadataHeight

	var body: some View {
		HStack(spacing: TVTheme.statsStripColumnSpacing) {
			if let edition {
				eventBadge(edition)
					.frame(idealWidth: TVTheme.statsStripEventWidth, maxWidth: TVTheme.statsStripEventWidth)
					// Claim the column before the flexible packets cell does; without
					// this the badge is what gets compressed, clipping the name.
					.layoutPriority(1)
				divider
			}

			cell(
				label: "Nodes",
				value: nodesText,
				accessibilityLabel: "Nodes online",
				accessibilityValue: nodesAccessibilityValue
			)
				.frame(idealWidth: TVTheme.statsStripNodesWidth, maxWidth: TVTheme.statsStripNodesWidth)

			divider
			cell(
				label: "Ch Util",
				value: percentText(stats?.channelUtilization),
				color: channelUtilColor,
				severity: channelUtilSeverity,
				accessibilityLabel: "Channel utilization"
			)
				.frame(idealWidth: TVTheme.statsStripUtilizationWidth, maxWidth: TVTheme.statsStripUtilizationWidth)

			divider
			cell(
				label: "Air TX",
				value: percentText(stats?.airUtilTx),
				color: airTxColor,
				severity: airTxSeverity,
				accessibilityLabel: "Airtime transmit"
			)
				.frame(idealWidth: TVTheme.statsStripUtilizationWidth, maxWidth: TVTheme.statsStripUtilizationWidth)

			divider
			packetsCell
				.frame(maxWidth: .infinity, alignment: .leading)
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

	/// Event firmware badge: edition artwork beside the edition name. Editions with
	/// no bundled artwork fall back to the Meshtastic mark — the mark is supplemented,
	/// never replaced. Display-only, like the rest of the strip.
	private func eventBadge(_ edition: EventEdition) -> some View {
		HStack(spacing: TVTheme.statsStripPacketSpacing) {
			Image(edition.assetName ?? "m-logo-white")
				.resizable()
				.scaledToFit()
				.frame(width: TVTheme.statsStripEventLogoSize, height: TVTheme.statsStripEventLogoSize)
			VStack(alignment: .leading, spacing: TVTheme.statsStripMetricSpacing) {
				metricLabel("Event")
				Text(edition.name)
					.font(.title3.weight(.semibold))
					.lineLimit(1)
					.minimumScaleFactor(0.6)
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel(Text("Event firmware: \(edition.name)"))
	}

	/// `severity` conveys a warning without relying on colour alone: the glyph rides
	/// beside the LABEL, where the column has slack, rather than beside the value,
	/// where it would push these fixed-width columns back into truncation. VoiceOver
	/// reads it from the accessibility value instead of the glyph.
	private func cell(
		label: LocalizedStringKey,
		value: String,
		color: Color = .primary,
		severity: LocalizedStringKey? = nil,
		accessibilityLabel: LocalizedStringKey? = nil,
		accessibilityValue: Text? = nil
	) -> some View {
		VStack(alignment: .leading, spacing: TVTheme.statsStripMetricSpacing) {
			HStack(spacing: 8) {
				metricLabel(label)
				if severity != nil {
					Image(systemName: "exclamationmark.triangle.fill")
						.font(.caption.weight(.semibold))
						.foregroundStyle(color)
						.accessibilityHidden(true)
				}
			}
			metricValue(value, color: color)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityLabel ?? label)
		.accessibilityValue(accessibilityValue ?? severityValue(value, severity))
	}

	/// "7.5%" on its own, or "7.5%, Congested" when a severity applies.
	private func severityValue(_ value: String, _ severity: LocalizedStringKey?) -> Text {
		guard let severity else { return Text(verbatim: value) }
		return Text(verbatim: value) + Text(verbatim: ", ") + Text(severity)
	}

	private var packetsCell: some View {
		VStack(alignment: .leading, spacing: TVTheme.statsStripMetricSpacing) {
			metricLabel("Packets")
			packetCounts
			packetMetadata
				.font(.caption2.weight(.medium).monospacedDigit())
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.6)
				.frame(height: metadataHeight)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Packets")
		.accessibilityValue(packetsAccessibilityValue)
	}

	@ViewBuilder
	private var packetCounts: some View {
		if let tx = stats?.packetsTx, let rx = stats?.packetsRx {
			HStack(spacing: TVTheme.statsStripPacketSpacing) {
				packetCount(tx, arrow: "↑")
				packetCount(rx, arrow: "↓")
			}
		} else {
			metricValue("—", font: packetFont)
		}
	}

	/// Grouped digits normally; compact ("457K", "1.2M") past six figures, where
	/// the counters outgrow the column no matter how much they are scaled down.
	private func packetText(_ value: UInt32, fractionDigits: Int = 1) -> String {
		value >= 100_000
			? value.formatted(.number.notation(.compactName).precision(.fractionLength(fractionDigits)))
			: value.formatted()
	}

	private func packetCount(_ value: UInt32, arrow: String) -> some View {
		Text("\(packetText(value)) \(arrow)")
			.font(packetFont.weight(.semibold).monospacedDigit())
			.lineLimit(1)
			.minimumScaleFactor(0.6)
			.frame(maxWidth: .infinity, alignment: .leading)
	}

	/// One concatenated Text, not an HStack of several: separate Texts each get
	/// their own width and the longest clips, so the scale factor never applies to
	/// the line as a whole ("457K dup…").
	@ViewBuilder
	private var packetMetadata: some View {
		if let stats {
			dupesText(stats) + Text("Updated ") + Text(stats.receivedAt, style: .relative)
		} else {
			Text("Updated —")
				.hidden()
		}
	}

	private func dupesText(_ stats: MeshClient.ConnectedNodeStats) -> Text {
		guard let dupes = stats.packetsRxDupe else { return Text(verbatim: "") }
		return Text("\(packetText(dupes, fractionDigits: 0)) dupes") + Text(verbatim: " · ")
	}

	private func metricLabel(_ text: LocalizedStringKey) -> some View {
		Text(text)
			.font(.caption.weight(.medium))
			.tracking(1.2)
			.textCase(.uppercase)
			.foregroundStyle(Color.gray)
			.lineLimit(1)
			.minimumScaleFactor(0.8)
			.accessibilityHidden(true)
	}

	/// Value type steps down when the event badge is present — the badge takes a
	/// column's worth of width, and at `.title` the remaining metrics hit their
	/// scale floor and truncate ("761 /…") instead of shrinking.
	private var valueFont: Font { edition == nil ? .title : .title2 }
	private var packetFont: Font { edition == nil ? .title2 : .title3 }

	private func metricValue(_ text: String, color: Color = .primary, font: Font? = nil) -> some View {
		Text(text)
			.font((font ?? valueFont).weight(.semibold).monospacedDigit())
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

	private var nodesAccessibilityValue: Text {
		if let online = stats?.onlineNodes, let total = stats?.totalNodes {
			return Text("\(Int(online)) of \(Int(total)) online")
		}
		return Text("\(storeOnlineCount) of \(storeTotalCount) online")
	}

	private var packetsAccessibilityValue: Text {
		guard let tx = stats?.packetsTx, let rx = stats?.packetsRx else { return Text("No data") }
		var value = Text("\(tx.formatted()) transmitted, \(rx.formatted()) received")
		if let dupes = stats?.packetsRxDupe {
			value = value + Text(verbatim: ", ") + Text("\(dupes.formatted()) duplicates")
		}
		return value
	}

	private var channelUtilSeverity: LocalizedStringKey? {
		guard let value = stats?.channelUtilization else { return nil }
		if value >= 50 { return "Severely congested" }
		if value >= 25 { return "Congested" }
		return nil
	}

	/// 10% is the duty-cycle ceiling in most regions.
	private var airTxSeverity: LocalizedStringKey? {
		guard let value = stats?.airUtilTx, value >= 10 else { return nil }
		return "At duty-cycle limit"
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

#Preview("Event firmware", traits: .fixedLayout(width: 1560, height: 300)) {
	ZStack {
		Color.gray
		MeshStatsStrip(
			stats: MeshClient.ConnectedNodeStats(
				channelUtilization: 12.5,
				airUtilTx: 3.1,
				packetsTx: 8_402,
				packetsRx: 30_115,
				packetsRxDupe: nil,
				onlineNodes: 64,
				totalNodes: 210,
				receivedAt: Date().addingTimeInterval(-20)
			),
			storeOnlineCount: 60,
			storeTotalCount: 200,
			edition: EventEdition(.defcon)
		)
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
