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
	@State var mapReportingOptIn = false
	//@AppStorage("mapReportingOptIn") private var  mapReportingOptIn: Bool = false
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

				Section(header: Text("Options")) {

					Toggle(isOn: $enabled) {
						Label("Enabled", systemImage: "dot.radiowaves.up.forward")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					Toggle(isOn: $proxyToClientEnabled) {

						Label("mqtt.clientproxy", systemImage: "iphone.radiowaves.left.and.right")
						Text("Utilizes the network connection on your phone to connect to MQTT.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					if enabled && proxyToClientEnabled && node?.mqttConfig?.proxyToClientEnabled ?? false == true {
						Toggle(isOn: $mqttConnected) {
							Label("Connect to MQTT via Proxy", systemImage: "server.rack")
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

					if !proxyToClientEnabled {
						Toggle(isOn: $jsonEnabled) {
							Label("JSON Enabled", systemImage: "ellipsis.curlybraces")
							Text("JSON mode is a limited, unencrypted MQTT output for locally integrating with home assistant")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					}
				}

				Section(header: Text("Map Report")) {
					Toggle(isOn: $mapReportingEnabled) {
						Label("Enabled", systemImage: "map")
						Text("Your node will periodically send an unencrypted map report packet to the configured MQTT server, this includes id, short and long name, approximate location, hardware model, role, firmware version, LoRa region, modem preset and primary channel name.")
							.foregroundColor(.gray)
							.font(.caption)
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					if mapReportingEnabled {
						Text("Consent to Share Unencrypted Node Data via MQTT")
						Text("By enabling this feature, you acknowledge and expressly consent to the transmission of your device’s real-time geographic location over the MQTT protocol without encryption. This location data may be used for purposes such as live map reporting, device tracking, and related telemetry functions.")
							.foregroundColor(.gray)
							.font(.caption)
						Text("Please be advised that because the map report is not encrypted, your data may be stored and displayed permanently by third parties. Meshtastic does not assume responsibility for any such storage, display or disclosure of this data.")
							.foregroundColor(.gray)
							.font(.caption)
						Toggle(isOn: $mapReportingOptIn) {
							Label("I have read and understand the above. I voluntarily consent to the unencrypted transmission of my node data via MQTT.", systemImage: "hand.raised")
								.foregroundColor(.gray)
								.font(.callout)

						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					}
					if mapReportingEnabled && mapReportingOptIn {
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
							Text("To comply with privacy laws like CCPA and GDPR, we avoid sharing exact location data. Instead, we use anonymized or approximate (imprecise) location information to protect your privacy.")
								.foregroundColor(.gray)
								.font(.callout)
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
							.onChange(of: root) {
								var totalBytes = root.utf8.count
								// Only mess with the value if it is too big
								while totalBytes > 30 {
									root = String(root.dropLast())
									totalBytes = root.utf8.count
								}
							}
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
							.onChange(of: address) {
								var totalBytes = address.utf8.count
								// Only mess with the value if it is too big
								while totalBytes > 62 {
									address = String(address.dropLast())
									totalBytes = address.utf8.count
								}
								hasChanges = true
							}
							.keyboardType(.default)
					}
					.autocorrectionDisabled()
					if address != "mqtt.meshtastic.org" {
						HStack {
							Label("Username", systemImage: "person.text.rectangle")
							TextField("Username", text: $username)
								.foregroundColor(.gray)
								.autocapitalization(.none)
								.disableAutocorrection(true)
								.onChange(of: username) {
									var totalBytes = username.utf8.count
									// Only mess with the value if it is too big
									while totalBytes > 62 {
										username = String(username.dropLast())
										totalBytes = username.utf8.count
									}
									hasChanges = true
								}
								.foregroundColor(.gray)
						}
						.keyboardType(.default)
						.scrollDismissesKeyboard(.interactively)
						HStack {
							Label("Password", systemImage: "wallet.pass")
							TextField("Password", text: $password)
								.foregroundColor(.gray)
								.autocapitalization(.none)
								.disableAutocorrection(true)
								.onChange(of: password) {
									var totalBytes = password.utf8.count
									// Only mess with the value if it is too big
									while totalBytes > 30 {
										password = String(password.dropLast())
										totalBytes = password.utf8.count
									}
									hasChanges = true
								}
								.foregroundColor(.gray)
						}
						.keyboardType(.default)
						.scrollDismissesKeyboard(.interactively)
						.listRowSeparator(/*@START_MENU_TOKEN@*/.visible/*@END_MENU_TOKEN@*/)
						if !proxyToClientEnabled {
							Toggle(isOn: $tlsEnabled) {
								Label("TLS Enabled", systemImage: "checkmark.shield.fill")
								Text("Your MQTT Server must support TLS.")
							}
							.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						}
					}
				}
				Text("For all Mqtt functionality other than the map report you must also set uplink and downlink for each channel you want to bridge over Mqtt.")
					.font(.callout)
			}
			.scrollDismissesKeyboard(.interactively)
			.disabled(self.bleManager.connectedPeripheral == nil || node?.mqttConfig == nil)

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
					mqtt.mapReportingEnabled = (self.mapReportingEnabled && self.mapReportingOptIn)
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
			}.onChange(of: enabled) { _, newEnabled in
				if newEnabled != node?.mqttConfig?.enabled { hasChanges = true }
			}
			.onChange(of: proxyToClientEnabled) { _, newProxyToClientEnabled in
				if newProxyToClientEnabled {
					jsonEnabled = false
					tlsEnabled = false
				}
				if newProxyToClientEnabled != node?.mqttConfig?.proxyToClientEnabled { hasChanges = true }
			}
			.onChange(of: address) { _, newAddress in
				if address.lowercased() == "mqtt.meshtastic.org" {
					username = "meshdev"
					password = "large4cats"
				}
				if newAddress != node?.mqttConfig?.address ?? "" { hasChanges = true }
			}
			.onChange(of: username) { _, newUsername in
				if newUsername != node?.mqttConfig?.username ?? "" { hasChanges = true }
			}
			.onChange(of: password) { _, newPassword in
				if newPassword != node?.mqttConfig?.password ?? "" { hasChanges = true }
			}
			.onChange(of: root) { _, newRoot in
				if newRoot != node?.mqttConfig?.root ?? "" { hasChanges = true }
			}
			.onChange(of: selectedTopic) { _, newSelectedTopic in
				root = newSelectedTopic
			}
			.onChange(of: encryptionEnabled) { _, newEncryptionEnabled in
				if newEncryptionEnabled != node?.mqttConfig?.encryptionEnabled { hasChanges = true }
			}
			.onChange(of: jsonEnabled) { _, newJsonEnabled in
				if newJsonEnabled {
					proxyToClientEnabled = false
				}
				if newJsonEnabled != node?.mqttConfig?.jsonEnabled { hasChanges = true }
			}
			.onChange(of: tlsEnabled) { _, newTlsEnabled in
				if address.lowercased() == "mqtt.meshtastic.org" {
					tlsEnabled = false
				} else {
					if newTlsEnabled != node?.mqttConfig?.tlsEnabled { hasChanges = true }
				}
			}
			.onChange(of: mqttConnected) { _, newMqttConnected in
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
			.onChange(of: mapReportingEnabled) { _, newMapReportingEnabled in
				if newMapReportingEnabled != node?.mqttConfig?.mapReportingEnabled { hasChanges = true }
			}
			.onChange(of: mapPublishIntervalSecs) { _, newMapPublishIntervalSecs in
				if newMapPublishIntervalSecs != node?.mqttConfig?.mapPublishIntervalSecs ?? -1 { hasChanges = true }
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
		.onFirstAppear {
			// Need to request a MqttModuleConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if node.num != connectedNode.num {
						if UserDefaults.enableAdministration && node.num != connectedNode.num {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.mqttConfig == nil {
								Logger.mesh.info("⚙️ Empty or expired mqtt module config requesting via PKI admin")
								_ = bleManager.requestMqttModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin, empty mqtt module config")
							_ = bleManager.requestMqttModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
						}
					}
				}
			}
		}
	}

	func setMqttValues() {

		nearbyTopics = []
		let geocoder = CLGeocoder()
		if LocationsHandler.shared.locationsArray.count > 0 {
			let region  = RegionCodes(rawValue: Int(node?.loRaConfig?.regionCode ?? 0))
			defaultTopic = "msh/" + (region?.topic ?? "UNSET")
			geocoder.reverseGeocodeLocation(LocationsHandler.shared.locationsArray.first!, completionHandler: {(placemarks, error) in
				if let error {
					Logger.services.error("Failed to reverse geocode location: \(error.localizedDescription, privacy: .public)")
					return
				}

				if let placemarks = placemarks, let placemark = placemarks.first {
					/// Country Topic unless your region is a country
					if !(region?.isCountry ?? false) {
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
