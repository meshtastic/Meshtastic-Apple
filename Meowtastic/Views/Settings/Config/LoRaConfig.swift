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
	@EnvironmentObject var bleManager: BLEManager
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

	let floatFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		return formatter
	}()

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "LoRa", config: \.loRaConfig, node: node)

				Section(header: Text("Options")) {

					VStack(alignment: .leading) {
						Picker("Region", selection: $region ) {
							ForEach(RegionCodes.allCases) { r in
								Text(r.description)
							}
						}
						.fixedSize()
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
								.toolbar {
									ToolbarItemGroup(placement: .keyboard) {
										Button("dismiss.keyboard") {
											focusedField = nil
										}
										.font(.subheadline)
									}
								}
								.keyboardType(.decimalPad)
								.scrollDismissesKeyboard(.immediately)
								.focused($focusedField, equals: .channelNum)
								.disabled(overrideFrequency > 0.0)
						}
						Text("This determines the actual frequency you are transmitting on in the band. If set to 0 this value will be calculated automatically based on the primary channel name.")
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
							.scrollDismissesKeyboard(.immediately)
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
			.disabled(self.bleManager.connectedPeripheral == nil || node?.loRaConfig == nil)

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? 0, context: context)
				if connectedNode != nil {
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
					if connectedNode?.num ?? -1 == node?.user?.num ?? 0 {
						UserDefaults.modemPreset = modemPreset
					}
					let adminMessageId = bleManager.saveLoRaConfig(config: lc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
		}
		.navigationTitle("lora.config")
		.navigationBarItems(
			trailing: ConnectedDevice(ble: bleManager)
		)
		.onAppear {
			setLoRaValues()
			// Need to request a LoRaConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.loRaConfig == nil {
				Logger.mesh.info("empty lora config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestLoRaConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: region) { newRegion in
			if node != nil && node!.loRaConfig != nil {
				if newRegion != node!.loRaConfig!.regionCode { hasChanges = true }
			}
		}
		.onChange(of: usePreset) { newUsePreset in
			if node != nil && node!.loRaConfig != nil {
				if newUsePreset != node!.loRaConfig!.usePreset { hasChanges = true }
			}
		}
		.onChange(of: modemPreset) { newModemPreset in
			if node != nil && node!.loRaConfig != nil {
				if newModemPreset != node!.loRaConfig!.modemPreset { hasChanges = true }
			}
		}
		.onChange(of: hopLimit) { newHopLimit in
			if node != nil && node!.loRaConfig != nil {
				if newHopLimit != node!.loRaConfig!.hopLimit { hasChanges = true }
			}
		}
		.onChange(of: channelNum) { newChannelNum in
			if node != nil && node!.loRaConfig != nil {
				if newChannelNum != node!.loRaConfig!.channelNum { hasChanges = true }
			}
		}
		.onChange(of: bandwidth) { newBandwidth in
			if node != nil && node!.loRaConfig != nil {
				if newBandwidth != node!.loRaConfig!.bandwidth { hasChanges = true }
			}
		}
		.onChange(of: codingRate) { newCodingRate in
			if node != nil && node!.loRaConfig != nil {
				if newCodingRate != node!.loRaConfig!.codingRate { hasChanges = true }
			}
		}
		.onChange(of: spreadFactor) { newSpreadFactor in
			if node != nil && node!.loRaConfig != nil {
				if newSpreadFactor != node!.loRaConfig!.spreadFactor { hasChanges = true }
			}
		}
		.onChange(of: rxBoostedGain) { newRxBoostedGain in
			if node != nil && node!.loRaConfig != nil {
				if newRxBoostedGain != node!.loRaConfig!.sx126xRxBoostedGain { hasChanges = true }
			}
		}
		.onChange(of: overrideFrequency) { newOverrideFrequency in
			if node != nil && node!.loRaConfig != nil {
				if newOverrideFrequency != node!.loRaConfig!.overrideFrequency { hasChanges = true }
			}
		}
		.onChange(of: txPower) { newTxPower in
			if node != nil && node!.loRaConfig != nil {
				if newTxPower != node!.loRaConfig!.txPower { hasChanges = true }
			}
		}
		.onChange(of: txEnabled) { newTxEnabled in
			if node != nil && node!.loRaConfig != nil {
				if newTxEnabled != node!.loRaConfig!.txEnabled { hasChanges = true }
			}
		}
		.onChange(of: ignoreMqtt) { newIgnoreMqtt in
			if node != nil && node!.loRaConfig != nil {
				if newIgnoreMqtt != node!.loRaConfig!.ignoreMqtt { hasChanges = true }
			}
		}
	}
	func setLoRaValues() {
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
		self.hasChanges = false
	}
}
