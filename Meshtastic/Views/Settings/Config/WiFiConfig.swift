//
//  WiFiConfig.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 8/1/2022
//

import SwiftUI

struct WiFiConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var initialLoad: Bool = true
	@State var hasChanges: Bool = false

	@State var ssid = ""
	@State var password = ""
	
	@State var apMode = false
	@State var apHidden = false
	
	var body: some View {
		
		VStack {
			
			Text("Enabling WiFi will disable bluetooth, only one connection method works at a time. Saving these settings will disconnect your device from the app.")
				.font(.title3)
				.padding()

			Form {
				
				Section(header: Text("SSID & Password")) {
					

				}
				Section(header: Text("AP Settings")) {
					
					Toggle(isOn: $apMode) {

						Label("Soft AP Mode", systemImage: "wifi")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("If set the software access point mode will be activated.")
						.font(.caption)
					
					Toggle(isOn: $apHidden) {

						Label("Hidden AP", systemImage: "eye.slash")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("If set the SSID for the AP will be hidden.")
						.font(.caption)
					
				}
			}
			.disabled(bleManager.connectedPeripheral == nil)
			
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
				
				"Are you sure?",
				isPresented: $isPresentingSaveConfirm
			) {
				Button("Save WiFI Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
					
					var wifi = Config.WiFiConfig()
					wifi.ssid = ssid
					wifi.psk = password
					wifi.apMode = apMode
					wifi.apHidden = apHidden
					
					//let adminMessageId =  bleManager.saveWiFiConfig(config: wiFi, fromUser: node!.user!, toUser: node!.user!, wantResponse: true)
					let adminMessageId = 0
					if adminMessageId > 0 {
						
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						
					} else {
						
					}
				}
			}
		}
		.navigationTitle("WiFi Config")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {

			if self.initialLoad{
				
				self.bleManager.context = context

				self.ssid = node!.wiFiConfig?.ssid ?? ""
				self.password = node!.wiFiConfig?.password ?? ""
				self.apMode = (node!.wiFiConfig?.apMode ?? false)
				self.apHidden = (node!.wiFiConfig?.apHidden ?? false)
				
				self.hasChanges = false
				self.initialLoad = false
			}
		}
		.onChange(of: ssid) { newSsid in
			
			hasChanges = true
			//if node != nil && node!.wiFiConfig != nil {  newSsid != node!.wiFiConfig.ssid { hasChanges = true }}
		}
		.onChange(of: password) { newPassword in
			
			hasChanges = true
			//if node != nil && node!.wiFiConfig != nil {  newPassword != node!.wiFiConfig!.password { hasChanges = true }}
		}
		.onChange(of: apMode) { newAPMode in
			
			hasChanges = true
			//if node != nil && node!.wiFiConfig != nil {  newAPMode != node!.wiFiConfig!.apMode { self.hasChanges = true }}
		}
		.onChange(of: apHidden) { newAPHidden in
			
			hasChanges = true
			//if node != nil && node!.wiFiConfig != nil {  newAPHidden != node!.wiFiConfig!.apHidden { hasChanges = true }}
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
