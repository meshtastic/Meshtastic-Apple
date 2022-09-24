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
	
	var node: NodeInfoEntity?
	
	@State var isPresentingSaveConfirm = false
	@State var initialLoad = true
	@State var hasChanges = false
	
	@State var region = 0
	@State var modemPreset  = 0
	@State var hopLimit  = 0
	@State var txPower  = 0
	@State var txEnabled = true
	@State var usePreset = true
	
	var body: some View {
		
		VStack {

			Form {
				Section(header: Text("Region")) {
					
					Picker("Region", selection: $region ) {
						ForEach(RegionCodes.allCases) { r in
							Text(r.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("The region where you will be using your radios.")
						.font(.caption)
				}
				Section(header: Text("Modem")) {
					Picker("Presets", selection: $modemPreset ) {
						ForEach(ModemPresets.allCases) { m in
							Text(m.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Available modem presets, default is Long Fast.")
						.font(.caption)
				}
				Section(header: Text("Mesh Options")) {
					
					Picker("Number of hops", selection: $hopLimit) {
						ForEach(HopValues.allCases) { hop in
							Text(hop.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Sets the maximum number of hops, default is 3. Increasing hops also increases air time utilization and should be used carefully.")
						.font(.caption)
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil)
			
			Button {
							
				isPresentingSaveConfirm = true
				
			} label: {
				
				Label("Save", systemImage: "square.and.arrow.down")
			}
			.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.confirmationDialog(
				
				"Are you sure you want to save?",
				isPresented: $isPresentingSaveConfirm,
				titleVisibility: .visible
			) {
				Button("Save Config for \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")") {
					
					var lc = Config.LoRaConfig()
					lc.hopLimit = UInt32(hopLimit)
					lc.region = RegionCodes(rawValue: region)!.protoEnumValue()
					lc.modemPreset = ModemPresets(rawValue: modemPreset)!.protoEnumValue()
					
					let adminMessageId = bleManager.saveLoRaConfig(config: lc, fromUser: node!.user!, toUser: node!.user!)
					
					if adminMessageId > 0 {
						
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						
					} else {
						
					}
				}
				
			} message: {
				
				Text("After LoRa config saves the node will reboot.")
			}
		}
		.navigationTitle("LoRa Config")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			
			self.bleManager.context = context

			if self.initialLoad{
				
			
				self.hopLimit = Int(node!.loRaConfig?.hopLimit ?? 0)
				self.region = Int(node!.loRaConfig?.regionCode ?? 0)
				self.usePreset = node!.loRaConfig?.usePreset ?? true
				self.modemPreset = Int(node!.loRaConfig?.modemPreset ?? 0)
				self.txEnabled = node!.loRaConfig?.txEnabled ?? true
				self.txPower = Int(node!.loRaConfig?.txPower ?? 0)
				
				self.hasChanges = false
				self.initialLoad = false
			}
		}
		.onChange(of: region) { newRegion in
			
			if node != nil && node!.loRaConfig != nil {
				
				if newRegion != node!.loRaConfig!.regionCode { hasChanges = true }
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
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
