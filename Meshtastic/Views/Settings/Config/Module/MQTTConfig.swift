//
//  MQTT.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 9/4/22.
//
import CoreLocation
import MeshtasticProtobufs
import OSLog
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
	@State var tlsEnabled = false
	@State var root = "msh"
	@State var selectedTopic = ""
	@State var mqttConnected: Bool = false
	@State var defaultTopic = "msh/US"
	@State var nearbyTopics = [String]()
	@State var mapReportingEnabled = false
	@State var mapPublishIntervalSecs = 3600
	@State var mapPositionPrecision: Double = 14.0

	let locale = Locale.current

	var body: some View {
		VStack {
			Form {
				if node != nil && node?.loRaConfig != nil {
					let rc = RegionCodes(rawValue: Int(node?.loRaConfig?.regionCode ?? 0))
					if rc?.dutyCycle ?? 0 > 0 && rc?.dutyCycle ?? 0 < 100 {
						Text("Your region has a \(rc?.dutyCycle ?? 0)% duty cycle. MQTT is not advised when you are duty cycle restricted, the extra traffic will quickly overwhelm your LoRa mesh.")
							.font(.callout)
							.foregroundColor(.red)
					}
				}

				ConfigHeader(title: "MQTT", config: \.mqttConfig, node: node, onAppear: setMqttValues)

				Section(header: Text("options")) {

					Toggle(isOn: $enabled) {
						Label("enabled", systemImage: "dot.radiowaves.up.forward")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					Toggle(isOn: $proxyToClientEnabled) {

						Label("mqtt.clientproxy", systemImage: "iphone.radiowaves.left.and.right")
						Text("Utilizes the network connection on your phone to connect to MQTT.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					if enabled && proxyToClientEnabled && node!.mqttConfig!.proxyToClientEnabled == true {
						Toggle(isOn: $mqttConnected) {
							Label(mqttConnected ? "mqtt.disconnect".localized : "mqtt.connect".localized, systemImage: "server.rack")
							if bleManager.mqttError.count > 0 {
								Text(bleManager.mqttError)
									.fixedSize(horizontal: false, vertical: true)
									.foregroundColor(.red)
							}

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
				}

				Section(header: Text("Map Report")) {

					Toggle(isOn: $mapReportingEnabled) {
						Label("enabled", systemImage: "map")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					if mapReportingEnabled {
						Picker("Map Publish Interval", selection: $mapPublishIntervalSecs ) {
							ForEach(UpdateIntervals.allCases) { ui in
								if ui.rawValue >= 3600 {
									Text(ui.description)
								}
							}
						}
						.pickerStyle(DefaultPickerStyle())
						VStack(alignment: .leading) {
							Label("Approximate Location", systemImage: "location.slash.circle.fill")
							Slider(value: $mapPositionPrecision, in: 11...14, step: 1) {
							} minimumValueLabel: {
								Image(systemName: "minus")
							} maximumValueLabel: {
								Image(systemName: "plus")
							}
							Text(PositionPrecision(rawValue: Int(mapPositionPrecision))?.description ?? "")
								.foregroundColor(.gray)
								.font(.callout)
						}
					}
				}
				Section(header: Text("Root Topic")) {
					HStack {
						Label("Root Topic", systemImage: "tree")
						TextField("Root Topic", text: $root)
							.foregroundColor(.gray)
							.onChange(of: root, perform: { _ in
								let totalBytes = root.utf8.count
								// Only mess with the value if it is too big
								if totalBytes > 30 {
									root = String(root.dropLast())
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
									address = String(address.dropLast())
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
									username = String(username.dropLast())
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
									password = String(password.dropLast())
								}
								hasChanges = true
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
					.scrollDismissesKeyboard(.interactively)
					.listRowSeparator(/*@START_MENU_TOKEN@*/.visible/*@END_MENU_TOKEN@*/)
					Toggle(isOn: $tlsEnabled) {
						Label("TLS Enabled", systemImage: "checkmark.shield.fill")
						Text("Your MQTT Server must support TLS. Not available via the public mqtt server.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
				Text("For all Mqtt functionality other than the map report you must also set uplink and downlink for each channel you want to bridge over Mqtt.")
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
				mqtt.mapReportingEnabled = self.mapReportingEnabled
				mqtt.mapReportSettings.positionPrecision = UInt32(self.mapPositionPrecision)
				mqtt.mapReportSettings.publishIntervalSecs = UInt32(self.mapPublishIntervalSecs)
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
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: bleManager.connectedPeripheral?.shortName ?? "?"
				)
			}
		)
		.onChange(of: enabled) {
			if $0 != node?.mqttConfig?.enabled { hasChanges = true }
		}
		.onChange(of: proxyToClientEnabled) { newProxyToClientEnabled in
			if newProxyToClientEnabled {
				jsonEnabled = false
			}
			if newProxyToClientEnabled != node?.mqttConfig?.proxyToClientEnabled { hasChanges = true }
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
		.onChange(of: encryptionEnabled) {
			if $0 != node?.mqttConfig?.encryptionEnabled { hasChanges = true }
		}
		.onChange(of: jsonEnabled) { newJsonEnabled in
			if newJsonEnabled {
				proxyToClientEnabled = false
			}
			if newJsonEnabled != node?.mqttConfig?.jsonEnabled { hasChanges = true }
		}
		.onChange(of: tlsEnabled) { newTlsEnabled in
			if address.lowercased() == "mqtt.meshtastic.org" {
				tlsEnabled = false
			} else {
				if newTlsEnabled != node?.mqttConfig?.tlsEnabled { hasChanges = true }
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
		.onChange(of: mapReportingEnabled) {
			if $0 != node?.mqttConfig?.mapReportingEnabled { hasChanges = true }
		}
		.onChange(of: mapPublishIntervalSecs) { newMapPublishIntervalSecs in
			if node != nil && node?.mqttConfig != nil {
				if newMapPublishIntervalSecs != node!.mqttConfig!.mapPublishIntervalSecs { hasChanges = true }
			}
		}
		.onFirstAppear {
			// Need to request a MqttModuleConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {
				Logger.mesh.info("empty mqtt module config")
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if node.num != connectedNode.num {
						if UserDefaults.enableAdministration && node.num != connectedNode.num {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.mqttConfig == nil {
								_ = bleManager.requestMqttModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						} else {
							/// Legacy Administration
							_ = bleManager.requestMqttModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
						}
					}
				}
			}
		}
	}
	func setMqttValues() {

		if #available(iOS 17.0, macOS 14.0, *) {

			nearbyTopics = []
			let geocoder = CLGeocoder()
			if LocationsHandler.shared.locationsArray.count > 0 {
				let region  = RegionCodes(rawValue: Int(node?.loRaConfig?.regionCode ?? 0))?.topic
				defaultTopic = "msh/" + (region ?? "UNSET")
				geocoder.reverseGeocodeLocation(LocationsHandler.shared.locationsArray.first!, completionHandler: {(placemarks, error) in
					if let error {
						Logger.services.error("Failed to reverse geocode location: \(error.localizedDescription)")
						return
					}

					if let placemarks = placemarks, let placemark = placemarks.first {
						let cc = locale.region?.identifier ?? "UNK"
						/// Country Topic unless you are US
						if  placemark.isoCountryCode ?? "unknown" != cc {
							let countryTopic = defaultTopic + "/" + (placemark.isoCountryCode ?? "")
							if !countryTopic.isEmpty {
								nearbyTopics.append(countryTopic)
							}
						}
						let stateTopic = defaultTopic + "/" + (placemark.administrativeArea ?? "")
						if !stateTopic.isEmpty {
							nearbyTopics.append(stateTopic)
						}
						let countyTopic = defaultTopic + "/" + (placemark.administrativeArea ?? "") + "/" + (placemark.subAdministrativeArea?.lowercased().replacingOccurrences(of: " ", with: "") ?? "")
						if !countyTopic.isEmpty {
							nearbyTopics.append(countyTopic)
						}
						let cityTopic = defaultTopic + "/" + (placemark.administrativeArea ?? "") + "/" + (placemark.locality?.lowercased().replacingOccurrences(of: " ", with: "") ?? "")
						if !cityTopic.isEmpty {
							nearbyTopics.append(cityTopic)
						}
						let neightborhoodTopic = defaultTopic + "/" + (placemark.administrativeArea ?? "") + "/" + (placemark.subLocality?.lowercased()
							.replacingOccurrences(of: " ", with: "")
							.replacingOccurrences(of: "'", with: "") ?? "")
						if !neightborhoodTopic.isEmpty {
							nearbyTopics.append(neightborhoodTopic)
						}
					} else {
						Logger.services.debug("No Location")
					}
				})
			}
		}
		self.enabled = node?.mqttConfig?.enabled ?? false
		self.proxyToClientEnabled = node?.mqttConfig?.proxyToClientEnabled ?? false
		self.address = node?.mqttConfig?.address ?? ""
		self.username = node?.mqttConfig?.username ?? ""
		self.password = node?.mqttConfig?.password ?? ""
		self.root = node?.mqttConfig?.root ?? "msh"
		self.encryptionEnabled = node?.mqttConfig?.encryptionEnabled ?? false
		self.jsonEnabled = node?.mqttConfig?.jsonEnabled ?? false
		self.tlsEnabled = node?.mqttConfig?.tlsEnabled ?? false
		self.mqttConnected = bleManager.mqttProxyConnected
		self.mapReportingEnabled = node?.mqttConfig?.mapReportingEnabled ?? false
		self.mapPublishIntervalSecs = Int(node?.mqttConfig?.mapPublishIntervalSecs ?? 3600)
		self.mapPositionPrecision = Double(node?.mqttConfig?.mapPositionPrecision ?? 14)
		if mapPositionPrecision < 11 || mapPositionPrecision > 14 {
			self.mapPositionPrecision = 14
			self.hasChanges = true
		} else {
			self.hasChanges = false
		}
	}
}
