// MARK: DiscoverySummaryView
//
//  DiscoverySummaryView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import OSLog
import SwiftData
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

struct DiscoverySummaryView: View {
	let session: DiscoverySessionEntity

	@State private var aiSummary: String = ""
	@State private var isGeneratingAI: Bool = false
	@State private var generatingPresets: Set<String> = []
	@State private var presetSummaries: [String: String] = [:]

	var body: some View {
		List {
			sessionOverviewSection
			presetResultsSection
			rfHealthSection
			aiRecommendationSection
		}
		.listSectionSpacing(.compact)
		.navigationTitle("Scan Summary")
		.task {
			loadCachedPresetSummaries()
			await generateAIRecommendation()
			await generateFoundationModelPresetSummaries()
		}
	}

	// MARK: - Session Overview

	private var sessionOverviewSection: some View {
		Section(header: Text("Session Overview")) {
			LabeledContent("Date", value: session.timestamp.formatted(date: .abbreviated, time: .shortened))
			LabeledContent("Presets Scanned", value: session.presetsScanned.replacingOccurrences(of: ",", with: ", "))
			LabeledContent("Total Unique Nodes", value: "\(session.totalUniqueNodes)")
			LabeledContent("Text Messages", value: "\(session.totalTextMessages)")
			LabeledContent("Sensor Packets", value: "\(session.totalSensorPackets)")
			if session.furthestNodeDistance > 0 {
				LabeledContent("Furthest Node") {
					Text(formatDistance(session.furthestNodeDistance))
				}
			}
			if session.averageChannelUtilization > 0 {
				LabeledContent("Avg Channel Utilization") {
					Text(String(format: "%.1f%%", session.averageChannelUtilization))
				}
			}
			LabeledContent("Status") {
				statusBadge(session.completionStatus)
			}
		}
	}

	// MARK: - Per-Preset Results (FR-012)

	private var presetResultsSection: some View {
		Section(header: Text("Per-Preset Results")) {
			if session.presetResults.isEmpty {
				Text("No preset data available")
					.foregroundStyle(.secondary)
			} else {
				ForEach(session.presetResults, id: \.presetName) { result in
					presetCard(result)
				}
			}
		}
	}

	@ViewBuilder
	private func presetCard(_ result: DiscoveryPresetResultEntity) -> some View {
		let isMac = UIDevice.current.userInterfaceIdiom == .mac || UIDevice.current.userInterfaceIdiom == .pad
		let rowFont: Font = isMac ? .body : .caption
		let headerFont: Font = isMac ? .title3 : .headline
		let valueFont: Font = isMac ? .callout : .subheadline

		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(result.presetName)
					.font(headerFont)
				Spacer()
				VStack(alignment: .trailing) {
					Text("\(result.uniqueNodesFound) nodes")
						.font(valueFont)
						.foregroundStyle(result.uniqueNodesFound > 0 ? .green : .secondary)
					HStack(spacing: 4) {
						Image(systemName: "point.3.connected.trianglepath.dotted")
							.foregroundStyle(.purple)
						Text("\(result.meshNeighborCount) Mesh")
							.foregroundStyle(.secondary)
					}
					.font(rowFont)
				}
			}

			HStack(alignment: .top, spacing: 16) {
				VStack(alignment: .leading, spacing: 6) {
					HStack(spacing: 6) {
						Image(systemName: "antenna.radiowaves.left.and.right")
							.foregroundStyle(.blue)
						Text("Direct")
						Text("\(result.directNeighborCount)")
							.foregroundStyle(.primary)
					}
					HStack(spacing: 6) {
						Image(systemName: "bubble.left")
							.foregroundStyle(.blue)
						Text("Messages")
						Text("\(result.messageCount)")
							.foregroundStyle(.primary)
					}
					HStack(spacing: 6) {
						Image(systemName: "chart.bar.fill")
							.foregroundStyle(result.averageChannelUtilization < 25 ? .green : (result.averageChannelUtilization > 50 ? .red : .orange))
						Text("Ch Util")
						Text(result.averageChannelUtilization > 0 ? "\(String(format: "%.1f", result.averageChannelUtilization))%" : "—")
							.foregroundStyle(.primary)
					}
				}
				Spacer()
				VStack(alignment: .leading, spacing: 6) {
					HStack(spacing: 6) {
						Image(systemName: "server.rack")
							.foregroundStyle(.teal)
						Text("Infrastructure")
						Text("\(result.infrastructureNodeCount)")
							.foregroundStyle(.primary)
					}
					HStack(spacing: 6) {
						Image(systemName: "thermometer.medium")
							.foregroundStyle(.orange)
						Text("Sensor")
						Text("\(result.sensorPacketCount)")
							.foregroundStyle(.primary)
					}
					HStack(spacing: 6) {
						Image(systemName: "clock.arrow.circlepath")
							.foregroundStyle(result.averageAirtimeRate > 10 ? .red : (result.averageAirtimeRate > 5 ? .orange : .green))
						Text("Airtime")
						Text(result.averageAirtimeRate > 0 ? "\(String(format: "%.2f", result.averageAirtimeRate))%" : "—")
							.foregroundStyle(.primary)
					}
				}
			}
			.font(rowFont)
			.foregroundStyle(.secondary)

			// Per-preset AI summary for presets with more than 1 node
			if result.uniqueNodesFound > 1 {
				if generatingPresets.contains(result.presetName) {
					HStack(spacing: 6) {
						ProgressView()
							.controlSize(.small)
						Text("Analyzing...")
							.font(rowFont)
							.foregroundStyle(.secondary)
					}
				} else if let summary = presetSummaries[result.presetName], !summary.isEmpty {
					Text(summary)
						.font(rowFont)
						.foregroundStyle(.secondary)
						.padding(.top, 2)
				}
			}
		}
		.padding(.vertical, 4)
	}

	// MARK: - RF Health (T030)

	private var rfHealthSection: some View {
		Section(header: Text("RF Health")) {
			let hasRFData = session.presetResults.contains {
				$0.packetSuccessRate > 0 || $0.packetFailureRate > 0
				|| $0.numPacketsTx > 0 || $0.numPacketsRx > 0
				|| $0.averageChannelUtilization > 0 || $0.averageAirtimeRate > 0
			}
			if hasRFData {
				ForEach(session.presetResults.filter {
					$0.packetSuccessRate > 0 || $0.packetFailureRate > 0
					|| $0.numPacketsTx > 0 || $0.numPacketsRx > 0
					|| $0.averageChannelUtilization > 0 || $0.averageAirtimeRate > 0
				}, id: \.presetName) { result in
					rfHealthCard(result)
				}
			} else {
				Text("No LocalStats data collected")
					.foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private func rfHealthCard(_ result: DiscoveryPresetResultEntity) -> some View {
		let errorRate = result.numPacketsRx > 0
			? (Double(result.numPacketsRxBad) / Double(result.numPacketsRx)) * 100
			: 0.0

		VStack(alignment: .leading, spacing: 6) {
			Text(result.presetName)
				.font(.subheadline)
				.fontWeight(.medium)

			HStack(alignment: .top, spacing: 16) {
				// Left column
				VStack(alignment: .leading, spacing: 4) {
					Label(String(format: "%.1f%%", result.averageChannelUtilization), systemImage: "chart.bar.fill")
						.foregroundStyle(result.averageChannelUtilization < 25 ? .green : (result.averageChannelUtilization > 50 ? .red : .orange))
					Label(String(format: "%.1f%%", result.averageAirtimeRate), systemImage: "clock.arrow.circlepath")
						.foregroundStyle(result.averageAirtimeRate > 10 ? .red : (result.averageAirtimeRate > 5 ? .orange : .green))
					Label("\(result.numPacketsTx) sent", systemImage: "arrow.up.circle")
						.foregroundStyle(.blue)
					Label("\(result.numPacketsRx) received", systemImage: "arrow.down.circle")
						.foregroundStyle(.blue)
				}

				Spacer()

				// Right column
				VStack(alignment: .leading, spacing: 4) {
					Label(String(format: "%.1f%% errors", errorRate), systemImage: "xmark.circle")
						.foregroundStyle(errorRate > 10 ? .red : (errorRate > 5 ? .orange : .green))
					Label("\(result.numTxRelay) relayed", systemImage: "arrow.triangle.swap")
						.foregroundStyle(.purple)
					Label("\(result.numTxRelayCanceled) relay canceled", systemImage: "arrow.triangle.pull")
						.foregroundStyle(.orange)
					Label("\(result.numRxDupe) duplicate", systemImage: "doc.on.doc")
						.foregroundStyle(.secondary)
				}
			}
			.font(.caption)

			// Footer: nodes + uptime
			HStack(spacing: 8) {
				if result.numTotalNodes > 0 {
					Label("\(result.numOnlineNodes)/\(result.numTotalNodes) nodes online", systemImage: "person.2")
						.foregroundStyle(.secondary)
				}
				Spacer()
				if result.uptimeSeconds > 0 {
					Label(uptimeString(result.uptimeSeconds), systemImage: "clock")
						.foregroundStyle(.secondary)
				}
			}
			.font(.caption2)
		}
		.padding(.vertical, 2)
	}

	private func uptimeString(_ seconds: Int) -> String {
		if seconds >= 3600 {
			return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
		}
		return "\(seconds / 60)m \(seconds % 60)s"
	}

	// MARK: - AI Recommendation (T031)

	private var aiRecommendationSection: some View {
		Section(header: Text("Recommendation")) {
			if isGeneratingAI {
				HStack {
					ProgressView()
					Text("Generating local AI recommendation...")
						.foregroundStyle(.secondary)
				}
			} else if !aiSummary.isEmpty {
				Text(aiSummary)
			} else if !session.aiSummaryText.isEmpty {
				Text(session.aiSummaryText)
			} else {
				structuredRecommendation
			}

			if !isGeneratingAI && generatingPresets.isEmpty {
				Button {
					Task {
						await rerunAllRecommendations()
					}
				} label: {
					Label("Re-run Analysis", systemImage: "arrow.clockwise")
				}
			}
		}
	}

	private var structuredRecommendation: some View {
		VStack(alignment: .leading, spacing: 8) {
			if let bestPreset = session.presetResults.max(by: { $0.uniqueNodesFound < $1.uniqueNodesFound }) {
				Label {
					Text("Most nodes discovered on **\(bestPreset.presetName)** (\(bestPreset.uniqueNodesFound) nodes)")
				} icon: {
					Image(systemName: "star.fill")
						.foregroundStyle(.yellow)
				}
			}

			if let leastCongested = session.presetResults.filter({ $0.averageChannelUtilization > 0 }).min(by: { $0.averageChannelUtilization < $1.averageChannelUtilization }) {
				Label {
					Text("Least congested: **\(leastCongested.presetName)** (\(String(format: "%.1f%%", leastCongested.averageChannelUtilization)) util)")
				} icon: {
					Image(systemName: "waveform.path")
						.foregroundStyle(.green)
				}
			}

			let chatDominant = session.presetResults.filter { $0.messageCount > $0.sensorPacketCount }
			let sensorDominant = session.presetResults.filter { $0.sensorPacketCount > $0.messageCount }
			if !chatDominant.isEmpty {
				Label {
					Text("Chat-dominated: \(chatDominant.map(\.presetName).joined(separator: ", "))")
				} icon: {
					Image(systemName: "bubble.left.and.bubble.right")
						.foregroundStyle(.blue)
				}
			}
			if !sensorDominant.isEmpty {
				Label {
					Text("Sensor-dominated: \(sensorDominant.map(\.presetName).joined(separator: ", "))")
				} icon: {
					Image(systemName: "thermometer.medium")
						.foregroundStyle(.orange)
				}
			}
		}
		.font(.callout)
	}

	@MainActor
	private func generateAIRecommendation() async {
		guard session.aiSummaryText.isEmpty else { return }

		if #available(iOS 26, *) {
			await generateFoundationModelRecommendation()
		}
	}

	@available(iOS 26, *)
	private func generateFoundationModelRecommendation() async {
		#if canImport(FoundationModels)
		isGeneratingAI = true
		defer { isGeneratingAI = false }

		do {
			let session = LanguageModelSession()
			let prompt = buildAIPrompt()
			let response = try await session.respond(to: prompt)
			aiSummary = response.content
			self.session.aiSummaryText = response.content
		} catch {
			Logger.discovery.error("📡 [Discovery] AI recommendation failed: \(error.localizedDescription)")
		}
		#endif
	}

	@MainActor
	private func generateFoundationModelPresetSummaries() async {
		guard #available(iOS 26, *) else { return }
		#if canImport(FoundationModels)
		let eligiblePresets = session.presetResults.filter { $0.uniqueNodesFound > 1 && $0.aiSummaryText.isEmpty }
		guard !eligiblePresets.isEmpty else { return }

		for result in eligiblePresets {
			generatingPresets.insert(result.presetName)
			do {
				let lmSession = LanguageModelSession()
				let prompt = buildPresetPrompt(result)
				let response = try await lmSession.respond(to: prompt)
				presetSummaries[result.presetName] = response.content
				result.aiSummaryText = response.content
			} catch {
				Logger.discovery.error("📡 [Discovery] Preset AI summary failed for \(result.presetName): \(error.localizedDescription)")
			}
			generatingPresets.remove(result.presetName)
		}
		#endif
	}

	private func loadCachedPresetSummaries() {
		for result in session.presetResults where !result.aiSummaryText.isEmpty {
			presetSummaries[result.presetName] = result.aiSummaryText
		}
	}

	@MainActor
	private func rerunAllRecommendations() async {
		aiSummary = ""
		session.aiSummaryText = ""
		presetSummaries = [:]
		for result in session.presetResults {
			result.aiSummaryText = ""
		}
		await generateAIRecommendation()
		await generateFoundationModelPresetSummaries()
	}

	private func buildAIPrompt() -> String {
		var prompt = "Analyze this Meshtastic mesh radio discovery scan and recommend the best modem preset. Be concise (3-4 sentences).\n\n"

		prompt += "LoRa Preset Reference:\n"
		prompt += "  LongFast: 250kHz BW, SF11, 1.07kbps, 153dB link budget. Default. Good range but high airtime per packet.\n"
		prompt += "  LongModerate: 125kHz BW, SF11, 0.34kbps, 155.5dB link budget. Maximum range, very slow.\n"
		prompt += "  LongSlow: 125kHz BW, SF12, 0.18kbps, 158dB link budget. Extreme range, extremely slow.\n"
		prompt += "  MediumSlow: 250kHz BW, SF10, 1.95kbps, 150.5dB link budget. ~2x LongFast speed.\n"
		prompt += "  MediumFast: 250kHz BW, SF9, 3.52kbps, 148dB link budget. ~3.5x LongFast speed.\n"
		prompt += "  ShortSlow: 250kHz BW, SF8, 6.25kbps, 145.5dB link budget. ~6x LongFast speed.\n"
		prompt += "  ShortFast: 250kHz BW, SF7, 10.94kbps, 143dB link budget. ~10x LongFast speed.\n"
		prompt += "  ShortTurbo: 500kHz BW, SF7, 21.88kbps, 140dB link budget. Maximum speed, minimum range.\n\n"

		prompt += "Key guidance:\n"
		prompt += "  - LongFast causes congestion in networks >60 nodes due to high airtime per packet and collision probability.\n"
		prompt += "  - Channel utilization >25% indicates congestion; >50% causes significant packet loss and delays.\n"
		prompt += "  - Dense urban/suburban networks benefit from MediumFast or MediumSlow (3-4x throughput, still good range).\n"
		prompt += "  - Extremely dense networks (>100 nodes, high traffic) should use ShortFast or ShortSlow.\n"
		prompt += "  - Infrastructure nodes (routers) competing for airtime benefit most from faster presets.\n"
		prompt += "  - Sensor-heavy networks generate more automated traffic; faster presets reduce airtime contention.\n"
		prompt += "  - Reduced range from faster presets is usually offset by improved reliability in dense deployments.\n\n"

		prompt += "Scan Date: \(session.timestamp.formatted())\n"
		prompt += "Total Unique Nodes: \(session.totalUniqueNodes)\n\n"

		for result in session.presetResults {
			prompt += "Preset: \(result.presetName)\n"
			prompt += "  Nodes: \(result.uniqueNodesFound) (Direct: \(result.directNeighborCount), Mesh: \(result.meshNeighborCount), Infrastructure: \(result.infrastructureNodeCount))\n"
			prompt += "  Messages: \(result.messageCount), Sensors: \(result.sensorPacketCount)\n"
			if result.averageChannelUtilization > 0 {
				prompt += "  Channel Util: \(String(format: "%.1f%%", result.averageChannelUtilization))\n"
			}
			if result.averageAirtimeRate > 0 {
				prompt += "  Airtime: \(String(format: "%.2f%%", result.averageAirtimeRate))\n"
			}
			prompt += "\n"
		}

		prompt += "Based on the scan data and preset reference, recommend which preset is best for this location. Consider node density, infrastructure count, channel utilization, airtime, and traffic mix. If congestion is high, recommend a faster preset."
		return prompt
	}

	private func buildPresetPrompt(_ result: DiscoveryPresetResultEntity) -> String {
		var prompt = "Briefly summarize (1-2 sentences) the performance of the \(result.presetName) Meshtastic modem preset based on this scan data.\n\n"

		// Provide preset-specific context
		switch result.presetName {
		case let name where name.contains("Long Fast"):
			prompt += "Preset info: 250kHz BW, SF11, 1.07kbps, 153dB link budget. Default preset. High airtime per packet; causes congestion in networks >60 nodes.\n"
		case let name where name.contains("Long Moderate"):
			prompt += "Preset info: 125kHz BW, SF11, 0.34kbps, 155.5dB link budget. Maximum range but extremely slow; only suitable for very sparse, long-range deployments.\n"
		case let name where name.contains("Long Slow"):
			prompt += "Preset info: 125kHz BW, SF12, 0.18kbps, 158dB link budget. Extreme range, extremely slow; only for point-to-point long-range links.\n"
		case let name where name.contains("Medium Slow"):
			prompt += "Preset info: 250kHz BW, SF10, 1.95kbps, 150.5dB link budget. ~2x LongFast speed. Bay Area mesh (150+ nodes) thrives on this preset.\n"
		case let name where name.contains("Medium Fast"):
			prompt += "Preset info: 250kHz BW, SF9, 3.52kbps, 148dB link budget. ~3.5x LongFast speed. Excellent balance for dense urban/suburban networks.\n"
		case let name where name.contains("Short Slow"):
			prompt += "Preset info: 250kHz BW, SF8, 6.25kbps, 145.5dB link budget. ~6x LongFast speed. Good for dense networks with adequate node spacing.\n"
		case let name where name.contains("Short Fast"):
			prompt += "Preset info: 250kHz BW, SF7, 10.94kbps, 143dB link budget. ~10x LongFast speed. Wellington NZ mesh (150+ nodes) switched here with excellent results.\n"
		case let name where name.contains("Short Turbo"):
			prompt += "Preset info: 500kHz BW, SF7, 21.88kbps, 140dB link budget. Maximum speed, minimum range. Only for very dense, close-proximity deployments.\n"
		default:
			break
		}

		prompt += "Channel util >25% indicates congestion; >50% causes significant packet loss.\n\n"
		prompt += "Nodes: \(result.uniqueNodesFound) (Direct: \(result.directNeighborCount), Mesh: \(result.meshNeighborCount), Infrastructure: \(result.infrastructureNodeCount))\n"
		prompt += "Messages: \(result.messageCount), Sensor Packets: \(result.sensorPacketCount)\n"
		if result.averageChannelUtilization > 0 {
			prompt += "Channel Utilization: \(String(format: "%.1f%%", result.averageChannelUtilization))\n"
		}
		if result.averageAirtimeRate > 0 {
			prompt += "Airtime: \(String(format: "%.2f%%", result.averageAirtimeRate))\n"
		}
		if result.packetSuccessRate > 0 {
			prompt += "Packet Success: \(String(format: "%.1f%%", result.packetSuccessRate * 100))\n"
		}
		prompt += "\nNote if this preset is well-suited for the observed traffic pattern and node density."
		return prompt
	}

	// MARK: - Helpers

	@ViewBuilder
	private func statusBadge(_ status: String) -> some View {
		let (color, icon): (Color, String) = switch status {
		case "complete": (.green, "checkmark.circle.fill")
		case "stopped": (.orange, "stop.circle.fill")
		case "interrupted": (.red, "exclamationmark.circle.fill")
		default: (.gray, "circle.dashed")
		}

		Label(status.capitalized, systemImage: icon)
			.foregroundStyle(color)
			.font(.callout)
	}

	private func formatDistance(_ meters: Double) -> String {
		if meters >= 1000 {
			return String(format: "%.1f km", meters / 1000)
		}
		return String(format: "%.0f m", meters)
	}
}
