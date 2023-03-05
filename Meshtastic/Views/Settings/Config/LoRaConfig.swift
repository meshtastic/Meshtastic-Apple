//
//  LoRaConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) by Garth Vander Houwen 6/11/22.
//

import SwiftUI

struct LoRaConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack
	
	var node: NodeInfoEntity?
	
	@State var isPresentingSaveConfirm = false
	@State var hasChanges = false
	@State var region = 0
	@State var modemPreset  = 0
	@State var hopLimit  = 0
	@State var txPower  = 0
	@State var txEnabled = true
	@State var usePreset = true
	@State var channelNum  = 0
	
	var body: some View {
		
		VStack {
			Form {
				Section(header: Text("Options")) {

					
					Picker("Region", selection: $region ) {
						ForEach(RegionCodes.allCases) { r in
							Text(r.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
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
						Grid {
							GridRow {
								Text("Bandwidth")
									.font(.caption)
								Text(String(node?.loRaConfig?.bandwidth ?? 0))
									.font(.caption)
							}
							GridRow {
								Text("Spread Factor")
									.font(.caption)
								Text(String(node?.loRaConfig?.spreadFactor ?? 0))
									.font(.caption)
							}
							GridRow {
								Text("Coding Rate")
									.font(.caption)
								Text(String(node?.loRaConfig?.codingRate ?? 0))
									.font(.caption)
							}
							GridRow {
								Text("Frequency Offset")
									.font(.caption)
								Text(String(node?.loRaConfig?.frequencyOffset ?? 0))
									.font(.caption)
							}
						}
					}

					Picker("Number of hops", selection: $hopLimit) {
						Text("Please Select")
							.tag(0)
						ForEach(HopValues.allCases) { hop in
							Text(hop.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Sets the maximum number of hops, default is 3. Increasing hops also increases air time utilization and should be used carefully.")
						.font(.caption)
					Picker("Channel Number", selection: $channelNum) {
						ForEach(0..<9) {
							if $0 == 0 {
								Text("Automatic")
							} else {
								Text("Channel \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("A hash of the primary channel's name sets the LoRa channel number, this determines the actual frequency you are transmitting on in the band. To ensure devices with different primary channel names transmit on the same frequency, you must explicitly set the LoRa channel number.")
						.font(.caption)
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
				let nodeName = node?.user?.longName ?? NSLocalizedString("unknown", comment: "Unknown")
				let buttonText = String.localizedStringWithFormat(NSLocalizedString("save.config %@", comment: "Save Config for %@"), nodeName)
				Button(buttonText) {
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
					if connectedNode != nil {
						var lc = Config.LoRaConfig()
						lc.hopLimit = UInt32(hopLimit)
						lc.region = RegionCodes(rawValue: region)!.protoEnumValue()
						lc.modemPreset = ModemPresets(rawValue: modemPreset)!.protoEnumValue()
						lc.usePreset = usePreset
						lc.txEnabled = txEnabled
						lc.channelNum = UInt32(channelNum)
						let adminMessageId = bleManager.saveLoRaConfig(config: lc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: node?.myInfo?.adminIndex ?? 0)
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
			self.hopLimit = Int(node?.loRaConfig?.hopLimit ?? 3)
			self.region = Int(node?.loRaConfig?.regionCode ?? 0)
			self.usePreset = node?.loRaConfig?.usePreset ?? true
			self.modemPreset = Int(node?.loRaConfig?.modemPreset ?? 0)
			self.txEnabled = node?.loRaConfig?.txEnabled ?? true
			self.txPower = Int(node?.loRaConfig?.txPower ?? 0)
			self.channelNum = Int(node?.loRaConfig?.channelNum ?? 0)
			self.hasChanges = false
			
			// Need to request a LoRaConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.loRaConfig == nil {
				print("empty lora config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if connectedNode != nil && connectedNode!.num > 0 {
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
	}
}
