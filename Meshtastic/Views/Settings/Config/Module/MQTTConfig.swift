//
//  MQTT.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 9/4/22.
//
import SwiftUI
import CoreLocation

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
	@State var selectedTopic = ""
	@State var mqttConnected: Bool = false
	@State var nearbyTopics = [String]()

	var body: some View {
		VStack {
			Form {
				if node != nil && node?.loRaConfig != nil {
					let rc = RegionCodes(rawValue: Int(node?.loRaConfig?.regionCode ?? 0))
					if rc?.dutyCycle ?? 0 > 0 && rc?.dutyCycle ?? 0 < 100  {
						Text("Your region has a \(rc?.dutyCycle ?? 0)% duty cycle. MQTT is not advised when you are duty cycle restricted, the extra traffic will quickly overwhelm your LoRa mesh.")
							.font(.callout)
							.foregroundColor(.red)
					}
				}

				ConfigHeader(title: "MQTT", config: \.mqttConfig, node: node, onAppear: setMqttValues)

				Section(header: Text("options")) {
					
					Toggle(isOn: $enabled) {
						Label("enabled", systemImage: "dot.radiowaves.right")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $proxyToClientEnabled) {
						
						Label("mqtt.clientproxy", systemImage: "iphone.radiowaves.left.and.right")
						Text("Utilizes the network connection on your phone to connect to MQTT.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					if enabled && proxyToClientEnabled {
						Toggle(isOn: $mqttConnected) {
							Label(mqttConnected ? "mqtt.disconnect".localized : "mqtt.connect".localized, systemImage: "server.rack")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					}
					
					Toggle(isOn: $encryptionEnabled) {
						Label("Encryption Enabled", systemImage: "lock.icloud")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $jsonEnabled) {
						Label("JSON Enabled", systemImage: "ellipsis.curlybraces")
						Text("JSON mode is a limited, unencrypted MQTT output for locally integrating with home assistant")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $tlsEnabled) {
						Label("TLS Enabled", systemImage: "checkmark.shield.fill")
						Text("Your MQTT Server must support TLS.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

				}
				Section(header: Text("Server")) {
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
					.listRowSeparator(/*@START_MENU_TOKEN@*/.visible/*@END_MENU_TOKEN@*/)
					HStack {
						Label("Root Topic", systemImage: "tree")
						TextField("Root Topic", text: $root)
							.foregroundColor(.gray)
							.onChange(of: root, perform: { _ in
								let totalBytes = root.utf8.count
								// Only mess with the value if it is too big
								if totalBytes > 30 {
									let firstNBytes = Data(root.utf8.prefix(30))
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
					.listRowSeparator(.hidden)
					Text("The root topic to use for MQTT.")
						.foregroundColor(.gray)
						.font(.callout)
					
					if nearbyTopics.count > 0 {
						Picker("Nearby Topics", selection: $selectedTopic ) {
							ForEach(nearbyTopics, id: \.self) { nt in
								Text(nt)
							}
						}
						.pickerStyle(InlinePickerStyle())
						.listRowSeparator(.hidden)
						Text("If the default region topic is too busy you can choose a more local topic.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}
				Text("You can set uplink and downlink for each channel.")
					.font(.callout)
			}
			.scrollDismissesKeyboard(.interactively)
			.disabled(self.bleManager.connectedPeripheral == nil || node?.mqttConfig == nil)
		}

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
			if connectedNode != nil {
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
		.onChange(of: selectedTopic) { newSelectedTopic in
			root = newSelectedTopic
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
		
		if #available(iOS 17.0, macOS 14.0, *) {
			
			nearbyTopics = []
			let geocoder = CLGeocoder()
			if LocationsHandler.shared.locationsArray.count > 0 {
				geocoder.reverseGeocodeLocation(LocationsHandler.shared.locationsArray.first!, completionHandler: {(placemarks, error) -> Void in
					if error != nil {
						print("Failed to reverse geocode location")
						return
					}
					
					if let placemarks = placemarks, let placemark = placemarks.first {
						
						/// Country Topic unless you are US
						if  placemark.isoCountryCode ?? "unknown" != "US" {
							let countryTopic = root + "/" + (placemark.isoCountryCode ?? "")
							if !countryTopic.isEmpty {
								nearbyTopics.append(countryTopic)
							}
						}
						let stateTopic = root + "/" + (placemark.administrativeArea ?? "")
						if !stateTopic.isEmpty {
							nearbyTopics.append(stateTopic)
						}
						let countyTopic = root + "/" + (placemark.subAdministrativeArea?.lowercased().replacingOccurrences(of: " ", with: "") ?? "")
						if !countyTopic.isEmpty {
							nearbyTopics.append(countyTopic)
						}
						let cityTopic = root + "/" + (placemark.locality?.lowercased().replacingOccurrences(of: " ", with: "") ?? "")
						if !cityTopic.isEmpty {
							nearbyTopics.append(cityTopic)
						}
						let neightborhoodTopic = root + "/" + (placemark.subLocality?.lowercased().replacingOccurrences(of: " ", with: "") ?? "")
						if !neightborhoodTopic.isEmpty {
							nearbyTopics.append(neightborhoodTopic)
						}
						
					}
					else
					{
						print("No Location")
					}
				})
			}
		}
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
