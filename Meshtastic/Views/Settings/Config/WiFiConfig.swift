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
					
					HStack {
						Label("SSID", systemImage: "wifi")
						TextField("SSID", text: $ssid)
							.foregroundColor(.gray)
							.onChange(of: ssid, perform: { value in

								let totalBytes = ssid.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 30 {

									let firstNBytes = Data(ssid.utf8.prefix(30))
							
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										
										// Set the shortName back to the last place where it was the right size
										ssid = maxBytesString
									}
								}
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
					.disableAutocorrection(true)
					
					HStack {
						Label("Password", systemImage: "wallet.pass")
						TextField("Password", text: $password)
							.foregroundColor(.gray)
							.onChange(of: password, perform: { value in

								let totalBytes = password.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 60 {

									let firstNBytes = Data(ssid.utf8.prefix(60))
							
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										
										// Set the shortName back to the last place where it was the right size
										ssid = maxBytesString
									}
								}
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
					.disableAutocorrection(true)

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
			.disabled(!(node != nil && node!.myInfo?.hasWifi ?? false))
			
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
					wifi.ssid = self.ssid
					wifi.psk = self.password
					wifi.apMode = self.apMode
					wifi.apHidden = self.apHidden
					
					let adminMessageId =  bleManager.saveWiFiConfig(config: wifi, fromUser: node!.user!, toUser: node!.user!, wantResponse: true)
					
					if adminMessageId > 0 {
						
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						self.hasChanges = false
						
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
			
			if node != nil && node!.wiFiConfig != nil {
				
				if newSsid != node!.wiFiConfig!.ssid { hasChanges = true }
			}
		}
		.onChange(of: password) { newPassword in
			
			if node != nil && node!.wiFiConfig != nil {
				
				if newPassword != node!.wiFiConfig!.password { hasChanges = true }
			}
		}
		.onChange(of: apMode) { newApMode in
			
			if node != nil && node!.wiFiConfig != nil {
				
				if newApMode != node!.wiFiConfig!.apMode { hasChanges = true }
			}
		}
		.onChange(of: apHidden) { newApHidden in
			
			if node != nil && node!.wiFiConfig != nil {
				
				if newApHidden != node!.wiFiConfig!.apHidden { hasChanges = true }
			}
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
