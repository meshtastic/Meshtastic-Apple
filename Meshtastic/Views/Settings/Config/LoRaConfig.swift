//
//  LoRaConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) by Garth Vander Houwen 6/11/22.
//

import SwiftUI
import CoreData
import MeshtasticProtobufs
import OSLog

struct LoRaConfig: View {

	enum Field: Hashable {
		case channelNum
		case frequencyOverride
	}

	let formatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.groupingSeparator = ""
		return formatter
	}()

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	@FocusState var focusedField: Field?

	var node: NodeInfoEntity?

	@State var hasChanges = false
	@State var region: Int = 0
	@State var modemPreset = 0
	@State var hopLimit = 3
	@State var txPower = 0
	@State var txEnabled = true
	@State var usePreset = true
	@State var channelNum = 0
	@State var bandwidth = 0
	@State var spreadFactor = 0
	@State var codingRate = 0
	@State var rxBoostedGain = false
	@State var overrideFrequency: Float = 0.0
	@State var ignoreMqtt = false
	@State var okToMqtt = false

	let floatFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.allowsFloats = true
		formatter.maximumFractionDigits = 4
		return formatter
	}()

	var body: some View {
		Form {
			ConfigHeader(title: "LoRa", config: \.loRaConfig, node: node, onAppear: setLoRaValues)

			Section(header: Text("Options")) {

				VStack(alignment: .leading) {
					Picker("Region", selection: $region ) {
						ForEach(RegionCodes.allCases) { r in
							Text(r.description)
						}
					}
					Text("The region where you will be using your radios.")
						.foregroundColor(.gray)
						.font(.callout)
				}
				.pickerStyle(DefaultPickerStyle())

				Toggle(isOn: $usePreset) {
					Label("Use Preset", systemImage: "list.bullet.rectangle")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))

				if usePreset {
					VStack(alignment: .leading) {
						Picker("Presets", selection: $modemPreset ) {
							ForEach(ModemPresets.allCases) { m in
								Text(m.description)
							}
						}
						.pickerStyle(DefaultPickerStyle())
						.fixedSize()
						Text("Available modem presets, default is Long Fast.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}
			}
			Section(header: Text("Advanced")) {

				Toggle(isOn: $ignoreMqtt) {
					Label("Ignore MQTT", systemImage: "server.rack")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Toggle(isOn: $okToMqtt) {
					Label("Ok to MQTT", systemImage: "network")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))

				Toggle(isOn: $txEnabled) {
					Label("Transmit Enabled", systemImage: "waveform.path")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))

				 if !usePreset {
					 HStack {
						 Picker("Bandwidth", selection: $bandwidth) {
							 ForEach(Bandwidths.allCases) { bw in
								 Text(bw.description)
									 .tag(bw.rawValue == 250 ? 0 : bw.rawValue)
							 }
						 }
					 }
					 HStack {
						 Picker("Spread Factor", selection: $spreadFactor) {
							 ForEach(7..<13) {
								 Text("\($0)")
									 .tag($0 == 12 ? 0 : $0)
							 }
						 }
					 }
					 HStack {
						 Picker("Coding Rate", selection: $codingRate) {
							 ForEach(5..<9) {
								 Text("\($0)")
									 .tag($0 == 8 ? 0 : $0)
							 }
						 }
					 }
				}
				VStack(alignment: .leading) {
					Picker("Number of hops", selection: $hopLimit) {
						ForEach(0..<8) {
							Text("\($0)")
								.tag($0)
						}
					}
					Text("Sets the maximum number of hops, default is 3. Increasing hops also increases congestion and should be used carefully. O hop broadcast messages will not get ACKs.")
						.foregroundColor(.gray)
						.font(.callout)
				}
				.pickerStyle(DefaultPickerStyle())

				VStack(alignment: .leading) {
					HStack {
						Text("Frequency Slot")
							.fixedSize()
						TextField("Frequency Slot", value: $channelNum, formatter: formatter)
							.keyboardType(.numberPad)
							.focused($focusedField, equals: .channelNum)
							.disabled(overrideFrequency > 0.0)
					}
					Text("Your node’s operating frequency is calculated based on the region, modem preset, and this field. When 0, the slot is automatically calculated based on the primary channel name.")
						.foregroundColor(.gray)
						.font(.callout)
				}

				Toggle(isOn: $rxBoostedGain) {
					Label("RX Boosted Gain", systemImage: "waveform.badge.plus")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))

				HStack {
					Label("Frequency Override", systemImage: "waveform.path.ecg")
					Spacer()
					TextField("Frequency Override", value: $overrideFrequency, formatter: floatFormatter)
						.keyboardType(.decimalPad)
						.focused($focusedField, equals: .frequencyOverride)
				}

				HStack {
					Image(systemName: "antenna.radiowaves.left.and.right")
						.foregroundColor(.accentColor)
					Stepper("\(txPower)dBm Transmit Power", value: $txPower, in: 1...30, step: 1)
						.padding(5)
				}
			}
		}
		.backport.scrollDismissesKeyboard(.immediately)
		.disabled(!accessoryManager.isConnected || node?.loRaConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					if let deviceNum = accessoryManager.activeDeviceNum, let connectedNode = getNodeInfo(id: deviceNum, context: context) {
						var lc = Config.LoRaConfig()
						lc.hopLimit = UInt32(hopLimit)
						lc.region = RegionCodes(rawValue: region)!.protoEnumValue()
						lc.modemPreset = ModemPresets(rawValue: modemPreset)!.protoEnumValue()
						lc.usePreset = usePreset
						lc.txEnabled = txEnabled
						lc.txPower = Int32(txPower)
						lc.channelNum = UInt32(channelNum)
						lc.bandwidth = UInt32(bandwidth)
						lc.codingRate = UInt32(codingRate)
						lc.spreadFactor = UInt32(spreadFactor)
						lc.sx126XRxBoostedGain = rxBoostedGain
						lc.overrideFrequency = overrideFrequency
						lc.ignoreMqtt = ignoreMqtt
						lc.configOkToMqtt = okToMqtt
						if connectedNode.num == node?.user?.num ?? 0 {
							UserDefaults.modemPreset = modemPreset
						}
						Task {
							_ = try await accessoryManager.saveLoRaConfig(config: lc, fromUser: connectedNode.user!, toUser: node!.user!)
							Task { @MainActor in
								// Should show a saved successfully alert once I know that to be true
								// for now just disable the button after a successful save
								hasChanges = false
								goBack()
							}
						}
					}
				}
			}
		}
		.navigationTitle("LoRa Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")

			}
		)
		.onFirstAppear {
			// Need to request a LoRaConfig from the remote node before allowing changes
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				if let connectedNode = getNodeInfo(id: deviceNum, context: context) {
					if node.num != deviceNum {
						if UserDefaults.enableAdministration {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.loRaConfig == nil {
								Task {
									do {
										if connectedNode.user != nil && node.user != nil {
											Logger.mesh.info("⚙️ Empty or expired lora config requesting via PKI admin")
											_ = try await accessoryManager.requestLoRaConfig(fromUser: connectedNode.user!, toUser: node.user!)
										} else {
											Logger.mesh.info("🚫 No User or node for lora config request")
										}
									} catch {
										Logger.mesh.info("🚨 Lora config request failed")
									}
								}
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
						}
					}
				}
			}
		}
		.backport.onChange(of: region) { _, newRegion in
			if newRegion != node?.loRaConfig?.regionCode ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: usePreset) { _, newPreset in
			if newPreset != node?.loRaConfig?.usePreset { hasChanges = true }
		}
		.backport.onChange(of: modemPreset) { _, newModemPreset in
			if newModemPreset != node?.loRaConfig?.modemPreset ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: hopLimit) { _, newHopLimit in
			if newHopLimit != node?.loRaConfig?.hopLimit ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: channelNum) { _, newChannelNum in
			if newChannelNum != node?.loRaConfig?.channelNum ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: bandwidth) { _, newBandwidth in
			if newBandwidth != node?.loRaConfig?.bandwidth ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: codingRate) { _, newCodingRate in
			if newCodingRate != node?.loRaConfig?.codingRate ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: spreadFactor) { _, newSpreadFactor in
			if newSpreadFactor != node?.loRaConfig?.spreadFactor ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: rxBoostedGain) { _, newRxBoostedGain in
			if newRxBoostedGain != node?.loRaConfig?.sx126xRxBoostedGain { hasChanges = true }
		}
		.backport.onChange(of: overrideFrequency) { _, newOverrideFrequency in
			if newOverrideFrequency != node?.loRaConfig?.overrideFrequency { hasChanges = true }
		}
		.backport.onChange(of: txPower) { _, newTxPower in
			if newTxPower != node?.loRaConfig?.txPower ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: txEnabled) { _, newTxEnabled in
			if newTxEnabled != node?.loRaConfig?.txEnabled { hasChanges = true }
		}
		.backport.onChange(of: ignoreMqtt) { _, newIgnoreMqtt in
			if newIgnoreMqtt != node?.loRaConfig?.ignoreMqtt { hasChanges = true }
		}
		.backport.onChange(of: okToMqtt) { _, newOkToMqtt in
			if newOkToMqtt != node?.loRaConfig?.okToMqtt { hasChanges = true }
		}
	}
	func setLoRaValues() {
		if node?.loRaConfig?.modemPreset ?? 0 == 2 {
			node?.loRaConfig?.modemPreset = 0
		}
		self.hopLimit = Int(node?.loRaConfig?.hopLimit ?? 3)
		self.region = Int(node?.loRaConfig?.regionCode ?? 0)
		self.usePreset = node?.loRaConfig?.usePreset ?? true
		self.modemPreset = Int(node?.loRaConfig?.modemPreset ?? 0)
		self.txEnabled = node?.loRaConfig?.txEnabled ?? true
		self.txPower = Int(node?.loRaConfig?.txPower ?? 0)
		self.channelNum = Int(node?.loRaConfig?.channelNum ?? 0)
		self.bandwidth = Int(node?.loRaConfig?.bandwidth ?? 0)
		self.codingRate = Int(node?.loRaConfig?.codingRate ?? 0)
		self.spreadFactor = Int(node?.loRaConfig?.spreadFactor ?? 0)
		self.rxBoostedGain = node?.loRaConfig?.sx126xRxBoostedGain ?? false
		self.overrideFrequency = node?.loRaConfig?.overrideFrequency ?? 0.0
		self.ignoreMqtt = node?.loRaConfig?.ignoreMqtt ?? false
		self.okToMqtt = node?.loRaConfig?.okToMqtt ?? false
		self.hasChanges = false
	}
}
