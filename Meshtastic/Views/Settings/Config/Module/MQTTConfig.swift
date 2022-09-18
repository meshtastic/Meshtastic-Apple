//
//  MQTT.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 9/4/22.
//
import SwiftUI

struct MQTTConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var initialLoad: Bool = true
	@State var hasChanges: Bool = false
	
	@State var enabled = false
	@State var address = ""
	@State var username = ""
	@State var password = ""
	@State var encryptionEnabled = false
	@State var jsonEnabled = false
	
	var body: some View {
		
		VStack {
			
			Form {
				
				Text("WiFi must also be enabled for MQTT to work. You can set uplink and downlink for each channel.")
					.font(.title3)
				
				Section(header: Text("Options")) {
						
					Toggle(isOn: $enabled) {

						Label("Enabled", systemImage: "dot.radiowaves.right")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $encryptionEnabled) {

						Label("Encryption Enabled", systemImage: "lock.icloud")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					Toggle(isOn: $jsonEnabled) {

						Label("JSON Enabled", systemImage: "ellipsis.curlybraces")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
				}
				Section(header: Text("Custom Server")) {
					
					HStack {
						Label("Address", systemImage: "server.rack")
						TextField("Server Address", text: $address)
							.foregroundColor(.gray)
							.autocapitalization(.none)
							.disableAutocorrection(true)
							.onChange(of: address, perform: { value in

								let totalBytes = address.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 30 {

									let firstNBytes = Data(username.utf8.prefix(30))
							
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										
										// Set the shortName back to the last place where it was the right size
										address = maxBytesString
									}
								}
								hasChanges = true
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
					
					HStack {
						Label("Username", systemImage: "person.text.rectangle")
						TextField("Server Username", text: $username)
							.foregroundColor(.gray)
							.autocapitalization(.none)
							.disableAutocorrection(true)
							.onChange(of: username, perform: { value in

								let totalBytes = username.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 30 {

									let firstNBytes = Data(username.utf8.prefix(30))
							
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										
										// Set the shortName back to the last place where it was the right size
										username = maxBytesString
									}
								}
								hasChanges = true
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
					
					
					HStack {
						Label("Password", systemImage: "wallet.pass")
						TextField("Server Password", text: $password)
							.foregroundColor(.gray)
							.autocapitalization(.none)
							.disableAutocorrection(true)
							.onChange(of: password, perform: { value in

								let totalBytes = password.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 30 {

									let firstNBytes = Data(password.utf8.prefix(30))
							
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										
										// Set the shortName back to the last place where it was the right size
										password = maxBytesString
									}
								}
								hasChanges = true
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
				Button("Save MQTT Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
					
					var mqtt = ModuleConfig.MQTTConfig()
					mqtt.enabled = self.enabled
					mqtt.address = self.address
					mqtt.username = self.username
					mqtt.password = self.password
					mqtt.encryptionEnabled = self.encryptionEnabled
					mqtt.jsonEnabled = self.jsonEnabled
									
					let adminMessageId =  bleManager.saveMQTTConfig(config: mqtt, fromUser: node!.user!, toUser: node!.user!)
					
					if adminMessageId > 0 {
						
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						self.hasChanges = false
						
					} else {
						
					}
				}
			}
		}
		.navigationTitle("MQTT Config")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {

			if self.initialLoad{
				
				self.bleManager.context = context

				self.enabled = (node!.mqttConfig?.enabled ?? false)
				self.address = node!.mqttConfig?.address ?? ""
				self.username = node!.mqttConfig?.username ?? ""
				self.password = node!.mqttConfig?.password ?? ""
				self.encryptionEnabled = (node!.mqttConfig?.encryptionEnabled ?? false)
				self.jsonEnabled = (node!.mqttConfig?.jsonEnabled ?? false)

				self.hasChanges = false
				self.initialLoad = false
			}
		}
		.onChange(of: enabled) { newEnabled in
			
			if node != nil && node!.mqttConfig != nil {
				
				if newEnabled != node!.mqttConfig!.enabled { hasChanges = true }
			}
		}
		.onChange(of: encryptionEnabled) { newEncryptionEnabled in
			
			if node != nil && node!.mqttConfig != nil {
				
				if newEncryptionEnabled != node!.mqttConfig!.encryptionEnabled { hasChanges = true }
			}
		}
		.onChange(of: jsonEnabled) { newJsonEnabled in
			
			if node != nil && node!.mqttConfig != nil {
				
				if newJsonEnabled != node!.mqttConfig!.jsonEnabled { hasChanges = true }
			}
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
