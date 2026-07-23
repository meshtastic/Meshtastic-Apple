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
		// When connected to a 2.8 radio that advertised a region→preset map, show exactly that
		// region's legal presets. This is the ONLY case where the 2.8-only Lite/Narrow/Tiny presets
		// can appear — and only where the region actually permits them.
		if accessoryManager.checkIsVersionSupported(forVersion: "2.8.0"),
		   let regionCode = connectedRegionCode,
		   let info = accessoryManager.loRaRegionPresets[regionCode], !info.presets.isEmpty {
			let constrained = ModemPresets.selectable(supports2_8: true)
				.filter { info.presets.contains($0.protoEnumValue()) }
			if !constrained.isEmpty { return constrained }
		}
		// Otherwise (offline, or the firmware advertised no region map) show the widely-supported
		// preset set — never the 2.8-only Lite/Narrow/Tiny presets, which would otherwise appear as
		// unusable grey tiles.
		return ModemPresets.userSelectable
	}

	/// The connected radio's region as the protobuf enum used to key `loRaRegionPresets`, derived the
	/// same way as the LoRa Config screen (`RegionCodes(rawValue:)` on the stored region code).
	private var connectedRegionCode: Config.LoRaConfig.RegionCode? {
		let num = Int64(UserDefaults.preferredPeripheralNum)
		var descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		descriptor.fetchLimit = 1
		guard let raw = (try? context.fetch(descriptor))?.first?.loRaConfig?.regionCode,
			  let region = RegionCodes(rawValue: Int(raw)) else { return nil }
		return region.protoEnumValue()
	}

	/// Most-common public-mesh presets from MQTT telemetry (LongFast dominant, MediumFast a distant
	/// second); auto-selected so a first scan covers the presets most meshes actually use.
	private let popularPresets: [ModemPresets] = [.longFast, .medFast]

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
					// Idle configuration (and iPhone scanning): a scrolling List that fills the pane on
					// every layout (iPhone, iPad, Mac Catalyst).
					scanList(proxy: proxy)
						.frame(maxWidth: .infinity)
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
				// Auto-select presets we've heard beacons for plus the most-popular public-mesh
				// presets, once, so a fresh scan covers any mesh a beacon advertised and the presets
				// most meshes actually use. Union-only: never clears the user's own choices, and gated
				// so it runs a single time and never fights a deliberate deselection afterward.
				if !didAutoSelectBeaconPresets {
					didAutoSelectBeaconPresets = true
					selectedPresets.formUnion(beaconPresets)
					selectedPresets.formUnion(Set(popularPresets).intersection(Set(availablePresets)))
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
					heroSection
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
					if engine.isSeededRun, let span = dataCollectionSpan {
						Label("Analyzing \(spanLengthText(from: span.start, to: span.end)) of collected data", systemImage: "clock.arrow.circlepath")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					VStack(alignment: .leading, spacing: 2) {
						HStack {
							Text("Time Remaining")
							Spacer()
							Text(formatDuration(engine.dwellTimeRemaining)).monospacedDigit()
						}
						.font(.caption)
						.foregroundStyle(.secondary)
						ProgressView(value: 1.0 - (engine.dwellTimeRemaining / engine.dwellDuration))
							.tint(.accentColor)
					}
					.accessibilityElement(children: .combine)
					.accessibilityValue(
						String(
							localized: "\(Int((1.0 - (engine.dwellTimeRemaining / engine.dwellDuration)) * 100)) percent",
							comment: "VoiceOver: discovery scan dwell progress percentage"
						)
					)
				}
			}

			HStack(alignment: .firstTextBaseline, spacing: 4) {
				Text("\(session.discoveredNodes.count)")
					.font(.title2.weight(.semibold))
					.monospacedDigit()
					.foregroundStyle(.tint)
				Text("nodes discovered")
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
		Section {
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
				if engine.isSeededRun, let span = dataCollectionSpan {
					Label("Analyzing \(spanLengthText(from: span.start, to: span.end)) of collected data", systemImage: "clock.arrow.circlepath")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				HStack {
					Text("Time Remaining")
					Spacer()
					Text(formatDuration(engine.dwellTimeRemaining))
						.monospacedDigit()
						.foregroundStyle(.secondary)
				}
				ProgressView(value: 1.0 - (engine.dwellTimeRemaining / engine.dwellDuration))
					.tint(.accentColor)
			}

			if let session = engine.session {
				HStack(alignment: .firstTextBaseline, spacing: 6) {
					Text("Nodes Discovered")
					Spacer()
					Text("\(session.discoveredNodes.count)")
						.font(.title3.weight(.semibold))
						.monospacedDigit()
						.foregroundStyle(.tint)
				}
			}
		} header: {
			sectionHeader("Scan Progress", systemImage: "dot.radiowaves.left.and.right")
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

// MARK: - Idle Setup UI

extension DiscoveryScanView {

	// MARK: - Hero

	/// The tasteful summary at the top of the idle configuration screen: an icon, a one-line pitch,
	/// and — when there's local history — the collected-data span as a highlighted card. Rendered on
	/// a clear List background so it reads as a hero rather than a grouped cell.
	@ViewBuilder
	var heroSection: some View {
		Section {
			heroHeader
				.listRowBackground(Color.clear)
				.listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
		}
	}

	@ViewBuilder
	private var heroHeader: some View {
		VStack(spacing: 12) {
			Image(systemName: "dot.radiowaves.left.and.right")
				.font(.system(size: 44))
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.tint)
			Text("Discover meshes around you")
				.font(.title3.weight(.semibold))
				.multilineTextAlignment(.center)
			Text("Sweep modem presets to find nearby nodes, or analyze your current preset from everything you've already collected.")
				.font(.footnote)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			if let span = dataCollectionSpan {
				dataSpanCard(span)
			}
		}
		.frame(maxWidth: .infinity)
	}

	/// The collected-data span presented as a highlighted card: a duration headline
	/// ("3 weeks of mesh data") with a locale-aware "since" subtitle. Shown in the hero when local
	/// history exists so it's clear the seeded analysis reflects the whole span, not just a 60s dwell.
	@ViewBuilder
	func dataSpanCard(_ span: (start: Date, end: Date)) -> some View {
		HStack(spacing: 12) {
			Image(systemName: "chart.bar.doc.horizontal")
				.font(.title2)
				.foregroundStyle(.tint)
			VStack(alignment: .leading, spacing: 2) {
				Text("\(spanLengthText(from: span.start, to: span.end)) of mesh data")
					.font(.headline)
				Text("since \(shortDate(span.start)) · first heard → last heard")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 0)
		}
		.padding()
		.frame(maxWidth: .infinity)
		.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 14, style: .continuous)
				.strokeBorder(.tint.opacity(0.25), lineWidth: 1)
		}
	}

	/// An accent-tinted section header with an SF Symbol, used across the setup screen for a
	/// consistent, native-feeling pop.
	@ViewBuilder
	func sectionHeader(_ title: String, systemImage: String) -> some View {
		Label(title, systemImage: systemImage)
			.foregroundStyle(.tint)
	}

	// MARK: - Modem Presets

	/// Compact, adaptive grid of selectable capsule "chips" — one per available preset — replacing
	/// the old row-per-preset list. Reads as multi-column on iPad/Mac and stays short on iPhone.
	var presetPickerSection: some View {
		let beaconAdvertised = beaconPresets
		let popular = Set(popularPresets)
		return Section {
			LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
				ForEach(availablePresets) { preset in
					presetChip(
						preset,
						isBeacon: beaconAdvertised.contains(preset),
						isPopular: popular.contains(preset)
					)
				}
			}
			.padding(.vertical, 4)
			.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
		} header: {
			sectionHeader("Modem Presets", systemImage: "antenna.radiowaves.left.and.right")
		} footer: {
			VStack(alignment: .leading, spacing: 4) {
				if availablePresets.contains(where: { popular.contains($0) }) {
					Label("A star marks the presets most public meshes use — pre-selected for you.", systemImage: "star.fill")
				}
				if !beaconAdvertised.isEmpty {
					Label("A beacon icon marks a preset a beacon advertised — also pre-selected.", systemImage: "dot.radiowaves.left.and.right")
				}
			}
		}
	}

	/// One selectable preset chip: accent-filled with a checkmark when selected, a subtle outlined
	/// fill when not; a beacon glyph when a beacon advertised the preset and a star when it's one of
	/// the most-popular public presets. Tapping toggles membership in `selectedPresets`.
	@ViewBuilder
	private func presetChip(_ preset: ModemPresets, isBeacon: Bool, isPopular: Bool) -> some View {
		let isSelected = selectedPresets.contains(preset)
		Button {
			if selectedPresets.contains(preset) {
				selectedPresets.remove(preset)
			} else {
				selectedPresets.insert(preset)
			}
		} label: {
			VStack(spacing: 6) {
				HStack(spacing: 5) {
					if isPopular {
						Image(systemName: "star.fill")
							.font(.caption2)
							.foregroundStyle(isSelected ? Color.white : Color.secondary)
					}
					if isBeacon {
						Image(systemName: "dot.radiowaves.left.and.right")
							.font(.caption2)
							.foregroundStyle(isSelected ? Color.white : Color.accentColor)
					}
					if isSelected {
						Image(systemName: "checkmark")
							.font(.caption2.weight(.bold))
							.foregroundStyle(Color.white)
					}
				}
				.frame(height: 14)
				Text(preset.description)
					.font(.caption2.weight(.medium))
					.multilineTextAlignment(.center)
					.lineLimit(2)
					.minimumScaleFactor(0.6)
			}
			.frame(maxWidth: .infinity, minHeight: 48)
			.padding(.vertical, 10)
			.padding(.horizontal, 8)
			.foregroundStyle(isSelected ? Color.white : Color.primary)
			.background {
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
			}
			.overlay {
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 1)
			}
			.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
		}
		.buttonStyle(.plain)
	}

	// MARK: - Beacon Channels

	/// A row per custom channel a beacon advertised. Selecting one adds a target that tunes the scan
	/// to that mesh's channel (name + PSK), so private meshes a beacon told us about can be scanned
	/// directly — distinct from the Modem Presets rows, which only run on the default public channel.
	@ViewBuilder
	var beaconChannelsSection: some View {
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
				sectionHeader("Beacon Channels", systemImage: "dot.radiowaves.left.and.right")
			} footer: {
				Text("Private channels advertised by beacons. Selecting one tunes the scan to that mesh so its traffic can be decoded.")
			}
		}
	}

	// MARK: - Dwell Configuration

	var dwellConfigSection: some View {
		Section {
			Picker("Dwell Duration", selection: $dwellMinutes) {
				Text("15 min").tag(15)
				Text("30 min").tag(30)
				Text("45 min").tag(45)
				Text("60 min").tag(60)
				Text("90 min").tag(90)
				Text("120 min").tag(120)
				Text("180 min").tag(180)
			}
		} header: {
			sectionHeader("Dwell Time Per Preset", systemImage: "timer")
		}
	}

	// MARK: - Current Data Report

	func currentDataReportSection(_ engine: DiscoveryScanEngine) -> some View {
		Section {
			if let span = dataCollectionSpan {
				VStack(alignment: .leading, spacing: 3) {
					Text("\(spanLengthText(from: span.start, to: span.end)) of mesh data")
						.font(.headline)
					Text("since \(shortDate(span.start)) · first heard → last heard")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.vertical, 2)
			}
			Button {
				Task { await engine.startCurrentPresetScan() }
			} label: {
				Label("Analyze Current Preset", systemImage: "doc.text.magnifyingglass")
			}
		} header: {
			sectionHeader("Current Preset", systemImage: "doc.text.magnifyingglass")
		} footer: {
			Text("Reports on your current preset using everything already collected — every known node with its message, sensor, and RF-health stats — with no preset change or reboot. Works even with no radio connected.")
		}
	}

	// MARK: - Data Collection Span

	/// The full span of accumulated local mesh history: the earliest `firstHeard` → latest
	/// `lastHeard` across all nodes. The seeded "Analyze Current Preset" run is built from this whole
	/// history (not just its ~60s dwell), so the setup and progress screens surface it. Two tiny
	/// `fetchLimit = 1` fetches; `nil` when there's no data or the span is degenerate.
	var dataCollectionSpan: (start: Date, end: Date)? {
		var earliest = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.firstHeard != nil },
			sortBy: [SortDescriptor(\.firstHeard, order: .forward)]
		)
		earliest.fetchLimit = 1
		var latest = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.lastHeard != nil },
			sortBy: [SortDescriptor(\.lastHeard, order: .reverse)]
		)
		latest.fetchLimit = 1
		guard let start = (try? context.fetch(earliest))?.first?.firstHeard,
			  let end = (try? context.fetch(latest))?.first?.lastHeard,
			  end >= start else { return nil }
		return (start, end)
	}

	/// A compact, locale-aware length for a span — the single largest unit, e.g. "3 weeks",
	/// "5 days", "12 hours". Falls back to "less than a minute" for a near-zero span.
	func spanLengthText(from start: Date, to end: Date) -> String {
		let interval = end.timeIntervalSince(start)
		guard interval >= 60 else { return "less than a minute" }
		let formatter = DateComponentsFormatter()
		formatter.unitsStyle = .full
		formatter.maximumUnitCount = 1
		formatter.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute]
		return formatter.string(from: interval) ?? ""
	}

	/// A short, locale-aware date like "Jun 12".
	func shortDate(_ date: Date) -> String {
		date.formatted(.dateTime.month(.abbreviated).day())
	}
}
