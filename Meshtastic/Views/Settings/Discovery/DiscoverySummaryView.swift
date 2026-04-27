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

	var body: some View {
		List {
			sessionOverviewSection
			presetResultsSection
			rfHealthSection
			aiRecommendationSection
		}
		.navigationTitle("Scan Summary")
		.task {
			await generateAIRecommendation()
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

	private func presetCard(_ result: DiscoveryPresetResultEntity) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(result.presetName)
				.font(.headline)

			LazyVGrid(columns: [
				GridItem(.flexible()),
				GridItem(.flexible())
			], spacing: 6) {
				metricItem("Nodes", value: "\(result.uniqueNodesFound)")
				metricItem("Direct", value: "\(result.directNeighborCount)")
				metricItem("Mesh", value: "\(result.meshNeighborCount)")
				metricItem("Messages", value: "\(result.messageCount)")
				metricItem("Sensor Pkts", value: "\(result.sensorPacketCount)")
				if result.averageChannelUtilization > 0 {
					metricItem("Ch Util", value: String(format: "%.1f%%", result.averageChannelUtilization))
				}
				if result.averageAirtimeRate > 0 {
					metricItem("Airtime", value: String(format: "%.2f%%", result.averageAirtimeRate))
				}
			}
		}
		.padding(.vertical, 4)
	}

	private func metricItem(_ label: String, value: String) -> some View {
		VStack(alignment: .leading) {
			Text(label)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.callout)
				.fontWeight(.medium)
		}
	}

	// MARK: - RF Health (T030)

	private var rfHealthSection: some View {
		Section(header: Text("RF Health")) {
			let hasRFData = session.presetResults.contains { $0.packetSuccessRate > 0 || $0.packetFailureRate > 0 }
			if hasRFData {
				ForEach(session.presetResults.filter { $0.packetSuccessRate > 0 || $0.packetFailureRate > 0 }, id: \.presetName) { result in
					VStack(alignment: .leading, spacing: 4) {
						Text(result.presetName)
							.font(.subheadline)
							.fontWeight(.medium)
						HStack {
							Label(String(format: "%.1f%% success", result.packetSuccessRate * 100), systemImage: "checkmark.circle")
								.foregroundStyle(.green)
								.font(.caption)
							Spacer()
							Label(String(format: "%.1f%% failure", result.packetFailureRate * 100), systemImage: "xmark.circle")
								.foregroundStyle(.red)
								.font(.caption)
						}
					}
				}
			} else {
				Text("No LocalStats data collected")
					.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: - AI Recommendation (T031)

	private var aiRecommendationSection: some View {
		Section(header: Text("Recommendation")) {
			if isGeneratingAI {
				HStack {
					ProgressView()
					Text("Generating AI recommendation...")
						.foregroundStyle(.secondary)
				}
			} else if !aiSummary.isEmpty {
				Text(aiSummary)
			} else if !session.aiSummaryText.isEmpty {
				Text(session.aiSummaryText)
			} else {
				structuredRecommendation
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
			// Fall through to structured recommendation
		}
		#endif
	}

	private func buildAIPrompt() -> String {
		var prompt = "Analyze this Meshtastic mesh radio discovery scan and recommend the best modem preset. Be concise (2-3 sentences).\n\n"
		prompt += "Scan Date: \(session.timestamp.formatted())\n"
		prompt += "Total Unique Nodes: \(session.totalUniqueNodes)\n\n"

		for result in session.presetResults {
			prompt += "Preset: \(result.presetName)\n"
			prompt += "  Nodes: \(result.uniqueNodesFound) (Direct: \(result.directNeighborCount), Mesh: \(result.meshNeighborCount))\n"
			prompt += "  Messages: \(result.messageCount), Sensors: \(result.sensorPacketCount)\n"
			if result.averageChannelUtilization > 0 {
				prompt += "  Channel Util: \(String(format: "%.1f%%", result.averageChannelUtilization))\n"
			}
			prompt += "\n"
		}

		prompt += "Consider: node count, channel utilization, and mix of chat vs sensor traffic. Recommend which preset is best for this location."
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
