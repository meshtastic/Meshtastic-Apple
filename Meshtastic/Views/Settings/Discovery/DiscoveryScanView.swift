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
import SwiftData
import SwiftUI
import TipKit

struct DiscoveryScanView: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	@State private var selectedPresets: Set<ModemPresets> = []
	@State private var dwellMinutes: Int = 15
	@State private var showHistory = false
	@State private var showDefaultKeyAlert = false

	@Query(sort: \NodeInfoEntity.lastHeard, order: .reverse)
	private var nodes: [NodeInfoEntity]

	@State private var engine: DiscoveryScanEngine?

	private var connectedNode: NodeInfoEntity? {
		let nodeNum = UserDefaults.preferredPeripheralNum
		return nodes.first(where: { $0.num == Int64(nodeNum) })
	}

	private var primaryChannelUsesDefaultKey: Bool {
		guard let channels = connectedNode?.myInfo?.channels else { return true }
		guard let primaryChannel = channels.first(where: { $0.role == 1 }) else { return true }
		let defaultKey = Data([0x01])
		return primaryChannel.psk == nil || primaryChannel.psk == defaultKey || primaryChannel.psk?.isEmpty == true
	}

	private var availablePresets: [ModemPresets] {
		ModemPresets.allCases
	}

	private let discoveryScanTip = DiscoveryScanTip()

	var body: some View {
		List {
			TipView(discoveryScanTip)
				.listRowBackground(Color.clear)
				.listRowInsets(EdgeInsets())

			if let engine {
				if engine.isScanning || engine.currentState == .complete || engine.currentState == .analysis {
					scanProgressSection(engine)
				}

				if engine.currentState == .idle {
					if !primaryChannelUsesDefaultKey {
						Section {
							Label("The primary channel must use the default key to perform a discovery scan.", systemImage: "exclamationmark.triangle.fill")
								.foregroundStyle(.orange)
						}
					}
					presetPickerSection
					dwellConfigSection
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
						DiscoveryMapView(
							discoveredNodes: session.discoveredNodes,
							userLatitude: session.userLatitude,
							userLongitude: session.userLongitude,
							isScanning: engine.currentState == .dwell
						)
						#if targetEnvironment(macCatalyst)
						.frame(minHeight: 500, maxHeight: 700)
						#else
						.frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 450 : 300)
						#endif
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
			if !primaryChannelUsesDefaultKey {
				showDefaultKeyAlert = true
			}
		}
		.alert("Default Key Required", isPresented: $showDefaultKeyAlert) {
			Button("OK", role: .cancel) { }
		} message: {
			Text("Local Mesh Discovery requires the primary channel to use the default key. Please reset your primary channel key to the default before scanning.")
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
				.disabled(selectedPresets.isEmpty || !accessoryManager.isConnected || !primaryChannelUsesDefaultKey)
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
