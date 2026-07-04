// MARK: DiscoveryScanView
//
//  DiscoveryScanView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import MapKit
import MeshtasticProtobufs
import OSLog
@preconcurrency import SwiftData
import SwiftUI
import TipKit

struct DiscoveryScanView: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	@State private var selectedPresets: Set<ModemPresets> = []
	/// Custom-channel targets (from beacons that advertised a channel) the user has selected to scan.
	@State private var selectedChannels: Set<BeaconChannel> = []
	@State private var dwellMinutes: Int = 15
	@State private var showHistory = false
	/// Ensures beacon-advertised presets are pre-selected only once per appearance, so the seed
	/// never fights a deliberate deselection the user makes afterward.
	@State private var didAutoSelectBeaconPresets = false
	/// Same one-shot pre-selection guard for beacon-advertised custom channels.
	@State private var didAutoSelectBeaconChannels = false

	@State private var engine: DiscoveryScanEngine?

	private var availablePresets: [ModemPresets] {
		// Lite / Narrow presets are intentionally hidden from selection
		// for now — see `ModemPresets.userSelectable`.
		ModemPresets.userSelectable
	}

	/// Selectable presets we've heard a beacon advertise (across all past sessions). These are
	/// pre-checked when the picker first appears so a fresh scan includes any mesh a beacon told us
	/// about, and flagged with a beacon icon in the row.
	private var beaconPresets: Set<ModemPresets> {
		let descriptor = FetchDescriptor<DiscoveredBeaconEntity>()
		guard let beacons = try? context.fetch(descriptor) else { return [] }
		let available = Set(availablePresets)
		return Set(beacons.compactMap { $0.offeredPreset }).intersection(available)
	}

	private let discoveryScanTip = DiscoveryScanTip()

	var body: some View {
		GeometryReader { proxy in
			Group {
				if let engine, usesFillMapLayout, let session = engine.session,
				   engine.isScanning || engine.currentState == .complete {
					// iPad / Mac Catalyst, scanning or complete: a non-scrolling layout with a compact
					// status header and the map filling all remaining space (no scrolling).
					mapFillingLayout(engine, session: session)
				} else {
					scanList(proxy: proxy)
				}
			}
			.navigationTitle("Local Mesh Discovery")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					NavigationLink {
						DiscoveryHistoryView()
					} label: {
						Image(systemName: "clock.arrow.circlepath")
					}
				}
			}
			.onAppear {
				if engine == nil {
					engine = accessoryManager.discoveryEngine
				}
				engine?.configure(accessoryManager: accessoryManager, modelContext: context)
				engine?.checkForInterruptedSessions(context: context)
				// Auto-select presets we've heard beacons for, once, so a fresh scan covers any
				// mesh a beacon advertised. Union-only: never clears the user's own choices.
				if !didAutoSelectBeaconPresets {
					didAutoSelectBeaconPresets = true
					selectedPresets.formUnion(beaconPresets)
				}
				// Same one-shot pre-selection for custom channels a beacon advertised.
				if !didAutoSelectBeaconChannels {
					didAutoSelectBeaconChannels = true
					selectedChannels.formUnion(beaconChannels)
				}
			}
		}
	}

	/// iPad and Mac Catalyst show a non-scrolling, map-filling layout while scanning or when a scan
	/// is complete; iPhone keeps the scrolling list so the controls aren't cramped on a small screen.
	private var usesFillMapLayout: Bool {
		#if targetEnvironment(macCatalyst)
		return true
		#else
		return UIDevice.current.userInterfaceIdiom == .pad
		#endif
	}

	// MARK: - Scrolling List (iPhone, and the idle configuration screen)

	@ViewBuilder
	private func scanList(proxy: GeometryProxy) -> some View {
		List {
			TipView(discoveryScanTip)
				.listRowBackground(Color.clear)
				.listRowInsets(EdgeInsets())

			if let engine {
				if engine.isScanning || engine.currentState == .complete || engine.currentState == .analysis {
					scanProgressSection(engine)
				}

				if engine.currentState == .idle {
					presetPickerSection
					beaconChannelsSection
					dwellConfigSection
					// "Analyze Current Preset" is seeded from local SwiftData and sends nothing to
					// the radio, so it's always available — including with no radio connected (review
					// your mesh offline). The full multi-preset "Start Scan" below stays gated on a
					// live connection because it changes the radio's preset.
					currentDataReportSection(engine)
				}

				scanControlSection(engine)

				if engine.currentState == .complete, let session = engine.session {
					NavigationLink {
						DiscoverySummaryView(session: session)
					} label: {
						Label("View Summary", systemImage: "chart.bar.doc.horizontal")
					}
				}

				if let session = engine.session, engine.isScanning || engine.currentState == .complete {
					Section(header: Text("Discovery Map")) {
						discoveryMap(for: session, engine: engine, availableHeight: proxy.size.height)
							.listRowInsets(EdgeInsets())
					}
				}

				if let errorMessage = engine.errorMessage {
					Section {
						Label(errorMessage, systemImage: "exclamationmark.triangle")
							.foregroundStyle(.red)
					}
				}
			}
		}
	}

	// MARK: - Map-Filling Layout (iPad / Mac Catalyst)

	/// A non-scrolling layout: a compact status header at its natural height, with the map taking
	/// all remaining vertical space. Because it's a `VStack` (not a `List`), nothing scrolls — the
	/// map simply fills whatever is left after the header.
	@ViewBuilder
	private func mapFillingLayout(_ engine: DiscoveryScanEngine, session: DiscoverySessionEntity) -> some View {
		VStack(spacing: 0) {
			statusHeader(engine, session: session)
			DiscoveryMapView(
				discoveredNodes: session.discoveredNodes,
				userLatitude: session.userLatitude,
				userLongitude: session.userLongitude,
				isScanning: engine.currentState == .dwell
			)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	@ViewBuilder
	private func statusHeader(_ engine: DiscoveryScanEngine, session: DiscoverySessionEntity) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				if let activePreset = engine.activePreset {
					Label(activePreset.description, systemImage: "antenna.radiowaves.left.and.right")
						.font(.headline)
				}
				Spacer()
				Text(stateDescription(engine))
					.foregroundStyle(.secondary)
			}

			if engine.currentState == .dwell {
				VStack(alignment: .leading, spacing: 2) {
					HStack {
						Text("Time Remaining")
						Spacer()
						Text(formatDuration(engine.dwellTimeRemaining)).monospacedDigit()
					}
					.font(.caption)
					.foregroundStyle(.secondary)
					ProgressView(value: 1.0 - (engine.dwellTimeRemaining / engine.dwellDuration))
				}
			}

			HStack {
				Text("\(session.discoveredNodes.count) nodes discovered")
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				statusControls(engine)
			}
		}
		.padding()
		.background(Color(.secondarySystemBackground))
	}

	@ViewBuilder
	private func statusControls(_ engine: DiscoveryScanEngine) -> some View {
		if engine.isScanning {
			Button(role: .destructive) {
				Task { await engine.stopScan() }
			} label: {
				Label("Stop Scan", systemImage: "stop.fill")
			}
			.buttonStyle(.borderedProminent)
		} else if engine.currentState == .complete, let session = engine.session {
			HStack(spacing: 8) {
				NavigationLink {
					DiscoverySummaryView(session: session)
				} label: {
					Label("View Summary", systemImage: "chart.bar.doc.horizontal")
				}
				.buttonStyle(.bordered)
				Button {
					selectedPresets = []
					selectedChannels = []
					engine.session = nil
					engine.currentState = .idle
				} label: {
					Label("New Scan", systemImage: "arrow.counterclockwise")
				}
				.buttonStyle(.bordered)
			}
		}
	}

	private var presetPickerSection: some View {
		let beaconAdvertised = beaconPresets
		return Section {
			ForEach(availablePresets) { preset in
				Button {
					if selectedPresets.contains(preset) {
						selectedPresets.remove(preset)
					} else {
						selectedPresets.insert(preset)
					}
				} label: {
					HStack {
						Text(preset.description)
						if beaconAdvertised.contains(preset) {
							Image(systemName: "dot.radiowaves.left.and.right")
								.foregroundStyle(.blue)
								.help("A beacon advertised this preset")
						}
						Spacer()
						if selectedPresets.contains(preset) {
							Image(systemName: "checkmark")
								.foregroundStyle(.blue)
						}
					}
				}
				.foregroundStyle(.primary)
			}
		} header: {
			Text("Modem Presets")
		} footer: {
			if !beaconAdvertised.isEmpty {
				Label("Presets marked with a beacon icon were advertised by a beacon and pre-selected.", systemImage: "dot.radiowaves.left.and.right")
			}
		}
	}

	// MARK: - Beacon Channels

	/// A row per custom channel a beacon advertised. Selecting one adds a target that tunes the scan
	/// to that mesh's channel (name + PSK), so private meshes a beacon told us about can be scanned
	/// directly — distinct from the Modem Presets rows, which only run on the default public channel.
	@ViewBuilder
	private var beaconChannelsSection: some View {
		let channels = beaconChannels
		if !channels.isEmpty {
			Section {
				ForEach(channels) { channel in
					Button {
						if selectedChannels.contains(channel) {
							selectedChannels.remove(channel)
						} else {
							selectedChannels.insert(channel)
						}
					} label: {
						HStack {
							Image(systemName: "lock.fill")
								.font(.caption)
								.foregroundStyle(.secondary)
							VStack(alignment: .leading, spacing: 1) {
								Text(channel.name)
								Text(channel.preset.description)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							Image(systemName: "dot.radiowaves.left.and.right")
								.foregroundStyle(.blue)
								.help("Advertised by a beacon")
							Spacer()
							if selectedChannels.contains(channel) {
								Image(systemName: "checkmark")
									.foregroundStyle(.blue)
							}
						}
					}
					.foregroundStyle(.primary)
				}
			} header: {
				Text("Beacon Channels")
			} footer: {
				Text("Private channels advertised by beacons. Selecting one tunes the scan to that mesh so its traffic can be decoded.")
			}
		}
	}

	// MARK: - Dwell Configuration

	private var dwellConfigSection: some View {
		Section(header: Text("Dwell Time Per Preset")) {
			Picker("Dwell Duration", selection: $dwellMinutes) {
				Text("15 min").tag(15)
				Text("30 min").tag(30)
				Text("45 min").tag(45)
				Text("60 min").tag(60)
				Text("90 min").tag(90)
				Text("120 min").tag(120)
				Text("180 min").tag(180)
			}
		}
	}

	// MARK: - Current Data Report

	private func currentDataReportSection(_ engine: DiscoveryScanEngine) -> some View {
		Section(
			header: Text("Current Preset"),
			footer: Text("Analyze only your current preset, seeded with everything already collected — every node heard, per-node message and sensor counts, and RF health including noise floor — so the run starts from your full history rather than an empty scan. Runs even with no radio connected. Stop anytime to view the summary.")
		) {
			Button {
				Task { await engine.startCurrentPresetScan() }
			} label: {
				Label("Analyze Current Preset", systemImage: "doc.text.magnifyingglass")
			}
		}
	}

	// MARK: - Discovery Map

	/// The discovery map sized for the device. On iPad and Mac Catalyst it fills most of the screen's
	/// available height (`availableHeight` comes from the `GeometryReader` wrapping the `List` —
	/// `containerRelativeFrame` inside a List row resolves against the self-sizing cell, not the
	/// window, so it collapses) so the map is the dominant element rather than a short fixed band;
	/// the controls remain reachable by scrolling. iPhone keeps a compact fixed height so it doesn't
	/// crowd the controls on a small screen.
	@ViewBuilder
	private func discoveryMap(for session: DiscoverySessionEntity, engine: DiscoveryScanEngine, availableHeight: CGFloat) -> some View {
		let map = DiscoveryMapView(
			discoveredNodes: session.discoveredNodes,
			userLatitude: session.userLatitude,
			userLongitude: session.userLongitude,
			isScanning: engine.currentState == .dwell
		)
		#if targetEnvironment(macCatalyst)
		map.frame(height: max(520, availableHeight * 0.8))
		#else
		if UIDevice.current.userInterfaceIdiom == .pad {
			map.frame(height: max(450, availableHeight * 0.78))
		} else {
			map.frame(height: 300)
		}
		#endif
	}

	// MARK: - Scan Progress

	private func scanProgressSection(_ engine: DiscoveryScanEngine) -> some View {
		Section(header: Text("Scan Progress")) {
			if let activePreset = engine.activePreset {
				HStack {
					Text("Active Preset")
					Spacer()
					Text(activePreset.description)
						.foregroundStyle(.secondary)
				}
			}

			HStack {
				Text("State")
				Spacer()
				Text(stateDescription(engine))
					.foregroundStyle(.secondary)
			}

			if engine.currentState == .dwell {
				HStack {
					Text("Time Remaining")
					Spacer()
					Text(formatDuration(engine.dwellTimeRemaining))
						.monospacedDigit()
						.foregroundStyle(.secondary)
				}
				ProgressView(value: 1.0 - (engine.dwellTimeRemaining / engine.dwellDuration))
			}

			if let session = engine.session {
				HStack {
					Text("Nodes Discovered")
					Spacer()
					Text("\(session.discoveredNodes.count)")
						.foregroundStyle(.secondary)
				}
			}
		}
	}

	// MARK: - Scan Control

	private func scanControlSection(_ engine: DiscoveryScanEngine) -> some View {
		Section {
			if engine.currentState == .idle {
				Button {
					engine.selectedPresets = Array(selectedPresets)
					engine.selectedBeaconTargets = selectedChannels.map { $0.scanTarget }
					engine.dwellDuration = TimeInterval(dwellMinutes * 60)
					Task { await engine.startScan() }
				} label: {
					Label("Start Scan", systemImage: "play.fill")
				}
				.disabled((selectedPresets.isEmpty && selectedChannels.isEmpty) || !accessoryManager.isConnected)
			} else if engine.isScanning {
				Button(role: .destructive) {
					Task { await engine.stopScan() }
				} label: {
					Label("Stop Scan", systemImage: "stop.fill")
				}
			} else if engine.currentState == .complete {
				Button {
					selectedPresets = []
					selectedChannels = []
					engine.session = nil
					engine.currentState = .idle
				} label: {
					Label("New Scan", systemImage: "arrow.counterclockwise")
				}
			}
		}
	}

	// MARK: - Helpers

	private func stateDescription(_ engine: DiscoveryScanEngine) -> String {
		switch engine.currentState {
		case .idle: return "Ready"
		case .shifting: return "Changing Preset..."
		case .reconnecting: return "Reconnecting..."
		case .dwell: return "Collecting Data"
		case .analysis: return "Analyzing..."
		case .complete: return "Complete"
		case .paused: return "Paused — Waiting for Connection"
		case .restoring: return "Restoring Home Preset..."
		}
	}

	private func formatDuration(_ seconds: TimeInterval) -> String {
		let mins = Int(seconds) / 60
		let secs = Int(seconds) % 60
		return String(format: "%d:%02d", mins, secs)
	}
}

// MARK: - Beacon channel model

extension DiscoveryScanView {

	/// A custom channel advertised by a beacon, shown as its own selectable row in the scan setup.
	/// Deduped by name + preset; carries the PSK/region needed to tune the radio to that mesh.
	struct BeaconChannel: Hashable, Identifiable {
		let name: String
		let psk: Data
		let preset: ModemPresets
		let regionRaw: Int
		var id: String { "\(name)|\(preset.rawValue)" }
		var scanTarget: ScanTarget {
			ScanTarget(preset: preset, regionRaw: regionRaw > 0 ? regionRaw : nil, channelName: name, channelPSK: psk)
		}
	}

	/// Distinct custom channels heard from beacons across past sessions, for the Beacon Channels
	/// section. A beacon must advertise both a channel name and a modem preset to be tunable.
	var beaconChannels: [BeaconChannel] {
		let descriptor = FetchDescriptor<DiscoveredBeaconEntity>()
		guard let beacons = try? context.fetch(descriptor) else { return [] }
		var seen = Set<String>()
		var channels: [BeaconChannel] = []
		for beacon in beacons where beacon.hasOfferChannel && !beacon.offerChannelName.isEmpty {
			guard let preset = beacon.offeredPreset else { continue }
			let channel = BeaconChannel(name: beacon.offerChannelName, psk: beacon.offerChannelPSK,
										preset: preset, regionRaw: beacon.offerRegion)
			if seen.insert(channel.id).inserted { channels.append(channel) }
		}
		return channels.sorted { $0.name < $1.name }
	}
}
