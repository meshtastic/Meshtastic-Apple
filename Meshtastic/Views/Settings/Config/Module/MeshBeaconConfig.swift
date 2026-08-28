//
//  MeshBeaconConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//
//  Editor for ModuleConfig.MeshBeaconConfig (FR-009–FR-014): turn the connected
//  node into a mesh beacon that periodically advertises its mesh so other nodes'
//  discovery scans can find and join it. Mirrors the existing module-config
//  screens (DetectionSensorConfig et al): reads the connected node's config into
//  an edit buffer and writes changes back via an AdminMessage
//  (setModuleConfig.meshBeacon) through AccessoryManager.
//
//  Mesh beacons are a 2.8 firmware capability, so the screen gates on
//  checkIsVersionSupported("2.8.0") with a graceful unsupported state.
//

import MeshtasticProtobufs
import OSLog
import SwiftUI

struct MeshBeaconConfig: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	let node: NodeInfoEntity?

	@State private var hasChanges = false

	// MARK: Edit buffer (mirrors MeshBeaconConfigEntity)
	@State private var flags: Int32 = 0
	@State private var broadcastMessage = ""
	@State private var offerChannelName = ""
	@State private var offerChannelPSK = Data()
	@State private var offerChannelIndex: Int32 = -1
	// Stored broadcast-on name+key pair, kept only to pass through unchanged when the
	// seeded selection matches none of the radio's channels (a pair set from another client).
	@State private var onChannelName = ""
	@State private var onChannelPSK = Data()
	@State private var beaconInterval = UpdateInterval(from: 3_600)
	@State private var targets: [BroadcastTargetDraft] = [BroadcastTargetDraft()]
	@State private var seededTargetKeys: [[Int32]] = []

	/// In-memory draft for one broadcast row. A single row saves as the broadcast-on
	/// config; multiple rows save as `broadcast_targets`, one beacon each.
	struct BroadcastTargetDraft: Identifiable, Equatable {
		let id = UUID()
		var preset: Int32 = -1   // -1 = falls back to running config
		var channelIndex: Int32 = -1 // -1 = unset (default channel)
	}

	private var supports2_8: Bool {
		accessoryManager.checkIsVersionSupported(forVersion: "2.8.0")
	}

	/// The radio's configured LoRa region. Every part of the beacon — the offered
	/// channel, the transmit settings, and each broadcast target — uses this region;
	/// a beacon is a tuning invitation, and inviting listeners onto a region the
	/// radio is not legally configured for is never right.
	private var nodeRegion: Int32 { Int32(node?.loRaConfig?.regionCode ?? 0) }

	private var hasConfiguredRegion: Bool { nodeRegion != RegionCodes.unset.rawValue }

	/// The radio's own configured modem preset — what a picked channel actually runs on
	/// today, and the natural preselection when a channel is chosen and no preset is set.
	private var nodeModemPreset: Int32 { Int32(node?.loRaConfig?.modemPreset ?? -1) }

	private var nodeModemPresetName: String {
		ModemPresets(rawValue: Int(nodeModemPreset))?.description ?? "Unknown"
	}

	private var nodeRegionName: String {
		RegionCodes(rawValue: Int(nodeRegion))?.description ?? "Unset"
	}

	/// The radio's own channels — the only channels a beacon can offer or transmit on.
	private var nodeChannels: [ChannelEntity] {
		canonicalValidUniqueChannels(from: node?.myInfo?.channels ?? [])
	}

	private func channelDisplayName(_ channel: ChannelEntity) -> String {
		if let name = channel.name, !name.isEmpty { return name }
		return channel.index == 0 ? "Primary" : "Channel \(channel.index)"
	}

	/// Resolves a stored name+key pair to the matching channel's index for the picker
	/// seed: -1 when the pair is empty (None), -2 when it matches no channel (a value
	/// set outside this editor). The primary channel commonly has an empty name, so
	/// the key participates in matching — a name round-trip alone cannot identify it.
	private func resolveChannelIndex(name: String, psk: Data) -> Int32 {
		if name.isEmpty && psk.isEmpty { return -1 }
		if let match = nodeChannels.first(where: { ($0.name ?? "") == name && ($0.psk ?? Data()) == psk }) {
			return match.index
		}
		if let match = nodeChannels.first(where: { ($0.name ?? "") == name && !name.isEmpty }) {
			return match.index
		}
		return -2
	}

	/// Writes the selected channel's name and key into the edit buffer.
	private func applyChannelSelection(_ index: Int32, name: inout String, psk: inout Data) {
		guard index >= 0, let channel = nodeChannels.first(where: { $0.index == index }) else {
			if index == -1 {
				name = ""
				psk = Data()
			}
			return
		}
		name = channel.name ?? ""
		psk = channel.psk ?? Data()
	}

	@ViewBuilder
	private func channelPicker(_ label: String, selection: Binding<Int32>, customName: String, noneLabel: String? = "None") -> some View {
		Picker(selection: selection) {
			if let noneLabel {
				Text(noneLabel).tag(Int32(-1))
			}
			if selection.wrappedValue == -2 {
				Text("Custom: \(customName.isEmpty ? "unnamed" : customName)").tag(Int32(-2))
			}
			if selection.wrappedValue >= 0, !nodeChannels.contains(where: { $0.index == selection.wrappedValue }) {
				Text("Channel \(selection.wrappedValue)").tag(selection.wrappedValue)
			}
			ForEach(nodeChannels, id: \.index) { channel in
				Text(channelDisplayName(channel)).tag(channel.index)
			}
		} label: {
			Label(label, systemImage: "fibrechannel")
		}
	}

	// Blocking validation (FR-011 / FR-013) — never truncate or clamp; block save with inline errors.
	private var isMessageValid: Bool { MeshBeaconValidation.isMessageValid(broadcastMessage) }
	private var isIntervalValid: Bool { MeshBeaconValidation.isIntervalValid(Int32(truncatingIfNeeded: beaconInterval.intValue)) }
	private var hasOfferChannel: Bool { offerChannelIndex >= 0 || offerChannelIndex == -2 }
	private var canSave: Bool { isMessageValid && isIntervalValid && hasConfiguredRegion && hasOfferChannel }

	var body: some View {
		Group {
			if supports2_8 {
				editorForm
			} else {
				unsupportedState
			}
		}
		.navigationTitle("Mesh Beacon Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
	}

	// MARK: - Unsupported (older firmware)

	private var unsupportedState: some View {
		ContentUnavailableView {
			Label("Mesh Beacons Not Supported", systemImage: "dot.radiowaves.left.and.right")
		} description: {
			Text("Mesh beacons require firmware 2.8 or newer.")
		}
	}

	// MARK: - Editor

	private var editorForm: some View {
		Form {
			ConfigHeader(title: "Mesh Beacon", config: \.meshBeaconConfig, node: node, onAppear: setMeshBeaconValues)
			if !hasConfiguredRegion {
				Section {
					Label("Set a LoRa region before configuring a mesh beacon.", systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.orange)
						.font(.callout)
				}
			}
			optionsSection
			if hasConfiguredRegion, MeshBeaconFlags.has(flags, MeshBeaconFlags.broadcastEnabled) {
				messageSection
				offeredSection
				intervalSection
				broadcastSection
			}
		}
		.scrollDismissesKeyboard(.interactively)
		.disabled(!accessoryManager.isConnected || node?.meshBeaconConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				performConfigSave(
					node: node,
					context: context,
					accessoryManager: accessoryManager,
					hasChanges: $hasChanges,
					dismiss: goBack
				) { fromUser, toUser in
					_ = try await accessoryManager.saveMeshBeaconModuleConfig(config: buildConfig(), fromUser: fromUser, toUser: toUser)
				}
			}
			.disabled(!canSave)
		}
		.onChange(of: broadcastMessage) { if broadcastMessage != (node?.meshBeaconConfig?.broadcastMessage ?? "") { hasChanges = true } }
		.onChange(of: offerChannelIndex) { applyChannelSelection(offerChannelIndex, name: &offerChannelName, psk: &offerChannelPSK) }
		.onChange(of: offerChannelName) { if offerChannelName != (node?.meshBeaconConfig?.broadcastOfferChannelName ?? "") { hasChanges = true } }
		.onChange(of: offerChannelPSK) { if offerChannelPSK != (node?.meshBeaconConfig?.broadcastOfferChannelPSK ?? Data()) { hasChanges = true } }
		.onChange(of: beaconInterval) { if beaconInterval.intValue != Int(node?.meshBeaconConfig?.broadcastIntervalSecs ?? 3600) { hasChanges = true } }
		.onChange(of: targets) { oldRows, newRows in
			// Picking a channel preselects the radio's own preset when the row has none —
			// that is what the channel runs on today. Only applies when the user changes
			// a row's channel, never to rows just seeded from the stored config.
			for index in newRows.indices where newRows[index].channelIndex >= 0 && newRows[index].preset == -1 {
				if let previous = oldRows.first(where: { $0.id == newRows[index].id }),
				   previous.channelIndex != newRows[index].channelIndex {
					targets[index].preset = nodeModemPreset
				}
			}
			if targets.map({ [$0.preset, $0.channelIndex] }) != seededTargetKeys { hasChanges = true }
		}
	}

	private var optionsSection: some View {
		Section(header: Text("Options")) {
			Toggle(isOn: flagBinding(MeshBeaconFlags.listenEnabled)) {
				Label("Listen for Beacons", systemImage: "antenna.radiowaves.left.and.right")
				Text("Hear beacons from other meshes and show them in discovery.")
			}

			Toggle(isOn: flagBinding(MeshBeaconFlags.broadcastEnabled)) {
				Label("Broadcast a Beacon", systemImage: "dot.radiowaves.right")
				Text("Advertise this mesh so nearby radios can find and join it.")
			}
		}
	}

	private var messageSection: some View {
		Section(header: Text("Beacon Message")) {
			TextField("Message", text: $broadcastMessage, axis: .vertical)
				.autocorrectionDisabled()
			HStack {
				Text("\(MeshBeaconValidation.messageByteCount(broadcastMessage)) / \(MeshBeaconValidation.maxMessageBytes) bytes")
					.font(.caption)
					.foregroundStyle(isMessageValid ? .secondary : Color.red)
				Spacer()
			}
			if !isMessageValid {
				Text("Message must be \(MeshBeaconValidation.maxMessageBytes) bytes or fewer.")
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
	}

	private var offeredSection: some View {
		Section(header: Text("Offered to Listeners")) {
			channelPicker("Channel", selection: $offerChannelIndex, customName: offerChannelName, noneLabel: nil)
			regionRow
			offerPresetRow
		}
	}

	/// The offered preset is always the radio's own modem preset — the offered channel
	/// runs on it, so advertising any other preset would describe a channel wrong.
	private var offerPresetRow: some View {
		HStack {
			Text("Preset")
			Spacer()
			Text(nodeModemPresetName)
				.foregroundStyle(.secondary)
		}
	}

	private var intervalSection: some View {
		Section(header: Text("Broadcast Interval")) {
			UpdateIntervalPicker(
				config: .meshBeacon,
				pickerLabel: "Interval",
				selectedInterval: $beaconInterval
			)
		}
	}

	private var broadcastSection: some View {
		Section(header: Text("Broadcast On"), footer: Text("The channel and preset the beacon transmits on. Add a target to broadcast on more channels.")) {
			ForEach($targets) { $target in
				VStack(alignment: .leading, spacing: 6) {
					channelPicker("Channel", selection: $target.channelIndex, customName: onChannelName, noneLabel: "Default")
					presetPicker("Preset", selection: $target.preset)
				}
			}
			.onDelete { offsets in
				targets.remove(atOffsets: offsets)
				if targets.isEmpty { targets = [BroadcastTargetDraft()] }
			}
			Button {
				targets.append(BroadcastTargetDraft())
			} label: {
				Label("Add Target", systemImage: "plus.circle")
			}
		}
	}

	// MARK: - Reusable field builders

	/// The beacon always uses the radio's configured region — shown, not chosen.
	private var regionRow: some View {
		HStack {
			Label("Region", systemImage: "globe")
			Spacer()
			Text(nodeRegionName)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private func presetPicker(_ label: String, selection: Binding<Int32>) -> some View {
		Picker(label, selection: selection) {
			Text("Default").tag(Int32(-1))
			ForEach(availablePresets(currentSelection: selection.wrappedValue)) { preset in
				Text(preset.description).tag(Int32(preset.rawValue))
			}
		}
	}

	/// Presets legal for the radio's own region, matching the discovery scan's rules:
	/// when the connected 2.8+ radio advertised a region→preset map, exactly that
	/// region's legal set — the only case the 2.8-only Lite/Narrow/Tiny presets can
	/// appear. Without a map, the conservative widely-supported set, never the full
	/// 2.8 list. The currently-selected preset stays visible even when filtered out,
	/// so an existing config never renders a blank row.
	private func availablePresets(currentSelection: Int32) -> [ModemPresets] {
		var presets = ModemPresets.userSelectable
		if supports2_8,
		   let code = RegionCodes(rawValue: Int(nodeRegion))?.protoEnumValue(),
		   let info = accessoryManager.loRaRegionPresets[code],
		   !info.presets.isEmpty {
			let constrained = ModemPresets.selectable(supports2_8: true)
				.filter { info.presets.contains($0.protoEnumValue()) }
			if !constrained.isEmpty { presets = constrained }
		}
		if currentSelection >= 0,
		   let current = ModemPresets(rawValue: Int(currentSelection)),
		   !presets.contains(current) {
			presets.append(current)
		}
		return presets
	}

	/// A binding that toggles a single flag bit while preserving every other bit (D4).
	private func flagBinding(_ flag: Int32) -> Binding<Bool> {
		Binding(
			get: { MeshBeaconFlags.has(flags, flag) },
			set: { newValue in
				flags = MeshBeaconFlags.setting(flags, flag, to: newValue)
				hasChanges = true
			}
		)
	}

	// MARK: - Load / build

	private func setMeshBeaconValues() {
		let config = node?.meshBeaconConfig
		flags = config?.flags ?? 0
		broadcastMessage = config?.broadcastMessage ?? ""
		offerChannelName = config?.broadcastOfferChannelName ?? ""
		offerChannelPSK = config?.broadcastOfferChannelPSK ?? Data()
		onChannelName = config?.broadcastOnChannelName ?? ""
		onChannelPSK = config?.broadcastOnChannelPSK ?? Data()
		offerChannelIndex = resolveChannelIndex(name: offerChannelName, psk: offerChannelPSK)
		// A beacon must offer a channel to join; a stored config without one gets the
		// primary channel.
		if offerChannelIndex == -1, let first = nodeChannels.first {
			offerChannelIndex = first.index
			offerChannelName = first.name ?? ""
			offerChannelPSK = first.psk ?? Data()
		}
		beaconInterval = UpdateInterval(from: Int(config?.broadcastIntervalSecs ?? 3_600))
		// Stored targets when present, otherwise a single row from the broadcast-on
		// fields. The relationship's order isn't guaranteed, so sort for a stable list.
		let storedTargets = (config?.broadcastTargets ?? []).sorted {
			($0.channelIndex, $0.preset) < ($1.channelIndex, $1.preset)
		}
		if storedTargets.isEmpty {
			targets = [BroadcastTargetDraft(
				preset: config?.broadcastOnPreset ?? -1,
				channelIndex: resolveChannelIndex(name: onChannelName, psk: onChannelPSK)
			)]
		} else {
			targets = storedTargets.map { BroadcastTargetDraft(preset: $0.preset, channelIndex: $0.channelIndex) }
		}
		seededTargetKeys = targets.map { [$0.preset, $0.channelIndex] }
		hasChanges = false
	}

	/// Assemble the protobuf from the edit buffer for the admin write. `FLAG_LEGACY_SPLIT` and any
	/// other bits not exposed here ride along in `flags` unchanged (D4).
	private func buildConfig() -> ModuleConfig.MeshBeaconConfig {
		var config = ModuleConfig.MeshBeaconConfig()
		config.flags = UInt32(truncatingIfNeeded: flags)
		config.broadcastMessage = broadcastMessage

		// The primary channel's name is empty, so presence is keyed on the selection
		// (or a non-empty custom pair), never on the name alone.
		if offerChannelIndex >= 0 || !offerChannelName.isEmpty || !offerChannelPSK.isEmpty {
			var settings = ChannelSettings()
			settings.name = offerChannelName
			settings.psk = offerChannelPSK
			config.broadcastOfferChannel = settings
		}
		if let region = Config.LoRaConfig.RegionCode(rawValue: Int(nodeRegion)) {
			config.broadcastOfferRegion = region
		}
		if nodeModemPreset >= 0, let preset = Config.LoRaConfig.ModemPreset(rawValue: Int(nodeModemPreset)) {
			config.broadcastOfferPreset = preset
		}

		// The first row is the broadcast-on config. A custom row (-2) passes the stored
		// name+key pair through unchanged.
		if let first = targets.first {
			if first.channelIndex >= 0, let channel = nodeChannels.first(where: { $0.index == first.channelIndex }) {
				var settings = ChannelSettings()
				settings.name = channel.name ?? ""
				settings.psk = channel.psk ?? Data()
				config.broadcastOnChannel = settings
			} else if first.channelIndex == -2 {
				var settings = ChannelSettings()
				settings.name = onChannelName
				settings.psk = onChannelPSK
				config.broadcastOnChannel = settings
			}
			if first.preset >= 0, let preset = Config.LoRaConfig.ModemPreset(rawValue: Int(first.preset)) {
				config.broadcastOnPreset = preset
			}
		}
		if let region = Config.LoRaConfig.RegionCode(rawValue: Int(nodeRegion)) {
			config.broadcastOnRegion = region
		}

		config.broadcastIntervalSecs = UInt32(truncatingIfNeeded: beaconInterval.intValue)
		// No longer exposed in this editor; ride the stored value along unchanged (D4) so
		// saving other fields cannot clear a value set from the CLI or another client.
		config.broadcastSendAsNode = UInt32(truncatingIfNeeded: node?.meshBeaconConfig?.broadcastSendAsNode ?? 0)

		// A single row rides in the broadcast-on fields alone; targets are written only
		// when there is more than one beacon to send.
		config.broadcastTargets = targets.count <= 1 ? [] : targets.map { draft in
			var target = ModuleConfig.MeshBeaconConfig.BroadcastTarget()
			if draft.preset >= 0, let preset = Config.LoRaConfig.ModemPreset(rawValue: Int(draft.preset)) {
				target.preset = preset
			}
			if let region = Config.LoRaConfig.RegionCode(rawValue: Int(nodeRegion)) {
				target.region = region
			}
			if draft.channelIndex >= 0 {
				target.channelIndex = UInt32(draft.channelIndex)
			}
			return target
		}
		return config
	}
}

#Preview {
	MeshBeaconConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
