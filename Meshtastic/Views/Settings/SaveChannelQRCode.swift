//
//  SaveChannelQRCode.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/13/22.
//
import SwiftUI
import CoreData
import OSLog
import MeshtasticProtobufs

struct SaveChannelQRCode: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.managedObjectContext) var context
	let channelSetLink: String
	var addChannels: Bool = false
	var accessoryManager: AccessoryManager

	@State private var showError: Bool = false
	@State private var errorMessage: String = ""
	@State private var connectedToDevice: Bool = false
	@State private var loraChanges: [String] = []
	@State private var okToMQTT: Bool = false
	var body: some View {
		VStack {
			Text("\(addChannels ? "Add" : "Replace all") Channels?")
				.font(.title)
			Text("These settings will \(addChannels ? "add" : "replace all") channels. The current LoRa Config will be replaced, if there are substantial changes to the LoRa config the device will reboot")
				.fixedSize(horizontal: false, vertical: true)
				.foregroundColor(.gray)
				.font(.title3)
				.padding()

			if !loraChanges.isEmpty {
				VStack(alignment: .leading) {
					Text("LoRa Config Changes:")
						.font(.headline)
						.padding(.bottom, 5)
					ForEach(loraChanges, id: \.self) { change in
						Text("• \(change)")
							.font(.callout)
							.foregroundColor(.orange)
					}
				}
				.padding()
			}
			if showError {
				Text(errorMessage.isEmpty ? "Channels being added from the QR code did not save. When adding channels the names must be unique." : errorMessage)
					.fixedSize(horizontal: false, vertical: true)
					.foregroundColor(.red)
					.font(.callout)
					.padding()
			}
			HStack {
				if !showError {
					Button {
						// Extract channel data if it's a full URL
						let channelData: String
						if channelSetLink.hasPrefix("http") || channelSetLink.hasPrefix("meshtastic://") {
							guard let extractedData = extractChannelDataFromURL(channelSetLink) else {
								Logger.data.error("Failed to extract channel data from URL during save: \(channelSetLink)")
								errorMessage = "Invalid channel URL format"
								showError = true
								return
							}
							channelData = extractedData
						} else {
							channelData = channelSetLink
						}

						Task {
							do {
								try await accessoryManager.saveChannelSet(base64UrlString: channelData, addChannels: addChannels, okToMQTT: okToMQTT)
								Task { @MainActor in
									dismiss()
								}
							} catch {
								Task { @MainActor in
									errorMessage = "Failed to save channel configuration"
									showError = true
								}
							}
						}
					} label: {
						Label("Save", systemImage: "square.and.arrow.down")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding()
					.disabled(!connectedToDevice)

					#if targetEnvironment(macCatalyst)
					Button {
						dismiss()
					} label: {
						Label("Cancel", systemImage: "xmark")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding()
					#endif
				} else {
					Button {
						dismiss()
					} label: {
						Label("Cancel", systemImage: "xmark")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding()
				}
			}
		}
		.onAppear {
			Logger.data.info("Ch set link \(channelSetLink)")
			connectedToDevice = accessoryManager.connectToPreferredDevice()
			fetchLoRaConfigChanges()
		}
	}
	private func extractChannelDataFromURL(_ urlString: String) -> String? {
		Logger.data.info("Extracting channel data from URL: \(urlString)")
		if let url = URL(string: urlString) {
			// Get the fragment (part after #)
			if let fragment = url.fragment, !fragment.isEmpty {
				Logger.data.info("Extracted fragment from URL: \(fragment)")
				return fragment
			}
		}
		// Fallback: manually extract everything after the last #
		if let hashIndex = urlString.lastIndex(of: "#") {
			let startIndex = urlString.index(after: hashIndex)
			let channelData = String(urlString[startIndex...])
			if !channelData.isEmpty {
				Logger.data.info("Extracted channel data manually: \(channelData)")
				return channelData
			}
		}
		Logger.data.error("Failed to extract channel data from URL: \(urlString)")
		return nil
	}
	private func fetchLoRaConfigChanges() {
		var currentLoRaConfig: Config.LoRaConfig?

		// First, extract the actual channel data from the URL if it's a full URL
		let channelData: String
		if channelSetLink.hasPrefix("http") || channelSetLink.hasPrefix("meshtastic://") {
			guard let extractedData = extractChannelDataFromURL(channelSetLink) else {
				Logger.data.error("Failed to extract channel data from URL: \(channelSetLink)")
				errorMessage = "Invalid channel URL format"
				showError = true
				return
			}
			channelData = extractedData
		} else {
			// Assume it's already the base64 data
			channelData = channelSetLink
		}
		Logger.data.info("Processing channel data: \(channelData)")
		// Fetch current LoRa config from Core Data
		let fetchRequest = NodeInfoEntity.fetchRequest()
		fetchRequest.predicate = NSPredicate(format: "num == %lld", Int64(accessoryManager.activeDeviceNum ?? 0))

		do {
			let nodes = try context.fetch(fetchRequest)
			if let node = nodes.first {
				currentLoRaConfig = node.loRaConfig?.toProto()
			}
		} catch {
			Logger.data.error("Failed to fetch NodeInfoEntity: \(error.localizedDescription, privacy: .public)")
		}
		// Decode base64url string
		let decodedString = channelData.base64urlToBase64()
		guard let decodedData = Data(base64Encoded: decodedString) else {
			Logger.data.error("Invalid base64 for ChannelSet data: \(channelData, privacy: .public)")
			errorMessage = "Invalid channel data format"
			showError = true
			return
		}
		do {
			let channelSet = try ChannelSet(serializedBytes: decodedData)
			let newLoRaConfig = channelSet.loraConfig
			var changes: [String] = []

			// Preserve user's current okToMQTT setting
			okToMQTT = currentLoRaConfig?.configOkToMqtt ?? false

			if let current = currentLoRaConfig {
				// Compare each field and track changes
				if current.hopLimit != newLoRaConfig.hopLimit {
					changes.append("Hop Limit: \(current.hopLimit) -> \(newLoRaConfig.hopLimit)")
				}
				if current.region != newLoRaConfig.region {
					let currentRegionDesc = RegionCodes(rawValue: Int(current.region.rawValue))?.description ?? "Unknown"
					let newRegionDesc = RegionCodes(rawValue: Int(newLoRaConfig.region.rawValue))?.description ?? "Unknown"
					changes.append("Region: \(currentRegionDesc) -> \(newRegionDesc)")
				}
				if current.modemPreset != newLoRaConfig.modemPreset {
					let currentPresetDesc = ModemPresets(rawValue: Int(current.modemPreset.rawValue))?.description ?? "Unknown"
					let newPresetDesc = ModemPresets(rawValue: Int(newLoRaConfig.modemPreset.rawValue))?.description ?? "Unknown"
					changes.append("Modem Preset: \(currentPresetDesc) -> \(newPresetDesc)")
				}
				if current.usePreset != newLoRaConfig.usePreset {
					changes.append("Use Preset: \(current.usePreset) -> \(newLoRaConfig.usePreset)")
				}
				if current.txEnabled != newLoRaConfig.txEnabled {
					changes.append("Transmit Enabled: \(current.txEnabled) -> \(newLoRaConfig.txEnabled)")
				}
				if current.txPower != newLoRaConfig.txPower {
					changes.append("Transmit Power: \(current.txPower)dBm -> \(newLoRaConfig.txPower)dBm")
				}
				if current.channelNum != newLoRaConfig.channelNum {
					changes.append("Channel Number: \(current.channelNum) -> \(newLoRaConfig.channelNum)")
				}
				if current.bandwidth != newLoRaConfig.bandwidth {
					changes.append("Bandwidth: \(current.bandwidth) -> \(newLoRaConfig.bandwidth)")
				}
				if current.codingRate != newLoRaConfig.codingRate {
					changes.append("Coding Rate: \(current.codingRate) -> \(newLoRaConfig.codingRate)")
				}
				if current.spreadFactor != newLoRaConfig.spreadFactor {
					changes.append("Spread Factor: \(current.spreadFactor) -> \(newLoRaConfig.spreadFactor)")
				}
				if current.sx126XRxBoostedGain != newLoRaConfig.sx126XRxBoostedGain {
					changes.append("RX Boosted Gain: \(current.sx126XRxBoostedGain) -> \(newLoRaConfig.sx126XRxBoostedGain)")
				}
				if current.overrideFrequency != newLoRaConfig.overrideFrequency {
					changes.append("Override Frequency: \(current.overrideFrequency) -> \(newLoRaConfig.overrideFrequency)")
				}
				if current.ignoreMqtt != newLoRaConfig.ignoreMqtt {
					changes.append("Ignore MQTT: \(current.ignoreMqtt) -> \(newLoRaConfig.ignoreMqtt)")
				}
			} else {
				// Compare against default values when no current config exists
				let defaultConfig = getDefaultLoRaConfig()
				if newLoRaConfig.hopLimit != defaultConfig.hopLimit {
					changes.append("Hop Limit: \(defaultConfig.hopLimit) -> \(newLoRaConfig.hopLimit)")
				}
				if newLoRaConfig.region != defaultConfig.region {
					let newRegionDesc = RegionCodes(rawValue: Int(newLoRaConfig.region.rawValue))?.description ?? "Unknown"
					changes.append("Region: Unset -> \(newRegionDesc)")
				}
				if newLoRaConfig.modemPreset != defaultConfig.modemPreset {
					let newPresetDesc = ModemPresets(rawValue: Int(newLoRaConfig.modemPreset.rawValue))?.description ?? "Unknown"
					changes.append("Modem Preset: Long Fast -> \(newPresetDesc)")
				}
				if newLoRaConfig.usePreset != defaultConfig.usePreset {
					changes.append("Use Preset: \(defaultConfig.usePreset) -> \(newLoRaConfig.usePreset)")
				}
				if newLoRaConfig.txEnabled != defaultConfig.txEnabled {
					changes.append("Transmit Enabled: \(defaultConfig.txEnabled) -> \(newLoRaConfig.txEnabled)")
				}
				if newLoRaConfig.txPower != defaultConfig.txPower {
					changes.append("Transmit Power: \(defaultConfig.txPower)dBm -> \(newLoRaConfig.txPower)dBm")
				}
				if newLoRaConfig.channelNum != defaultConfig.channelNum {
					changes.append("Channel Number: \(defaultConfig.channelNum) -> \(newLoRaConfig.channelNum)")
				}
				if newLoRaConfig.bandwidth != defaultConfig.bandwidth {
					changes.append("Bandwidth: \(defaultConfig.bandwidth) -> \(newLoRaConfig.bandwidth)")
				}
				if newLoRaConfig.codingRate != defaultConfig.codingRate {
					changes.append("Coding Rate: \(defaultConfig.codingRate) -> \(newLoRaConfig.codingRate)")
				}
				if newLoRaConfig.spreadFactor != defaultConfig.spreadFactor {
					changes.append("Spread Factor: \(defaultConfig.spreadFactor) -> \(newLoRaConfig.spreadFactor)")
				}
				if newLoRaConfig.sx126XRxBoostedGain != defaultConfig.sx126XRxBoostedGain {
					changes.append("RX Boosted Gain: \(defaultConfig.sx126XRxBoostedGain) -> \(newLoRaConfig.sx126XRxBoostedGain)")
				}
				if newLoRaConfig.overrideFrequency != defaultConfig.overrideFrequency {
					changes.append("Override Frequency: \(defaultConfig.overrideFrequency) -> \(newLoRaConfig.overrideFrequency)")
				}
				if newLoRaConfig.ignoreMqtt != defaultConfig.ignoreMqtt {
					changes.append("Ignore MQTT: \(defaultConfig.ignoreMqtt) -> \(newLoRaConfig.ignoreMqtt)")
				}
			}
			loraChanges = changes
		} catch {
			Logger.data.error("Failed to decode ChannelSet: \(error.localizedDescription, privacy: .public)")
			errorMessage = "Failed to decode channel configuration"
			showError = true
		}
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
