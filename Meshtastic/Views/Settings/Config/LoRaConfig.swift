//
//  LoRaConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) by Garth Vander Houwen 6/11/22.
//

import SwiftUI
import CoreData

struct LoRaConfig: View {

	enum Field: Hashable {
		case channelNum
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

	@State var isPresentingSaveConfirm = false
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

	var body: some View {

		VStack {
			Form {
				if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					Text("There has been no response to a request for device metadata over the admin channel for this node.")
						.font(.callout)
						.foregroundColor(.orange)

				} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					// Let users know what is going on if they are using remote admin and don't have the config yet
					if node?.loRaConfig == nil {
						Text("LoRa config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
							.font(.callout)
							.foregroundColor(.orange)
					} else {
						Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
							.font(.title3)
							.onAppear {
								setLoRaValues()
							}
					}
				} else if node != nil && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? 0 {
					Text("Configuration for: \(node?.user?.longName ?? "Unknown")")
						.font(.title3)
				} else {
					Text("Please connect to a radio to configure settings.")
						.font(.callout)
						.foregroundColor(.orange)
				}
				Section(header: Text("Options")) {

					Picker("Region", selection: $region ) {
						ForEach(RegionCodes.allCases) { r in
							Text(r.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.fixedSize()

					Text("The region where you will be using your radios.")
						.font(.caption)

					Toggle(isOn: $usePreset) {
						Label("Use Preset", systemImage: "list.bullet.rectangle")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					if usePreset {
						Picker("Presets", selection: $modemPreset ) {
							ForEach(ModemPresets.allCases) { m in
								Text(m.description)
							}
						}
						.pickerStyle(DefaultPickerStyle())
						.fixedSize()
						Text("Available modem presets, default is Long Fast.")
							.font(.caption)
					}
				}
				Section(header: Text("Advanced")) {

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

					Picker("Number of hops", selection: $hopLimit) {
						ForEach(1..<8) {
							Text("\($0)")
								.tag($0 == 0 ? 3 : $0)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Sets the maximum number of hops, default is 3. Increasing hops also increases congestion and should be used carefully.")
						.font(.caption)

					HStack {
						Text("LoRa Channel Number")
							.fixedSize()
						TextField("Channel Number", value: $channelNum, formatter: formatter)
							.multilineTextAlignment(.trailing)
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
					}
					Text("This determines the actual frequency you are transmitting on in the band.")
						.font(.caption)
					Toggle(isOn: $rxBoostedGain) {
						Label("RX Boosted Gain", systemImage: "waveform.badge.plus")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.loRaConfig == nil)

			Button {
				isPresentingSaveConfirm = true
			} label: {
				Label("save", systemImage: "square.and.arrow.down")
			}
			.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.confirmationDialog(
				"are.you.sure",
				isPresented: $isPresentingSaveConfirm,
				titleVisibility: .visible
			) {
				let nodeName = node?.user?.longName ?? "unknown".localized
				let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
				Button(buttonText) {
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? 0, context: context)
					if connectedNode != nil {
						var lc = Config.LoRaConfig()
						lc.hopLimit = UInt32(hopLimit)
						lc.region = RegionCodes(rawValue: region)!.protoEnumValue()
						lc.modemPreset = ModemPresets(rawValue: modemPreset)!.protoEnumValue()
						lc.usePreset = usePreset
						lc.txEnabled = txEnabled
						lc.channelNum = UInt32(channelNum)
						lc.bandwidth = UInt32(bandwidth)
						lc.codingRate = UInt32(codingRate)
						lc.spreadFactor = UInt32(spreadFactor)
						lc.sx126XRxBoostedGain = rxBoostedGain
						let adminMessageId = bleManager.saveLoRaConfig(config: lc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
						if adminMessageId > 0 {
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasChanges = false
							goBack()
						}
					}
				}
			} message: {
				Text("config.save.confirm")
			}
		}
		.navigationTitle("lora.config")
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {

			self.bleManager.context = context
			setLoRaValues()

			// Need to request a LoRaConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.loRaConfig == nil {
				print("empty lora config")
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
		self.hasChanges = false
	}
}
