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
	@State private var offerRegion: Int32 = 0
	@State private var offerPreset: Int32 = -1
	@State private var onChannelName = ""
	@State private var onChannelPSK = Data()
	@State private var onRegion: Int32 = 0
	@State private var onPreset: Int32 = -1
	@State private var intervalText = "3600"
	@State private var sendAsNodeText = "0"
	@State private var targets: [BroadcastTargetDraft] = []

	/// In-memory draft for one `broadcast_targets` row.
	struct BroadcastTargetDraft: Identifiable, Equatable {
		let id = UUID()
		var preset: Int32 = -1   // -1 = falls back to running config
		var region: Int32 = 0    // 0 = unset (running config)
		var channelIndex: Int32 = -1 // -1 = unset (default channel)
	}

	private var supports2_8: Bool {
		accessoryManager.checkIsVersionSupported(forVersion: "2.8.0")
	}

	// Blocking validation (FR-011 / FR-013) — never truncate or clamp; block save with inline errors.
	private var intervalValue: Int32 { Int32(intervalText) ?? 0 }
	private var isMessageValid: Bool { MeshBeaconValidation.isMessageValid(broadcastMessage) }
	private var isIntervalValid: Bool { MeshBeaconValidation.isIntervalValid(intervalValue) }
	// A node number is a UInt32. Empty = 0 = "this node". Reject non-digits or values that overflow
	// UInt32 so we never silently wrap a bad value (e.g. a pasted "-1") into a bogus node number.
	private var isSendAsNodeValid: Bool {
		if sendAsNodeText.isEmpty { return true }
		guard let value = UInt64(sendAsNodeText) else { return false }
		return value <= UInt64(UInt32.max)
	}
	private var canSave: Bool { isMessageValid && isIntervalValid && isSendAsNodeValid }

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
			Text("Mesh beacon broadcasting requires firmware 2.8 or newer. Update your radio to advertise your mesh to nearby nodes.")
		}
	}

	// MARK: - Editor

	private var editorForm: some View {
		Form {
			ConfigHeader(title: "Mesh Beacon", config: \.meshBeaconConfig, node: node, onAppear: setMeshBeaconValues)
			optionsSection
			if MeshBeaconFlags.has(flags, MeshBeaconFlags.broadcastEnabled) {
				messageSection
				offeredSection
				intervalSection
				broadcastTargetsSection
				if targets.isEmpty {
					singleTargetSection
				}
				advancedSection
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
		.onChange(of: offerChannelName) { if offerChannelName != (node?.meshBeaconConfig?.broadcastOfferChannelName ?? "") { hasChanges = true } }
		.onChange(of: offerChannelPSK) { if offerChannelPSK != (node?.meshBeaconConfig?.broadcastOfferChannelPSK ?? Data()) { hasChanges = true } }
		.onChange(of: offerRegion) { if offerRegion != (node?.meshBeaconConfig?.broadcastOfferRegion ?? 0) { hasChanges = true } }
		.onChange(of: offerPreset) { if offerPreset != (node?.meshBeaconConfig?.broadcastOfferPreset ?? -1) { hasChanges = true } }
		.onChange(of: onChannelName) { if onChannelName != (node?.meshBeaconConfig?.broadcastOnChannelName ?? "") { hasChanges = true } }
		.onChange(of: onChannelPSK) { if onChannelPSK != (node?.meshBeaconConfig?.broadcastOnChannelPSK ?? Data()) { hasChanges = true } }
		.onChange(of: onRegion) { if onRegion != (node?.meshBeaconConfig?.broadcastOnRegion ?? 0) { hasChanges = true } }
		.onChange(of: onPreset) { if onPreset != (node?.meshBeaconConfig?.broadcastOnPreset ?? -1) { hasChanges = true } }
		.onChange(of: intervalText) { if intervalText != String(node?.meshBeaconConfig?.broadcastIntervalSecs ?? 3600) { hasChanges = true } }
		.onChange(of: sendAsNodeText) { if sendAsNodeText != String(node?.meshBeaconConfig?.broadcastSendAsNode ?? 0) { hasChanges = true } }
		.onChange(of: targets) { if !targetsMatchEntity() { hasChanges = true } }
	}

	/// True when the draft targets exactly match the persisted config's targets (used to avoid
	/// flagging `hasChanges` when the buffer is first populated from the entity).
	private func targetsMatchEntity() -> Bool {
		let entityTargets = node?.meshBeaconConfig?.broadcastTargets ?? []
		guard entityTargets.count == targets.count else { return false }
		// `broadcastTargets` is a SwiftData to-many relationship whose order isn't guaranteed, so
		// compare content-sorted key tuples rather than zipping positionally (which would falsely
		// flag hasChanges when the same targets are returned in a different order).
		let draftKeys = targets.map { [$0.preset, $0.region, $0.channelIndex] }
			.sorted { $0.lexicographicallyPrecedes($1) }
		let entityKeys = entityTargets.map { [$0.preset, $0.region, $0.channelIndex] }
			.sorted { $0.lexicographicallyPrecedes($1) }
		return draftKeys == entityKeys
	}

	private var optionsSection: some View {
		Section(header: Text("Options")) {
			Toggle(isOn: flagBinding(MeshBeaconFlags.listenEnabled)) {
				Label("Listen for Beacons", systemImage: "antenna.radiowaves.left.and.right")
				Text("Receive and act on MESH_BEACON_APP packets from other nodes so beaconed meshes appear in Nearby Meshes and the scan setup.")
			}
			.tint(.accentColor)

			Toggle(isOn: flagBinding(MeshBeaconFlags.broadcastEnabled)) {
				Label("Broadcast a Beacon", systemImage: "dot.radiowaves.right")
				Text("Periodically advertise this node's mesh so other people's discovery scans can find and join it.")
			}
			.tint(.accentColor)
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
				Text("Message must be \(MeshBeaconValidation.maxMessageBytes) bytes or fewer. Shorten it before saving.")
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
	}

	private var offeredSection: some View {
		Section(header: Text("Offered to Listeners"), footer: Text("What the beacon advertises. Leave empty to broadcast a text-only beacon.")) {
			HStack {
				Label("Channel", systemImage: "fibrechannel")
				TextField("Channel name", text: $offerChannelName)
					.multilineTextAlignment(.trailing)
					.autocorrectionDisabled()
			}
			pskField("Offered key", psk: $offerChannelPSK)
			regionPicker("Region", selection: $offerRegion)
			presetPicker("Preset", selection: $offerPreset)
		}
	}

	private var intervalSection: some View {
		Section(header: Text("Broadcast Interval")) {
			HStack {
				Label("Interval (seconds)", systemImage: "timer")
				TextField("Seconds", text: $intervalText)
					.keyboardType(.numberPad)
					.multilineTextAlignment(.trailing)
			}
			if !isIntervalValid {
				Text("Interval must be at least \(MeshBeaconValidation.minIntervalSecs) seconds (1 hour). Increase it before saving.")
					.font(.caption)
					.foregroundStyle(.red)
			} else {
				Text("How often to transmit a beacon. Firmware minimum is \(MeshBeaconValidation.minIntervalSecs) seconds.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	private var singleTargetSection: some View {
		Section(header: Text("Broadcast On"), footer: Text("The radio settings the beacon is transmitted on. Used only when no broadcast targets are added below.")) {
			HStack {
				Label("Channel", systemImage: "fibrechannel")
				TextField("Channel name", text: $onChannelName)
					.multilineTextAlignment(.trailing)
					.autocorrectionDisabled()
			}
			pskField("Transmit key", psk: $onChannelPSK)
			regionPicker("Region", selection: $onRegion)
			presetPicker("Preset", selection: $onPreset)
		}
	}

	private var broadcastTargetsSection: some View {
		Section(header: Text("Broadcast Targets"), footer: Text("Advanced: transmit one beacon per target, each on its own preset/region/channel. When empty, the single Broadcast On settings are used instead.")) {
			ForEach($targets) { $target in
				VStack(alignment: .leading, spacing: 6) {
					presetPicker("Preset", selection: $target.preset)
					regionPicker("Region", selection: $target.region)
					HStack {
						Label("Channel Index", systemImage: "number")
						Spacer()
						Picker("", selection: $target.channelIndex) {
							Text("Default").tag(Int32(-1))
							ForEach(0..<8) { idx in
								Text("\(idx)").tag(Int32(idx))
							}
						}
						.labelsHidden()
					}
				}
			}
			.onDelete { offsets in
				targets.remove(atOffsets: offsets)
				hasChanges = true
			}
			Button {
				targets.append(BroadcastTargetDraft())
				hasChanges = true
			} label: {
				Label("Add Target", systemImage: "plus.circle")
			}
		}
	}

	private var advancedSection: some View {
		Section(header: Text("Advanced")) {
			HStack {
				Label("Send As Node", systemImage: "person.crop.circle")
				TextField("Node number (0 = this node)", text: $sendAsNodeText)
					.keyboardType(.numberPad)
					.multilineTextAlignment(.trailing)
			}
			if !isSendAsNodeValid {
				Text("Enter a node number between 0 and \(UInt32.max). 0 uses this node.")
					.font(.caption)
					.foregroundStyle(.red)
			} else {
				Text("Spoof the sender of outgoing beacons. 0 uses this node. Remote admin may only set its own node number.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: - Reusable field builders

	@ViewBuilder
	private func pskField(_ label: String, psk: Binding<Data>) -> some View {
		HStack {
			Label(label, systemImage: "key")
			TextField("Base64 key", text: Binding(
				get: { psk.wrappedValue.base64EncodedString() },
				set: { newValue in
					if newValue.isEmpty {
						psk.wrappedValue = Data()
					} else if let decoded = Data(base64Encoded: newValue) {
						psk.wrappedValue = decoded
					}
				}
			))
			.multilineTextAlignment(.trailing)
			.autocorrectionDisabled()
			.textInputAutocapitalization(.never)
			.font(.caption.monospaced())
		}
	}

	@ViewBuilder
	private func regionPicker(_ label: String, selection: Binding<Int32>) -> some View {
		Picker(label, selection: selection) {
			ForEach(RegionCodes.allCases.filter { !$0.isHiddenFromPicker }) { region in
				Text(region.description).tag(Int32(region.rawValue))
			}
		}
	}

	@ViewBuilder
	private func presetPicker(_ label: String, selection: Binding<Int32>) -> some View {
		Picker(label, selection: selection) {
			Text("None").tag(Int32(-1))
			ForEach(ModemPresets.allCases) { preset in
				Text(preset.description).tag(Int32(preset.rawValue))
			}
		}
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
		offerRegion = config?.broadcastOfferRegion ?? 0
		offerPreset = config?.broadcastOfferPreset ?? -1
		onChannelName = config?.broadcastOnChannelName ?? ""
		onChannelPSK = config?.broadcastOnChannelPSK ?? Data()
		onRegion = config?.broadcastOnRegion ?? 0
		onPreset = config?.broadcastOnPreset ?? -1
		intervalText = String(config?.broadcastIntervalSecs ?? 3600)
		sendAsNodeText = String(config?.broadcastSendAsNode ?? 0)
		targets = (config?.broadcastTargets ?? []).map {
			BroadcastTargetDraft(preset: $0.preset, region: $0.region, channelIndex: $0.channelIndex)
		}
		hasChanges = false
	}

	/// Assemble the protobuf from the edit buffer for the admin write. `FLAG_LEGACY_SPLIT` and any
	/// other bits not exposed here ride along in `flags` unchanged (D4).
	private func buildConfig() -> ModuleConfig.MeshBeaconConfig {
		var config = ModuleConfig.MeshBeaconConfig()
		config.flags = UInt32(truncatingIfNeeded: flags)
		config.broadcastMessage = broadcastMessage

		if !offerChannelName.isEmpty {
			var settings = ChannelSettings()
			settings.name = offerChannelName
			settings.psk = offerChannelPSK
			config.broadcastOfferChannel = settings
		}
		if let region = Config.LoRaConfig.RegionCode(rawValue: Int(offerRegion)) {
			config.broadcastOfferRegion = region
		}
		if offerPreset >= 0, let preset = Config.LoRaConfig.ModemPreset(rawValue: Int(offerPreset)) {
			config.broadcastOfferPreset = preset
		}

		if !onChannelName.isEmpty {
			var settings = ChannelSettings()
			settings.name = onChannelName
			settings.psk = onChannelPSK
			config.broadcastOnChannel = settings
		}
		if let region = Config.LoRaConfig.RegionCode(rawValue: Int(onRegion)) {
			config.broadcastOnRegion = region
		}
		if onPreset >= 0, let preset = Config.LoRaConfig.ModemPreset(rawValue: Int(onPreset)) {
			config.broadcastOnPreset = preset
		}

		config.broadcastIntervalSecs = UInt32(truncatingIfNeeded: intervalValue)
		// Validated by isSendAsNodeValid before save; parse directly (no truncating wrap) and fall
		// back to 0 ("this node") for an empty field.
		config.broadcastSendAsNode = UInt32(sendAsNodeText) ?? 0

		config.broadcastTargets = targets.map { draft in
			var target = ModuleConfig.MeshBeaconConfig.BroadcastTarget()
			if draft.preset >= 0, let preset = Config.LoRaConfig.ModemPreset(rawValue: Int(draft.preset)) {
				target.preset = preset
			}
			if let region = Config.LoRaConfig.RegionCode(rawValue: Int(draft.region)) {
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
