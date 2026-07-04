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

	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context

	@State private var aiSummary: String = ""
	@State private var isGeneratingAI: Bool = false
	@State private var generatingPresets: Set<String> = []
	@State private var presetSummaries: [String: String] = [:]
	@State private var isExportingPDF: Bool = false
	@State private var isGeneratingPDF: Bool = false
	@State private var pdfDocument: PDFDocument?
	/// Beacon awaiting a "switch to this channel" confirmation; drives the alert.
	@State private var beaconToJoin: DiscoveredBeaconEntity?
	@State private var joinErrorMessage: String?
	/// Beacon awaiting an "add channel" confirmation; drives the Add alert.
	@State private var beaconToAdd: DiscoveredBeaconEntity?
	@State private var addErrorMessage: String?
	/// Beacon awaiting a "replace which secondary channel?" choice when no free slot exists (D2).
	@State private var beaconToReplace: DiscoveredBeaconEntity?

	var body: some View {
		List {
			sessionOverviewSection
			presetResultsSection
			beaconsSection
			rfHealthSection
			aiRecommendationSection
		}
		.listSectionSpacing(.compact)
		.navigationTitle("Scan Summary")
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				if isGeneratingPDF {
					ProgressView()
				} else {
					Button {
						Task {
							isGeneratingPDF = true
							let data = await DiscoverySummaryPDF.generate(session: session)
							pdfDocument = PDFDocument(data: data)
							isGeneratingPDF = false
							isExportingPDF = true
						}
					} label: {
						Image(systemName: "square.and.arrow.up")
					}
				}
			}
		}
		.fileExporter(
			isPresented: $isExportingPDF,
			document: pdfDocument,
			contentType: .pdf,
			defaultFilename: "Meshtastic Scan \(session.timestamp.exportTimestamp)"
		) { result in
			switch result {
			case .success:
				Logger.services.info("Discovery scan PDF export succeeded.")
			case .failure(let error):
				Logger.services.error("Discovery scan PDF export failed: \(error.localizedDescription, privacy: .public)")
			}
		}
		.task {
			loadCachedPresetSummaries()
			await generateAIRecommendation()
			await generateFoundationModelPresetSummaries()
		}
		.alert("Switch to this channel?", isPresented: Binding(
			get: { beaconToJoin != nil },
			set: { if !$0 { beaconToJoin = nil } }
		), presenting: beaconToJoin) { beacon in
			Button("Cancel", role: .cancel) { beaconToJoin = nil }
			Button("Switch") { switchToBeaconChannel(beacon) }
		} message: { beacon in
			Text(beaconSwitchPrompt(beacon))
		}
		.alert("Couldn't switch channel", isPresented: Binding(
			get: { joinErrorMessage != nil },
			set: { if !$0 { joinErrorMessage = nil } }
		)) {
			Button("OK", role: .cancel) { joinErrorMessage = nil }
		} message: {
			Text(joinErrorMessage ?? "")
		}
		.alert("Add this channel?", isPresented: Binding(
			get: { beaconToAdd != nil },
			set: { if !$0 { beaconToAdd = nil } }
		), presenting: beaconToAdd) { beacon in
			Button("Cancel", role: .cancel) { beaconToAdd = nil }
			Button("Add") { addBeaconChannel(beacon) }
		} message: { beacon in
			Text("Add \"\(beacon.offerChannelName)\" as an additional channel — your radio keeps its current mesh, no reboot.")
		}
		.alert("Couldn't add channel", isPresented: Binding(
			get: { addErrorMessage != nil },
			set: { if !$0 { addErrorMessage = nil } }
		)) {
			Button("OK", role: .cancel) { addErrorMessage = nil }
		} message: {
			Text(addErrorMessage ?? "")
		}
		.confirmationDialog(
			"Replace which channel?",
			isPresented: Binding(
				get: { beaconToReplace != nil },
				set: { if !$0 { beaconToReplace = nil } }
			),
			titleVisibility: .visible,
			presenting: beaconToReplace
		) { beacon in
			ForEach(accessoryManager.beaconReplaceableSecondaryChannels()) { channel in
				Button("\(channel.name) (slot \(channel.index))", role: .destructive) {
					replaceBeaconChannel(beacon, atIndex: channel.index)
				}
			}
			Button("Cancel", role: .cancel) { beaconToReplace = nil }
		} message: { _ in
			Text("All secondary channel slots are full. Choose an existing secondary channel to replace — your primary channel is never touched.")
		}
	}

	/// Applies a beacon's advertised channel + region/preset to the connected radio. The radio
	/// reboots onto the advertised mesh; failures surface in an alert.
	private func switchToBeaconChannel(_ beacon: DiscoveredBeaconEntity) {
		beaconToJoin = nil
		Task {
			do {
				try await accessoryManager.joinBeaconMesh(
					channelName: beacon.offerChannelName,
					channelPSK: beacon.offerChannelPSK,
					region: beacon.offeredRegion,
					preset: beacon.offeredPreset
				)
			} catch {
				joinErrorMessage = error.localizedDescription
			}
		}
	}

	private func beaconSwitchPrompt(_ beacon: DiscoveredBeaconEntity) -> String {
		var parts = ["This sets your radio's primary channel to \"\(beacon.offerChannelName)\""]
		if let preset = beacon.offeredPreset { parts.append("the \(preset.description) preset") }
		if let region = beacon.offeredRegion { parts.append("region \(region.description)") }
		let joined = parts.count > 1
			? parts.dropLast().joined(separator: ", ") + " and " + parts.last!
			: parts[0]
		return "\(joined). Your radio will reboot and reconnect on the new mesh. Your previous channel settings will be replaced."
	}

	// MARK: - Session Overview

	private var sessionOverviewSection: some View {
		Section(header: Text("Session Overview")) {
			LabeledContent("Date", value: session.timestamp.formatted(date: .abbreviated, time: .shortened))
			LabeledContent("Presets Scanned", value: session.presetsScanned.replacingOccurrences(of: ",", with: ", "))
			ForEach(session.presetResults, id: \.presetName) { result in
				if result.dwellDurationSeconds > 0 {
					LabeledContent("\(result.presetName) Dwell", value: formatDwellDuration(result.dwellDurationSeconds))
				}
			}
			let totalDwell = session.presetResults.reduce(0) { $0 + $1.dwellDurationSeconds }
			if totalDwell > 0 {
				LabeledContent("Total Dwell Time", value: formatDwellDuration(totalDwell))
			}
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

	// MARK: - Beacons

	/// Beacons heard during the scan, newest first. Hidden entirely when none were received so the
	/// section doesn't add noise to scans on meshes that don't run beacon nodes.
	@ViewBuilder
	private var beaconsSection: some View {
		let beacons = session.beacons.sorted { $0.timestamp > $1.timestamp }
		if !beacons.isEmpty {
			Section {
				ForEach(beacons) { beacon in
					beaconCard(beacon)
				}
			} header: {
				Label("Beacons", systemImage: "dot.radiowaves.left.and.right")
			} footer: {
				Text("Nodes advertising a mesh to join. A preset offered by a beacon is added to the scan automatically.")
			}
		}
	}

	@ViewBuilder
	private func beaconCard(_ beacon: DiscoveredBeaconEntity) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(beacon.displayName)
					.font(.headline)
				Spacer()
				Text("\(String(format: "%.1f", beacon.snr)) SNR")
					.font(.caption)
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}

			if !beacon.message.isEmpty {
				Text(beacon.message)
					.font(.subheadline)
					.fixedSize(horizontal: false, vertical: true)
			}

			// Offered preset / region / channel chips — only what the beacon actually advertised.
			let chips = beaconChips(beacon)
			if !chips.isEmpty {
				HStack(spacing: 6) {
					ForEach(chips, id: \.self) { chip in
						Text(chip)
							.font(.caption2)
							.padding(.horizontal, 8)
							.padding(.vertical, 3)
							.background(Color.accentColor.opacity(0.15), in: Capsule())
					}
				}
			}

			if !beacon.heardOnPresetName.isEmpty {
				Text("Heard on \(beacon.heardOnPresetName)")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}

			// Offer join actions only when the beacon advertised a channel. When the offered mesh
			// already runs on the radio's current preset/region/frequency slot, Add (no reboot) is
			// offered alongside Switch; otherwise only Switch (retune + reboot) is shown (FR-016).
			let joinOption = beaconJoinOption(for: beacon)
			if joinOption != .none {
				HStack(spacing: 8) {
					if joinOption == .add {
						Button {
							beaconToAdd = beacon
						} label: {
							Label("Add channel", systemImage: "plus.circle")
								.font(.caption)
						}
						.buttonStyle(.bordered)
						.controlSize(.small)
						.disabled(!accessoryManager.isConnected)
					}
					Button {
						beaconToJoin = beacon
					} label: {
						Label("Switch to this channel", systemImage: "arrow.triangle.2.circlepath")
							.font(.caption)
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
					.disabled(!accessoryManager.isConnected)
				}
				.padding(.top, 2)
			}
		}
		.padding(.vertical, 4)
	}

	/// Builds the "advertised" chips for a beacon (preset, region, channel), skipping anything the
	/// beacon didn't offer.
	private func beaconChips(_ beacon: DiscoveredBeaconEntity) -> [String] {
		var chips: [String] = []
		if let preset = beacon.offeredPreset {
			chips.append(preset.description)
		}
		if let region = beacon.offeredRegion {
			chips.append(region.description)
		}
		if beacon.hasOfferChannel, !beacon.offerChannelName.isEmpty {
			chips.append("#\(beacon.offerChannelName)")
		}
		return chips
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
					HStack(spacing: 6) {
						Image(systemName: "waveform")
							.foregroundStyle(result.noiseFloorSampleCount == 0 ? Color.secondary : (result.averageNoiseFloor < -110 ? .green : (result.averageNoiseFloor > -95 ? .red : .orange)))
						Text("Noise")
						Text(result.noiseFloorSampleCount > 0 ? "\(String(format: "%.0f", result.averageNoiseFloor)) dBm" : "—")
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
					|| $0.noiseFloorSampleCount > 0
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
					if result.noiseFloorSampleCount > 0 {
						Label(String(format: "%.0f dBm noise", result.averageNoiseFloor), systemImage: "waveform")
							.foregroundStyle(result.averageNoiseFloor < -110 ? .green : (result.averageNoiseFloor > -95 ? .red : .orange))
					}
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

			if let quietest = session.presetResults.filter({ $0.noiseFloorSampleCount > 0 }).min(by: { $0.averageNoiseFloor < $1.averageNoiseFloor }) {
				Label {
					Text("Quietest channel: **\(quietest.presetName)** (\(String(format: "%.0f", quietest.averageNoiseFloor)) dBm noise floor)")
				} icon: {
					Image(systemName: "waveform")
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
		guard await FoundationModelAvailability.shared.isAvailable else { return }
		isGeneratingAI = true
		defer { isGeneratingAI = false }

		do {
			let session = LanguageModelSession()
			let prompt = buildAIPrompt()
			let response = try await session.respond(to: prompt)
			aiSummary = response.content
			self.session.aiSummaryText = response.content
		} catch {
			await FoundationModelAvailability.shared.reportFailure(error)
			Logger.discovery.error("📡 [Discovery] AI recommendation failed: \(error.localizedDescription)")
		}
		#endif
	}

	@MainActor
	private func generateFoundationModelPresetSummaries() async {
		guard #available(iOS 26, *) else { return }
		#if canImport(FoundationModels)
		guard await FoundationModelAvailability.shared.isAvailable else { return }
		let eligiblePresets = session.presetResults.filter { $0.uniqueNodesFound > 1 && $0.aiSummaryText.isEmpty }
		guard !eligiblePresets.isEmpty else { return }

		for result in eligiblePresets {
			guard await FoundationModelAvailability.shared.isAvailable else { break }
			generatingPresets.insert(result.presetName)
			do {
				let lmSession = LanguageModelSession()
				let prompt = buildPresetPrompt(result)
				let response = try await lmSession.respond(to: prompt)
				presetSummaries[result.presetName] = response.content
				result.aiSummaryText = response.content
			} catch {
				await FoundationModelAvailability.shared.reportFailure(error)
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
		await FoundationModelAvailability.shared.reset()
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
		prompt += "  - Reduced range from faster presets is usually offset by improved reliability in dense deployments.\n"
		prompt += "  - Noise Floor (dBm) is the RF background noise measured on each preset's frequency; lower (more negative) is quieter. A high noise floor (e.g. above -95 dBm) means an interference-heavy channel and lower effective range, so prefer a quieter preset when node activity is comparable.\n\n"

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
			if result.noiseFloorSampleCount > 0 {
				prompt += "  Noise Floor: \(String(format: "%.0f dBm", result.averageNoiseFloor))\n"
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

	private func formatDwellDuration(_ seconds: Int) -> String {
		if seconds >= 3600 {
			let hours = seconds / 3600
			let mins = (seconds % 3600) / 60
			return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
		}
		return "\(seconds / 60)m"
	}

	private func formatDistance(_ meters: Double) -> String {
		let measurement = Measurement(value: meters, unit: UnitLength.meters)
		let formatter = MeasurementFormatter()
		formatter.unitOptions = .naturalScale
		formatter.numberFormatter.maximumFractionDigits = 1
		return formatter.string(from: measurement)
	}
}

// MARK: - Beacon join (Add vs Switch, FR-016/FR-017)

extension DiscoverySummaryView {

	/// Decide which join action a beacon supports on the connected radio (contract C6). Reads the
	/// connected node's LoRa config + primary channel and delegates to the pure decision in
	/// `LoRaChannelCalculator`.
	func beaconJoinOption(for beacon: DiscoveredBeaconEntity) -> BeaconJoinOption {
		let num = Int64(UserDefaults.preferredPeripheralNum)
		let node = getNodeInfo(id: num, context: context)
		return LoRaChannelCalculator.beaconJoinOption(
			hasOfferChannel: beacon.hasOfferChannel,
			offerChannelName: beacon.offerChannelName,
			offeredPreset: beacon.offeredPreset,
			offerRegion: beacon.offerRegion,
			isConnected: accessoryManager.isConnected,
			loRaConfig: node?.loRaConfig,
			primaryChannelName: beaconPrimaryChannelName(for: node)
		)
	}

	/// The connected node's primary channel name for slot derivation. Mirrors the Channels editor's
	/// firmware-accurate rule: use the named primary channel; when the primary is the unnamed default
	/// public channel, fall back to the preset's default channel name (what the firmware hashes),
	/// which is what makes the slot comparison correct.
	private func beaconPrimaryChannelName(for node: NodeInfoEntity?) -> String {
		guard let node else { return "" }
		if let primary = node.myInfo?.channels.first(where: { $0.index == 0 || $0.role == 1 }),
		   let name = primary.name, !name.isEmpty {
			return name
		}
		if node.loRaConfig?.usePreset == false {
			return "Custom"
		}
		guard let preset = ModemPresets(rawValue: Int(node.loRaConfig?.modemPreset ?? 0)) else {
			return "LongFast"
		}
		return preset.androidChannelName
	}

	/// Adds a beacon's advertised channel to a free secondary slot (no reboot). When every secondary
	/// slot is full, presents the replace-a-secondary picker instead of erroring (D2). Failures
	/// surface in an alert.
	func addBeaconChannel(_ beacon: DiscoveredBeaconEntity) {
		beaconToAdd = nil
		// No free slot → let the user choose an existing secondary to replace (never the primary).
		guard accessoryManager.beaconHasFreeSecondarySlot() else {
			beaconToReplace = beacon
			return
		}
		Task {
			do {
				try await accessoryManager.addBeaconChannel(
					channelName: beacon.offerChannelName,
					channelPSK: beacon.offerChannelPSK
				)
			} catch {
				addErrorMessage = error.localizedDescription
			}
		}
	}

	/// Replaces the secondary channel at `index` with the beacon's advertised channel (D2). Cancelling
	/// the picker makes no change.
	func replaceBeaconChannel(_ beacon: DiscoveredBeaconEntity, atIndex index: Int32) {
		beaconToReplace = nil
		Task {
			do {
				try await accessoryManager.addBeaconChannel(
					channelName: beacon.offerChannelName,
					channelPSK: beacon.offerChannelPSK,
					replacingIndex: index
				)
			} catch {
				addErrorMessage = error.localizedDescription
			}
		}
	}
}
