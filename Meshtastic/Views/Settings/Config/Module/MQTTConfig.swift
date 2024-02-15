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
	@Environment(\.dismiss) private var goBack
	var node: NodeInfoEntity?
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges: Bool = false
	@State var enabled = false
	@State var proxyToClientEnabled = false
	@State var address = ""
	@State var username = ""
	@State var password = ""
	@State var encryptionEnabled = true
	@State var jsonEnabled = false
	@State var tlsEnabled = true
	@State var root = "msh"
	@State var mqttConnected: Bool = false
	
	

	var body: some View {
		VStack {
			Form {
				if node != nil && node?.loRaConfig != nil {
					let rc = RegionCodes(rawValue: Int(node?.loRaConfig?.regionCode ?? 0))
					if rc?.dutyCycle ?? 0 <= 10 {
						Text("Your region has a \(rc?.dutyCycle ?? 0)% duty cycle. MQTT is not advised when you are duty cycle restricted, the extra traffic will quickly overwhelm your LoRa mesh.")
							.font(.callout)
							.foregroundColor(.red)
					}
				}
					
				if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					Text("There has been no response to a request for device metadata over the admin channel for this node.")
						.font(.callout)
						.foregroundColor(.orange)
					
				} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					// Let users know what is going on if they are using remote admin and don't have the config yet
					if node?.mqttConfig == nil {
						Text("MQTT config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
							.font(.callout)
							.foregroundColor(.orange)
					} else {
						Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
							.font(.title3)
							.onAppear {
								setMqttValues()
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
				Section(header: Text("options")) {
					
					Toggle(isOn: $enabled) {
						
						Label("enabled", systemImage: "dot.radiowaves.right")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Toggle(isOn: $proxyToClientEnabled) {
						
						Label("mqtt.clientproxy", systemImage: "iphone.radiowaves.left.and.right")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					if enabled && proxyToClientEnabled {
						Toggle(isOn: $mqttConnected) {
							Label(mqttConnected ? "mqtt.disconnect".localized : "mqtt.connect".localized, systemImage: "server.rack")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					}
					Text("If both MQTT and the client proxy are enabled your mobile device will utilize an available network connection to connect to the specified MQTT server.")
						.font(.caption2)
					
					Toggle(isOn: $encryptionEnabled) {
						
						Label("Encryption Enabled", systemImage: "lock.icloud")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $jsonEnabled) {
						
						Label("JSON Enabled", systemImage: "ellipsis.curlybraces")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("JSON mode is a limited, unencrypted MQTT output that can crash your node it should not be enabled unless you are locally integrating with home assistant")
						.font(.caption2)
					
					Toggle(isOn: $tlsEnabled) {
						
						Label("TLS Enabled", systemImage: "checkmark.shield.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("Your MQTT Server must support TLS.")
						.font(.caption2)
				}
				Section(header: Text("Custom Server")) {
					HStack {
						Label("Address", systemImage: "server.rack")
						TextField("Server Address", text: $address)
							.foregroundColor(.gray)
							.autocapitalization(.none)
							.disableAutocorrection(true)
							.onChange(of: address, perform: { _ in
								let totalBytes = address.utf8.count
								// Only mess with the value if it is too big
								if totalBytes > 62 {
									let firstNBytes = Data(username.utf8.prefix(62))
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										// Set the shortName back to the last place where it was the right size
										address = maxBytesString
									}
								}
								hasChanges = true
							})
							.foregroundColor(.gray)
							.keyboardType(.default)
					}
					.autocorrectionDisabled()
					
					HStack {
						Label("mqtt.username", systemImage: "person.text.rectangle")
						TextField("mqtt.username", text: $username)
							.foregroundColor(.gray)
							.autocapitalization(.none)
							.disableAutocorrection(true)
							.onChange(of: username, perform: { _ in
								
								let totalBytes = username.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 62 {
									
									let firstNBytes = Data(username.utf8.prefix(62))
									
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
					.scrollDismissesKeyboard(.interactively)
					HStack {
						Label("password", systemImage: "wallet.pass")
						TextField("password", text: $password)
							.foregroundColor(.gray)
							.autocapitalization(.none)
							.disableAutocorrection(true)
							.onChange(of: password, perform: { _ in
								
								let totalBytes = password.utf8.count
								
								// Only mess with the value if it is too big
								if totalBytes > 62 {
									
									let firstNBytes = Data(password.utf8.prefix(62))
									
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
					.scrollDismissesKeyboard(.interactively)
					HStack {
						Label("Root Topic", systemImage: "tree")
						TextField("Root Topic", text: $root)
							.foregroundColor(.gray)
							.onChange(of: root, perform: { _ in
								let totalBytes = root.utf8.count
								// Only mess with the value if it is too big
								if totalBytes > 14 {
									let firstNBytes = Data(root.utf8.prefix(14))
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										// Set the shortName back to the last place where it was the right size
										root = maxBytesString
									}
								}
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.asciiCapable)
					.scrollDismissesKeyboard(.interactively)
					.disableAutocorrection(true)
					Text("The root topic to use for MQTT messages. Default is \"msh\". This is useful if you want to use a single MQTT server for multiple meshtastic networks and separate them via ACLs")
						.font(.caption2)
				}
				Text("You can set uplink and downlink for each channel.")
					.font(.callout)
			}
			.scrollDismissesKeyboard(.interactively)
			.disabled(self.bleManager.connectedPeripheral == nil || node?.mqttConfig == nil)
		}
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
			let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
			if connectedNode != nil {
				let nodeName = node?.user?.longName ?? "unknown".localized
				let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
				Button(buttonText) {
					var mqtt = ModuleConfig.MQTTConfig()
					mqtt.enabled = self.enabled
					mqtt.proxyToClientEnabled = self.proxyToClientEnabled
					mqtt.address = self.address
					mqtt.username = self.username
					mqtt.password = self.password
					mqtt.root = self.root
					mqtt.encryptionEnabled = self.encryptionEnabled
					mqtt.jsonEnabled = self.jsonEnabled
					mqtt.tlsEnabled = self.tlsEnabled
					let adminMessageId =  bleManager.saveMQTTConfig(config: mqtt, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
		}
		message: {
			Text("config.save.confirm")
		}
		.navigationTitle("mqtt.config")
		.navigationBarItems(trailing:
			ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?", mqttProxyConnected: bleManager.mqttProxyConnected)
		})
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
			setMqttValues()
			// Need to request a TelemetryModuleConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.mqttConfig == nil {
				print("empty mqtt module config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestMqttModuleConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: address) { newAddress in
			if node != nil && node?.mqttConfig != nil {
				if newAddress != node!.mqttConfig!.address { hasChanges = true }
			}
		}
		.onChange(of: username) { newUsername in
			if node != nil && node?.mqttConfig != nil {
				if newUsername != node!.mqttConfig!.username { hasChanges = true }
			}
		}
		.onChange(of: password) { newPassword in
			if node != nil && node?.mqttConfig != nil {
				if newPassword != node!.mqttConfig!.password { hasChanges = true }
			}
		}
		.onChange(of: root) { newRoot in
			if node != nil && node?.mqttConfig != nil {
				if newRoot != node!.mqttConfig!.root { hasChanges = true }
			}
		}
		.onChange(of: enabled) { newEnabled in
			if node != nil && node?.mqttConfig != nil {
				if newEnabled != node!.mqttConfig!.enabled { hasChanges = true }
			}
		}
		.onChange(of: proxyToClientEnabled) { newProxyToClientEnabled in
			if node != nil && node?.mqttConfig != nil {
				if newProxyToClientEnabled != node!.mqttConfig!.proxyToClientEnabled { hasChanges = true }
				if newProxyToClientEnabled {
					jsonEnabled = false
				}
			}
		}
		.onChange(of: encryptionEnabled) { newEncryptionEnabled in
			if node != nil && node?.mqttConfig != nil {
				if newEncryptionEnabled != node!.mqttConfig!.encryptionEnabled { hasChanges = true }
			}
		}
		.onChange(of: jsonEnabled) { newJsonEnabled in
			if node != nil && node?.mqttConfig != nil {
				if newJsonEnabled != node!.mqttConfig!.jsonEnabled { hasChanges = true }
			}
		}
		.onChange(of: tlsEnabled) { newTlsEnabled in
			if node != nil && node?.mqttConfig != nil {
				if newTlsEnabled != node!.mqttConfig!.tlsEnabled { hasChanges = true }
			}
		}
		.onChange(of: mqttConnected) { newMqttConnected in
			if newMqttConnected == false {
				if bleManager.mqttProxyConnected {
					bleManager.mqttManager.disconnect()
				}
			} else {
				if !bleManager.mqttProxyConnected && node != nil {
					bleManager.mqttManager.connectFromConfigSettings(node: node!)
				}
			}
		}
	}
	func setMqttValues() {
		self.enabled = (node?.mqttConfig?.enabled ?? false)
		self.proxyToClientEnabled = (node?.mqttConfig?.proxyToClientEnabled ?? false)
		self.address = node?.mqttConfig?.address ?? ""
		self.username = node?.mqttConfig?.username ?? ""
		self.password = node?.mqttConfig?.password ?? ""
		self.root = node?.mqttConfig?.root ?? "msh"
		self.encryptionEnabled = (node?.mqttConfig?.encryptionEnabled ?? false)
		self.jsonEnabled = (node?.mqttConfig?.jsonEnabled ?? false)
		self.tlsEnabled = (node?.mqttConfig?.tlsEnabled ?? false)
		self.mqttConnected = bleManager.mqttProxyConnected
		self.hasChanges = false
	}
}
