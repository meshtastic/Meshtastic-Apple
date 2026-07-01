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
	@State private var dwellMinutes: Int = 15
	@State private var showHistory = false

	@State private var engine: DiscoveryScanEngine?

	private var connectedNode: NodeInfoEntity? {
		let nodeNum = Int64(UserDefaults.preferredPeripheralNum)
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == nodeNum }
		)
		descriptor.fetchLimit = 1
		return try? context.fetch(descriptor).first
	}

	private var availablePresets: [ModemPresets] {
		// Lite / Narrow presets are intentionally hidden from selection
		// for now — see `ModemPresets.userSelectable`.
		ModemPresets.userSelectable
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
					dwellConfigSection
					if connectedNode != nil {
						currentDataReportSection(engine)
					}
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
		Section(header: Text("Modem Presets")) {
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
						Spacer()
						if selectedPresets.contains(preset) {
							Image(systemName: "checkmark")
								.foregroundStyle(.blue)
						}
					}
				}
				.foregroundStyle(.primary)
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
			footer: Text("Analyze only your radio's current preset, seeded with everything already collected — every node heard, per-node message and sensor counts, and RF health including noise floor — so the run starts from your full history rather than an empty scan. Stop anytime to view the summary.")
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
					engine.dwellDuration = TimeInterval(dwellMinutes * 60)
					Task { await engine.startScan() }
				} label: {
					Label("Start Scan", systemImage: "play.fill")
				}
				.disabled(selectedPresets.isEmpty || !accessoryManager.isConnected)
			} else if engine.isScanning {
				Button(role: .destructive) {
					Task { await engine.stopScan() }
				} label: {
					Label("Stop Scan", systemImage: "stop.fill")
				}
			} else if engine.currentState == .complete {
				Button {
					selectedPresets = []
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
