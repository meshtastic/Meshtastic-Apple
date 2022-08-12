//
//  WiFiConfig.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 8/1/2022
//

import SwiftUI

enum WiFiModes: Int, CaseIterable, Identifiable {

	case client = 0
	case accessPoint = 1
	case accessPointHidden = 2

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .client:
				return "Client"
			case .accessPoint:
				return "Software Access Point"
			case .accessPointHidden:
				return "Software Access Point (Hidden)"
			
			}
		}
	}
	func protoEnumValue() -> Config.WiFiConfig.WiFiMode {
		
		switch self {
			
		case .client:
			return Config.WiFiConfig.WiFiMode.client
		case .accessPoint:
			return Config.WiFiConfig.WiFiMode.accessPoint
		case .accessPointHidden:
			return Config.WiFiConfig.WiFiMode.accessPointHidden
		}
	}
}

struct WiFiConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var initialLoad: Bool = true
	@State var hasChanges: Bool = false
	
	@State var enabled = false
	@State var ssid = ""
	@State var password = ""
	@State var mode = 0
	
	var body: some View {
		
		VStack {
			
			Form {
				
				Text("Enabling WiFi will disable the bluetooth connection to the app.")
					.font(.title3)
				
				Section(header: Text("Options")) {
						
					Toggle(isOn: $enabled) {

						Label("Enabled", systemImage: "wifi")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					

					Picker("Mode", selection: $mode ) {
						ForEach(WiFiModes.allCases) { lu in
							Text(lu.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
				}
				Section(header: Text("SSID & Password")) {
					
					HStack {
						Label("SSID", systemImage: "network")
						TextField("SSID", text: $ssid)
							.foregroundColor(.gray)
							.autocapitalization(.none)
							.disableAutocorrection(true)
							.onChange(of: ssid, perform: { value in

								let totalBytes = ssid.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 32 {

									let firstNBytes = Data(ssid.utf8.prefix(32))
							
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										
										// Set the shortName back to the last place where it was the right size
										ssid = maxBytesString
									}
								}
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
					
					
					HStack {
						Label("Password", systemImage: "wallet.pass")
						TextField("Password", text: $password)
							.foregroundColor(.gray)
							.autocapitalization(.none)
							.disableAutocorrection(true)
							.onChange(of: password, perform: { value in

								let totalBytes = password.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 63 {

									let firstNBytes = Data(ssid.utf8.prefix(63))
							
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										
										// Set the shortName back to the last place where it was the right size
										ssid = maxBytesString
									}
								}
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
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
					wifi.enabled = self.enabled
					wifi.ssid = self.ssid
					wifi.psk = self.password
					wifi.mode = WiFiModes(rawValue: self.mode)?.protoEnumValue() ?? WiFiModes.client.protoEnumValue()
					
					let adminMessageId =  bleManager.saveWiFiConfig(config: wifi, fromUser: node!.user!, toUser: node!.user!, wantAck: true)
					
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

				self.enabled = (node!.wiFiConfig?.enabled ?? false)
				self.ssid = node!.wiFiConfig?.ssid ?? ""
				self.password = node!.wiFiConfig?.password ?? ""
				self.mode = Int(node!.wiFiConfig?.mode ?? 0)

				self.hasChanges = false
				self.initialLoad = false
			}
		}
		.onChange(of: enabled) { newEnabled in
			
			if node != nil && node!.wiFiConfig != nil {
				
				if newEnabled != node!.wiFiConfig!.enabled { hasChanges = true }
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
		.onChange(of: mode) { newMode in
			
			if node != nil && node!.wiFiConfig != nil {
				
				if newMode != node!.wiFiConfig!.mode { hasChanges = true }
			}
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
