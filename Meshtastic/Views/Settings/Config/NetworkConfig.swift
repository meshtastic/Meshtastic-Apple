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

	@State private var isPresentingSaveConfirm: Bool = false
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
				if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					Text("There has been no response to a request for device metadata over the admin channel for this node.")
						.font(.callout)
						.foregroundColor(.orange)

				} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					// Let users know what is going on if they are using remote admin and don't have the config yet
					if node?.networkConfig == nil {
						Text("Network config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
							.font(.callout)
							.foregroundColor(.orange)
					} else {
						Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
							.font(.title3)
							.onAppear {
								setNetworkValues()
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
				if (node != nil && node?.metadata?.hasWifi ?? false) {
					Section(header: Text("WiFi Options")) {
						Toggle(isOn: $wifiEnabled) {
							Label("enabled", systemImage: "wifi")
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
						Text("Enabling WiFi will disable the bluetooth connection to the app.")
							.font(.callout)
					}
				}
				if (node != nil && node?.metadata?.hasEthernet ?? false) {
					Section(header: Text("Ethernet Options")) {
						Toggle(isOn: $ethEnabled) {
							Label("enabled", systemImage: "network")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						Text("Enabling Ethernet will disable the bluetooth connection to the app.")
							.font(.callout)
					}
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.disabled(self.bleManager.connectedPeripheral == nil || node?.networkConfig == nil)
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
				let nodeName = node?.user?.longName ?? "unknown".localized
				let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
				Button(buttonText) {
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
			} message: {
				Text("config.save.confirm")
			}
		}
		.navigationTitle("network.config")
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			self.bleManager.context = context
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
