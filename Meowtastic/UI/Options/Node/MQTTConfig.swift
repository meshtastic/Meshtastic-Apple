import CoreLocation
import FirebaseAnalytics
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct MQTTConfig: View {
	var node: NodeInfoEntity?

	private let locale = Locale.current

	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager
	@EnvironmentObject
	private var nodeConfig: NodeConfig
	@Environment(\.dismiss)
	private var goBack

	@State
	private var isPresentingSaveConfirm = false
	@State
	private var hasChanges = false
	@State
	private var enabled = false
	@State
	private var proxyToClientEnabled = false
	@State
	private var address = ""
	@State
	private var username = ""
	@State
	private var password = ""
	@State
	private var encryptionEnabled = true
	@State
	private var jsonEnabled = false
	@State
	private var tlsEnabled = true
	@State
	private var root = "msh"
	@State
	private var mqttConnected = false
	@State
	private var defaultTopic = "msh"
	@State
	private var mapReportingEnabled = false
	@State
	private var mapPublishIntervalSecs = 3600
	@State
	private var preciseLocation = false
	@State
	private var mapPositionPrecision: Double = 13.0

	@ViewBuilder
	var body: some View {
		Form {
			if let loraConfig = node?.loRaConfig {
				let rc = RegionCodes(rawValue: Int(loraConfig.regionCode))

				if rc?.dutyCycle ?? 0 > 0 && rc?.dutyCycle ?? 0 < 100 {
					Text("Your region has a \(rc?.dutyCycle ?? 0)% duty cycle. MQTT is not advised when you are duty cycle restricted, the extra traffic will quickly overwhelm your LoRa mesh.")
						.font(.callout)
						.foregroundColor(.red)
				}
			}

			ConfigHeader(title: "MQTT", config: \.mqttConfig, node: node)

			Section(header: Text("Options")) {
				Toggle(isOn: $enabled) {
					Label("Enabled", systemImage: "dot.radiowaves.up.forward")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				.onChange(of: enabled) {
					hasChanges = true
				}

				Toggle(isOn: $proxyToClientEnabled) {
					Label(
						"Client Proxy",
						systemImage: "iphone.radiowaves.left.and.right"
					)

					Text("Utilizes the network connection on your phone to connect to MQTT.")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				.onChange(of: proxyToClientEnabled) {
					if proxyToClientEnabled {
						jsonEnabled = false
					}
					if let mqttConfig = node?.mqttConfig {
						if proxyToClientEnabled != mqttConfig.proxyToClientEnabled {
							hasChanges = true
						}

						if proxyToClientEnabled {
							jsonEnabled = false
						}
					}
				}

				if enabled, proxyToClientEnabled, node?.mqttConfig?.proxyToClientEnabled ?? false == true {
					Toggle(isOn: $mqttConnected) {
						Label(
							mqttConnected ? "Connected" : "Not Connected",
							systemImage: "server.rack"
						)

						if bleManager.mqttError.count > 0 {
							Text(bleManager.mqttError)
								.fixedSize(horizontal: false, vertical: true)
								.foregroundColor(.red)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.onChange(of: mqttConnected) {
						if mqttConnected, !bleManager.mqttProxyConnected, let node {
							bleManager.mqttManager.connectFromConfigSettings(node: node)
						}
						else if !mqttConnected, bleManager.mqttProxyConnected {
							bleManager.mqttManager.disconnect()
						}
					}
					.onChange(of: bleManager.mqttProxyConnected, initial: true) {
						mqttConnected = bleManager.mqttProxyConnected
					}
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
				.onChange(of: jsonEnabled) {
					if jsonEnabled {
						proxyToClientEnabled = false
					}

					hasChanges = true
				}
			}

			Section(header: Text("Map Report")) {
				Toggle(isOn: $mapReportingEnabled) {
					Label("enabled", systemImage: "map")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				.onChange(of: mapReportingEnabled) {
					hasChanges = true
				}

				if mapReportingEnabled {
					Picker("Map Publish Interval", selection: $mapPublishIntervalSecs ) {
						ForEach(UpdateIntervals.allCases) { ui in
							if ui.rawValue >= 3600 {
								Text(ui.description)
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.onChange(of: mapPublishIntervalSecs) {
						hasChanges = true
					}

					VStack(alignment: .leading) {
						Toggle(isOn: $preciseLocation) {
							Label("Precise Location", systemImage: "scope")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.listRowSeparator(.visible)
						.onChange(of: preciseLocation) {
							if preciseLocation == false {
								mapPositionPrecision = 12
							}
							else {
								mapPositionPrecision = 32
							}

							hasChanges = true
						}
					}
					
					if !preciseLocation {
						VStack(alignment: .leading) {
							Label("Approximate Location", systemImage: "location.slash.circle.fill")

							Slider(value: $mapPositionPrecision, in: 11...16, step: 1) {
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
			}

			Section(header: Text("Root Topic")) {
				HStack {
					Label(
						"Root Topic",
						systemImage: "tree"
					)

					TextField("Root Topic", text: $root)
						.keyboardType(.asciiCapable)
						.autocapitalization(.none)
						.disableAutocorrection(true)
						.foregroundColor(.gray)
						.onChange(of: root) {
							if root.utf8.count > 30 {
								root = String(root.dropLast())
							}

							hasChanges = true
						}
				}
				.listRowSeparator(.hidden)

				Text("The root topic to use for MQTT.")
					.foregroundColor(.gray)
					.font(.callout)
			}

			Section(header: Text("Server")) {
				HStack {
					Label(
						"Address",
						systemImage: "server.rack"
					)

					TextField("Address", text: $address)
						.keyboardType(.default)
						.autocapitalization(.none)
						.disableAutocorrection(true)
						.foregroundColor(.gray)
						.onChange(of: address) {
							if address.utf8.count > 62 {
								address = String(address.dropLast())
							}

							hasChanges = true
						}
				}
				
				HStack {
					Label(
						"Username",
						systemImage: "person.text.rectangle"
					)

					TextField("Username", text: $username)
						.keyboardType(.default)
						.autocapitalization(.none)
						.disableAutocorrection(true)
						.foregroundColor(.gray)
						.onChange(of: username) {
							if username.utf8.count > 62 {
								username = String(username.dropLast())
							}

							hasChanges = true
						}
				}
				.scrollDismissesKeyboard(.interactively)

				HStack {
					Label("Password", systemImage: "wallet.pass")

					TextField(
						"Password",
						text: $password
					)
						.keyboardType(.default)
						.autocapitalization(.none)
						.disableAutocorrection(true)
						.foregroundColor(.gray)
						.onChange(of: password) {
							if password.utf8.count > 62 {
								password = String(password.dropLast())
							}

							hasChanges = true
						}
				}
				.listRowSeparator(/*@START_MENU_TOKEN@*/.visible/*@END_MENU_TOKEN@*/)

				Toggle(isOn: $tlsEnabled) {
					Label(
						"TLS Enabled",
						systemImage: "checkmark.shield.fill"
					)

					Text("Your MQTT Server must support TLS.")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				.onChange(of: tlsEnabled) {
					hasChanges = true
				}
			}

			Text("For all Mqtt functionality other than the map report you must also set uplink and downlink for each channel you want to bridge over Mqtt.")
				.font(.callout)
		}
		.scrollDismissesKeyboard(.interactively)
		.disabled(bleManager.deviceConnected == nil || node?.mqttConfig == nil)
		.onAppear {
			Analytics.logEvent(AnalyticEvents.optionsMQTT.id, parameters: [:])
		}

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			let connectedNode = getNodeInfo(id: bleManager.deviceConnected?.num ?? -1, context: context)

			if let connectedNode {
				var mqtt = ModuleConfig.MQTTConfig()
				mqtt.enabled = enabled
				mqtt.proxyToClientEnabled = proxyToClientEnabled
				mqtt.address = address
				mqtt.username = username
				mqtt.password = password
				mqtt.root = root
				mqtt.encryptionEnabled = encryptionEnabled
				mqtt.jsonEnabled = jsonEnabled
				mqtt.tlsEnabled = tlsEnabled
				mqtt.mapReportingEnabled = mapReportingEnabled
				mqtt.mapReportSettings.positionPrecision = UInt32(mapPositionPrecision)
				mqtt.mapReportSettings.publishIntervalSecs = UInt32(mapPublishIntervalSecs)

				let adminMessageId = nodeConfig.saveMQTTConfig(
					config: mqtt,
					fromUser: connectedNode.user!,
					toUser: node!.user!,
					adminIndex: connectedNode.myInfo?.adminIndex ?? 0
				)

				if adminMessageId > 0 {
					// Should show a saved successfully alert once I know that to be true
					// for now just disable the button after a successful save
					hasChanges = false
					goBack()
				}
			}
		}
		.navigationTitle("MQTT Config")
		.navigationBarItems(
			trailing: ConnectedDevice()
		)
		.onAppear {
			setMqttValues()

			// Need to request a TelemetryModuleConfig from the remote node before allowing changes
			if
				let node,
				let peripheral = bleManager.deviceConnected,
				let connectedNode = getNodeInfo(id: peripheral.num, context: context),
				node.mqttConfig == nil
			{
				Logger.mesh.info("empty mqtt module config")

				nodeConfig.requestMQTTModuleConfig(
					fromUser: connectedNode.user!,
					toUser: node.user!,
					adminIndex: connectedNode.myInfo?.adminIndex ?? 0
				)
			}
		}
	}

	private func setMqttValues() {
		if mapPositionPrecision == 0 {
			mapPositionPrecision = 12
		}
		preciseLocation = mapPositionPrecision == 32

		if let config = node?.mqttConfig {
			enabled = config.enabled
			proxyToClientEnabled = config.proxyToClientEnabled

			address = config.address ?? ""
			username = config.username ?? ""
			password = config.password ?? ""
			root = config.root ?? "msh"

			encryptionEnabled = config.encryptionEnabled
			jsonEnabled = config.jsonEnabled
			tlsEnabled = config.tlsEnabled
			mapReportingEnabled = config.mapReportingEnabled
			mapPublishIntervalSecs = Int(config.mapPublishIntervalSecs)
			mapPositionPrecision = Double(config.mapPositionPrecision)
		}
		else {
			enabled = false
			proxyToClientEnabled = false

			address = ""
			username = ""
			password = ""
			root = "msh"

			encryptionEnabled = false
			jsonEnabled = false
			tlsEnabled = false
			mapReportingEnabled = false
			mapPublishIntervalSecs = Int(3600)
			mapPositionPrecision = Double(12)
		}

		hasChanges = false
	}
}
