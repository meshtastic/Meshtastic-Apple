//
//  NetworkConfig.swift
//  Meshtastic
//
//  Copyright (c) Garth Vander Houwen 8/1/2022
//

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

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Network", config: \.networkConfig, node: node, onAppear: setNetworkValues)
				
				if (node != nil && node?.metadata?.hasWifi ?? false) {
					Section(header: Text("WiFi Options")) {
						
						Toggle(isOn: $wifiEnabled) {
							Label("enabled", systemImage: "wifi")
							Text("Enabling WiFi will disable the bluetooth connection to the app.")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						
						HStack {
							Label("ssid", systemImage: "network")
							TextField("ssid", text: $wifiSsid)
								.foregroundColor(.gray)
								.autocapitalization(.none)
								.disableAutocorrection(true)
								.onChange(of: wifiSsid, perform: { _ in
									let totalBytes = wifiSsid.utf8.count
									// Only mess with the value if it is too big
									if totalBytes > 32 {
										let firstNBytes = Data(wifiSsid.utf8.prefix(32))
										if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
											// Set the shortName back to the last place where it was the right size
											wifiSsid = maxBytesString
										}
									}
									hasChanges = true
								})
								.foregroundColor(.gray)
						}
						.keyboardType(.default)
						HStack {
							Label("password", systemImage: "wallet.pass")
							TextField("password", text: $wifiPsk)
								.foregroundColor(.gray)
								.autocapitalization(.none)
								.disableAutocorrection(true)
								.onChange(of: wifiPsk, perform: { _ in
									let totalBytes = wifiPsk.utf8.count
									// Only mess with the value if it is too big
									if totalBytes > 63 {
										let firstNBytes = Data(wifiPsk.utf8.prefix(63))
										if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
											// Set the shortName back to the last place where it was the right size
											wifiPsk = maxBytesString
										}
									}
									hasChanges = true
								})
								.foregroundColor(.gray)
						}
						.keyboardType(.default)
					}
				}
				if (node != nil && node?.metadata?.hasEthernet ?? false) {
					Section(header: Text("Ethernet Options")) {
						Toggle(isOn: $ethEnabled) {
							Label("enabled", systemImage: "network")
							Text("Enabling Ethernet will disable the bluetooth connection to the app.")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
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
		.navigationTitle("network.config")
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
			setNetworkValues()
			// Need to request a NetworkConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.networkConfig == nil {
				print("empty network config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestNetworkConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: wifiEnabled) { newEnabled in
			if node != nil && node!.networkConfig != nil {
				if newEnabled != node!.networkConfig!.wifiEnabled { hasChanges = true }
			}
		}
		.onChange(of: wifiSsid) { newSSID in
			if node != nil && node!.networkConfig != nil {
				if newSSID != node!.networkConfig!.wifiSsid { hasChanges = true }
			}
		}
		.onChange(of: wifiPsk) { newPsk in
			if node != nil && node!.networkConfig != nil {
				if newPsk != node!.networkConfig!.wifiPsk { hasChanges = true }
			}
		}
		.onChange(of: wifiMode) { newMode in
			if node != nil && node!.networkConfig != nil {
				if newMode != node!.networkConfig!.wifiMode { hasChanges = true }
			}
		}
		.onChange(of: ethEnabled) { newEthEnabled in
			if node != nil && node!.networkConfig != nil {
				if newEthEnabled != node!.networkConfig!.ethEnabled { hasChanges = true }
			}
		}
	}
	func setNetworkValues() {
		self.wifiEnabled = node?.networkConfig?.wifiEnabled ?? false
		self.wifiSsid = node?.networkConfig?.wifiSsid ?? ""
		self.wifiPsk = node?.networkConfig?.wifiPsk ?? ""
		self.wifiMode = Int(node?.networkConfig?.wifiMode ?? 0)
		self.ethEnabled = node?.networkConfig?.ethEnabled ?? false
		self.hasChanges = false
	}
}
