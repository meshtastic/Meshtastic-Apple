//
//  SaveChannelQRCode.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/13/22.
//
import SwiftUI
@preconcurrency import SwiftData
import OSLog
import MeshtasticProtobufs

struct SaveChannelLinkData: Identifiable {
	let id = UUID()
	let data: String
	let add: Bool
}

struct SaveChannelQRCode: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context

	let channelSetLink: String
	@State var addChannels: Bool = false
	var accessoryManager: AccessoryManager

	@State private var channelLink: MeshtasticChannelURL?
	@State private var incomingChannels: [ChannelSettings] = []
	@State private var selectedChannelIndices = Set<Int>()
	@State private var currentChannelNames = Set<String>()
	@State private var currentChannelCount = 0
	@State private var loraChanges: [String] = []
	@State private var okToMQTT = false
	@State private var showError = false
	@State private var errorMessage = ""
	@State private var isSaving = false

	private var selectedIncomingChannels: [ChannelSettings] {
		incomingChannels.enumerated().compactMap { index, channel in
			selectedChannelIndices.contains(index) ? channel : nil
		}
	}

	private var canReplace: Bool {
		channelLink?.channelSet.hasLoraConfig == true
	}

	private var selectedTotal: Int {
		addChannels ? currentChannelCount + selectedChannelIndices.count : selectedChannelIndices.count
	}

	private var saveDisabled: Bool {
		channelLink == nil ||
		!accessoryManager.isConnected ||
		isSaving ||
		selectedChannelIndices.isEmpty ||
		selectedTotal > 8 ||
		(!addChannels && !canReplace)
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					header
					importModePicker
					channelSelection
					loraChangeSummary
					errorSummary
				}
				.padding()
			}
			.navigationTitle("Channel QR Code")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(String(localized: "Cancel", comment: "VoiceOver: dismiss the channel QR code sheet"))
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(isSaving ? "Saving" : "Save") {
						save()
					}
					.disabled(saveDisabled)
				}
			}
			.onAppear {
				loadChannelLink()
			}
			.onChange(of: addChannels) {
				if !addChannels && !canReplace {
					addChannels = true
					errorMessage = "This channel link does not include LoRa settings, so it can only add channels."
					showError = true
				}
				reselectChannels()
			}
		}
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(addChannels ? "Add Channels" : "Replace Channels")
				.font(.title2.bold())

			Text(
				addChannels ?
				"Selected channels will be appended to the connected radio. Existing channels and LoRa settings are preserved." :
				"Selected channels will replace the connected radio's channel list. LoRa settings from the QR code will be applied."
			)
			.foregroundStyle(.secondary)

			if !accessoryManager.isConnected {
				Label("Connect to a radio before saving.", systemImage: "antenna.radiowaves.left.and.right.slash")
					.foregroundStyle(.orange)
			}
		}
	}

	private var importModePicker: some View {
		VStack(alignment: .leading, spacing: 8) {
			Picker("Import Mode", selection: $addChannels) {
				Text("Replace").tag(false)
				Text("Add").tag(true)
			}
			.pickerStyle(.segmented)

			if addChannels {
				Text("\(selectedTotal) of 8 channel slots will be used.")
					.font(.callout)
					.foregroundStyle(selectedTotal > 8 ? .red : .secondary)
			} else if !canReplace {
				Text("Replace is unavailable because this link was shared as add-only.")
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
	}

	private var channelSelection: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Channels")
				.font(.headline)

			if incomingChannels.isEmpty {
				ContentUnavailableView("No Channels", systemImage: "qrcode", description: Text("This QR code did not contain channel settings."))
			} else {
				ForEach(Array(incomingChannels.enumerated()), id: \.offset) { index, channel in
					channelRow(index: index, channel: channel)
				}
			}
		}
	}

	@ViewBuilder
	private func channelRow(index: Int, channel: ChannelSettings) -> some View {
		let duplicate = addChannels && isDuplicate(channel)
		HStack(spacing: 12) {
			Toggle(isOn: Binding(
				get: { selectedChannelIndices.contains(index) },
				set: { selected in
					if selected {
						selectedChannelIndices.insert(index)
					} else if selectedChannelIndices.count > 1 {
						selectedChannelIndices.remove(index)
					}
				}
			)) {
				VStack(alignment: .leading, spacing: 3) {
					Text(channelTitle(channel, index: index))
						.font(.body.weight(.medium))
					Text(duplicate ? "Already on this radio" : encryptionDescription(channel))
						.font(.caption)
						.foregroundStyle(duplicate ? .orange : .secondary)
				}
			}
			.disabled(duplicate)
		}
		.padding()
		.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
	}

	@ViewBuilder
	private var loraChangeSummary: some View {
		if !addChannels && !loraChanges.isEmpty {
			VStack(alignment: .leading, spacing: 8) {
				Text("LoRa Changes")
					.font(.headline)
				ForEach(loraChanges, id: \.self) { change in
					Text("• \(change)")
						.font(.callout)
						.foregroundStyle(.orange)
				}
			}
			.padding()
			.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
		}
	}

	@ViewBuilder
	private var errorSummary: some View {
		if showError {
			Text(errorMessage)
				.font(.callout)
				.foregroundStyle(.red)
				.padding()
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
		}
	}

	private func loadChannelLink() {
		do {
			let parsed = try MeshtasticChannelURL.parse(channelSetLink, defaultAddChannels: addChannels)
			let current = currentRadioState()

			channelLink = parsed
			incomingChannels = parsed.channelSet.settings
			currentChannelNames = current.channelNames
			currentChannelCount = current.channelCount
			okToMQTT = current.loraConfig?.configOkToMqtt ?? false
			addChannels = parsed.addChannels || !parsed.channelSet.hasLoraConfig
			loraChanges = loraConfigChanges(current: current.loraConfig, incoming: parsed.channelSet)
			showError = false
			errorMessage = ""
			reselectChannels()
		} catch {
			channelLink = nil
			incomingChannels = []
			selectedChannelIndices = []
			errorMessage = error.localizedDescription
			showError = true
		}
	}

	private func reselectChannels() {
		let selectable = incomingChannels.indices.filter { index in
			!addChannels || !isDuplicate(incomingChannels[index])
		}
		let availableSlots = max(0, 8 - (addChannels ? currentChannelCount : 0))
		selectedChannelIndices = Set(selectable.prefix(availableSlots))

		let slotLimitMessage = "There are not enough free channel slots for every selected channel."
		if addChannels && selectable.count > availableSlots {
			errorMessage = slotLimitMessage
			showError = true
		} else if errorMessage == slotLimitMessage {
			errorMessage = ""
			showError = false
		}
	}

	private func save() {
		guard var channelSet = channelLink?.channelSet else {
			return
		}

		channelSet.settings = selectedIncomingChannels
		isSaving = true
		showError = false

		Task {
			do {
				try await accessoryManager.saveChannelSet(channelSet: channelSet, addChannels: addChannels, okToMQTT: okToMQTT)
				await MainActor.run {
					dismiss()
				}
			} catch {
				await MainActor.run {
					errorMessage = error.localizedDescription
					showError = true
					isSaving = false
				}
			}
		}
	}

	private func currentRadioState() -> (channelNames: Set<String>, channelCount: Int, loraConfig: Config.LoRaConfig?) {
		guard let activeDeviceNum = accessoryManager.activeDeviceNum else {
			return ([], 0, nil)
		}
		let activeNum = Int64(activeDeviceNum)

		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == activeNum }
		)

		do {
			guard let node = try context.fetch(descriptor).first else {
				return ([], 0, nil)
			}
			let channels = node.myInfo?.channels ?? []
			let names = Set(channels.compactMap { $0.name?.isEmpty == false ? $0.name : nil })
			return (names, channels.count, node.loRaConfig?.toProto())
		} catch {
			Logger.data.error("Failed to fetch current channel state: \(error.localizedDescription, privacy: .public)")
			return ([], 0, nil)
		}
	}

	private func loraConfigChanges(current: Config.LoRaConfig?, incoming: ChannelSet) -> [String] {
		guard incoming.hasLoraConfig else {
			return []
		}

		let newLoRaConfig = incoming.loraConfig
		let currentConfig = current ?? getDefaultLoRaConfig()
		var changes: [String] = []

		if currentConfig.hopLimit != newLoRaConfig.hopLimit {
			changes.append("Hop Limit: \(currentConfig.hopLimit) -> \(newLoRaConfig.hopLimit)")
		}
		if currentConfig.region != newLoRaConfig.region {
			let currentRegionDesc = RegionCodes(rawValue: Int(currentConfig.region.rawValue))?.description ?? "Unknown"
			let newRegionDesc = RegionCodes(rawValue: Int(newLoRaConfig.region.rawValue))?.description ?? "Unknown"
			changes.append("Region: \(currentRegionDesc) -> \(newRegionDesc)")
		}
		if currentConfig.modemPreset != newLoRaConfig.modemPreset {
			let currentPresetDesc = ModemPresets(rawValue: Int(currentConfig.modemPreset.rawValue))?.description ?? "Unknown"
			let newPresetDesc = ModemPresets(rawValue: Int(newLoRaConfig.modemPreset.rawValue))?.description ?? "Unknown"
			changes.append("Modem Preset: \(currentPresetDesc) -> \(newPresetDesc)")
		}
		if currentConfig.usePreset != newLoRaConfig.usePreset {
			changes.append("Use Preset: \(currentConfig.usePreset) -> \(newLoRaConfig.usePreset)")
		}
		if currentConfig.channelNum != newLoRaConfig.channelNum {
			changes.append("Channel Number: \(currentConfig.channelNum) -> \(newLoRaConfig.channelNum)")
		}
		if currentConfig.bandwidth != newLoRaConfig.bandwidth {
			changes.append("Bandwidth: \(currentConfig.bandwidth) -> \(newLoRaConfig.bandwidth)")
		}
		if currentConfig.codingRate != newLoRaConfig.codingRate {
			changes.append("Coding Rate: \(currentConfig.codingRate) -> \(newLoRaConfig.codingRate)")
		}
		if currentConfig.spreadFactor != newLoRaConfig.spreadFactor {
			changes.append("Spread Factor: \(currentConfig.spreadFactor) -> \(newLoRaConfig.spreadFactor)")
		}
		if currentConfig.sx126XRxBoostedGain != newLoRaConfig.sx126XRxBoostedGain {
			changes.append("RX Boosted Gain: \(currentConfig.sx126XRxBoostedGain) -> \(newLoRaConfig.sx126XRxBoostedGain)")
		}
		if currentConfig.overrideFrequency != newLoRaConfig.overrideFrequency {
			changes.append("Override Frequency: \(currentConfig.overrideFrequency) -> \(newLoRaConfig.overrideFrequency)")
		}
		if currentConfig.ignoreMqtt != newLoRaConfig.ignoreMqtt {
			changes.append("Ignore MQTT: \(currentConfig.ignoreMqtt) -> \(newLoRaConfig.ignoreMqtt)")
		}

		return changes
	}

	private func getDefaultLoRaConfig() -> Config.LoRaConfig {
		var config = Config.LoRaConfig()
		config.hopLimit = 3
		config.region = .unset
		config.modemPreset = .longFast
		config.usePreset = true
		config.txEnabled = true
		config.txPower = 0
		config.channelNum = 0
		config.bandwidth = 0
		config.codingRate = 0
		config.spreadFactor = 0
		config.sx126XRxBoostedGain = false
		config.overrideFrequency = 0.0
		config.ignoreMqtt = false
		config.configOkToMqtt = false
		return config
	}

	private func isDuplicate(_ channel: ChannelSettings) -> Bool {
		guard !channel.name.isEmpty else {
			return false
		}
		return currentChannelNames.contains(channel.name)
	}

	private func channelTitle(_ channel: ChannelSettings, index: Int) -> String {
		if !channel.name.isEmpty {
			return channel.name
		}
		return index == 0 ? "Primary" : "Channel \(index)"
	}

	private func encryptionDescription(_ channel: ChannelSettings) -> String {
		channel.psk.count < 3 ? "Unencrypted" : "Encrypted"
	}
}

extension LoRaConfigEntity {
	func toProto() -> Config.LoRaConfig {
		var config = Config.LoRaConfig()
		config.hopLimit = UInt32(self.hopLimit)
		config.region = Config.LoRaConfig.RegionCode(rawValue: Int(self.regionCode)) ?? .unset
		config.modemPreset = Config.LoRaConfig.ModemPreset(rawValue: Int(self.modemPreset)) ?? .longFast
		config.usePreset = self.usePreset
		config.txEnabled = self.txEnabled
		config.txPower = Int32(self.txPower)
		config.channelNum = UInt32(self.channelNum)
		config.bandwidth = UInt32(self.bandwidth)
		config.codingRate = UInt32(self.codingRate)
		config.spreadFactor = UInt32(self.spreadFactor)
		config.sx126XRxBoostedGain = self.sx126xRxBoostedGain
		config.overrideFrequency = self.overrideFrequency
		config.ignoreMqtt = self.ignoreMqtt
		config.configOkToMqtt = self.okToMqtt
		return config
	}
}
