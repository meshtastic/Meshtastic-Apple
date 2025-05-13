//
//  NetworkConfig.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 8/1/2022
//
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct NetworkConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	@State var hasChanges: Bool = false
	@State var wifiEnabled = false
	@State var wifiSsid = ""
	@State var wifiPsk = ""
	@State var wifiMode = 0
	@State var ntpServer = ""
	@State var ethEnabled = false
	@State var ethMode = 0
	@State var udpEnabled = false

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Network", config: \.networkConfig, node: node, onAppear: setNetworkValues)

				if let node {
					if node.metadata?.hasWifi ?? false {
						Section(header: Text("WiFi Options")) {

							Toggle(isOn: $wifiEnabled) {
								Label("Enabled", systemImage: "wifi")
								Text("Enabling WiFi will disable the bluetooth connection to the app.")
							}
							.toggleStyle(SwitchToggleStyle(tint: .accentColor))

							HStack {
								Label("SSID", systemImage: "network")
								TextField("SSID", text: $wifiSsid)
									.foregroundColor(.gray)
									.autocapitalization(.none)
									.disableAutocorrection(true)
									.onChange(of: wifiSsid) {
										var totalBytes = wifiSsid.utf8.count
										// Only mess with the value if it is too big
										while totalBytes > 32 {
											wifiSsid = String(wifiSsid.dropLast())
											totalBytes = wifiSsid.utf8.count
										}
										hasChanges = true
									}
									.foregroundColor(.gray)
							}
							.keyboardType(.default)
							HStack {
								Label("Password", systemImage: "wallet.pass")
								TextField("Password", text: $wifiPsk)
									.foregroundColor(.gray)
									.autocapitalization(.none)
									.disableAutocorrection(true)
									.onChange(of: wifiPsk) {
										var totalBytes = wifiPsk.utf8.count
										// Only mess with the value if it is too big
										while totalBytes > 63 {
											wifiPsk = String(wifiPsk.dropLast())
											totalBytes = wifiPsk.utf8.count
										}
										hasChanges = true
									}
									.foregroundColor(.gray)
							}
							.keyboardType(.default)
						}
					}
					if node.metadata?.hasEthernet ?? false {
						Section(header: Text("Ethernet Options")) {
							Toggle(isOn: $ethEnabled) {
								Label("Enabled", systemImage: "network")
								Text("Enabling Ethernet will disable the bluetooth connection to the app.")
							}
							.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						}
					}

					if node.metadata?.hasEthernet ?? false || node.metadata?.hasWifi ?? false {
						Section(header: Text("UDP Broadcast")) {
							Toggle(isOn: $udpEnabled) {
								Label("Enabled", systemImage: "point.3.connected.trianglepath.dotted")
								Text("Enable broadcasting packets via UDP over the local network.")
							}
						}
					}
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.disabled(self.bleManager.connectedPeripheral == nil || node?.networkConfig == nil)

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if connectedNode != nil {
					var network = Config.NetworkConfig()
					network.wifiEnabled = self.wifiEnabled
					network.wifiSsid = self.wifiSsid
					network.wifiPsk = self.wifiPsk
					network.ethEnabled = self.ethEnabled
					network.enabledProtocols = self.udpEnabled ? UInt32(Config.NetworkConfig.ProtocolFlags.udpBroadcast.rawValue) : UInt32(Config.NetworkConfig.ProtocolFlags.noBroadcast.rawValue)
					// network.addressMode = Config.NetworkConfig.AddressMode.dhcp

					let adminMessageId =  bleManager.saveNetworkConfig(config: network, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
		}
		.navigationTitle("Network Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: bleManager.connectedPeripheral?.shortName ?? "?"
				)
			}
		)
		.onAppear {
			// Need to request a NetworkConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.networkConfig == nil {
				Logger.mesh.info("empty network config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestNetworkConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onFirstAppear {
			// Need to request a NetworkConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if node.num != connectedNode.num {
						if UserDefaults.enableAdministration {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.networkConfig == nil {
								Logger.mesh.info("⚙️ Empty or expired network config requesting via PKI admin")
								_ = bleManager.requestNetworkConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
						}
					}
				}
			}
		}
		.onChange(of: wifiEnabled) { _, newEnabled in
			if newEnabled != node?.networkConfig?.wifiEnabled { hasChanges = true }
		}
		.onChange(of: wifiSsid) { _, newSSID in
			if newSSID != node?.networkConfig?.wifiSsid { hasChanges = true }
		}
		.onChange(of: wifiPsk) { _, newPsk in
			if newPsk != node?.networkConfig?.wifiPsk { hasChanges = true }
		}
		.onChange(of: wifiMode) { _, newMode in
			if newMode != node?.networkConfig?.wifiMode ?? -1 { hasChanges = true }
		}
		.onChange(of: ethEnabled) { _, newEthEnabled in
			if newEthEnabled != node?.networkConfig?.ethEnabled { hasChanges = true }
		}.onChange(of: udpEnabled) {_, newUdpEnabled in
			if let netConfig = node?.networkConfig {
				let newValue: UInt32
				if newUdpEnabled {
					newValue = UInt32(netConfig.enabledProtocols) | UInt32(Config.NetworkConfig.ProtocolFlags.udpBroadcast.rawValue)
				} else {
					newValue = UInt32(netConfig.enabledProtocols) & ~UInt32(Config.NetworkConfig.ProtocolFlags.udpBroadcast.rawValue)
				}
				if netConfig.enabledProtocols != Int32(newValue) {
					netConfig.enabledProtocols = Int32(newValue)
					hasChanges = true
				}
			}
		}
	}

	func setNetworkValues() {
		self.wifiEnabled = node?.networkConfig?.wifiEnabled ?? false
		self.wifiSsid = node?.networkConfig?.wifiSsid ?? ""
		self.wifiPsk = node?.networkConfig?.wifiPsk ?? ""
		self.wifiMode = Int(node?.networkConfig?.wifiMode ?? 0)
		self.ethEnabled = node?.networkConfig?.ethEnabled ?? false
		let enabledProtocols = UInt32(node?.networkConfig?.enabledProtocols ?? Int32(Config.NetworkConfig.ProtocolFlags.noBroadcast.rawValue))
		self.udpEnabled = enabledProtocols & UInt32(Config.NetworkConfig.ProtocolFlags.udpBroadcast.rawValue) != 0
		self.hasChanges = false
	}
}
