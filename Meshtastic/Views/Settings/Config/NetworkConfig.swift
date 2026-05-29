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
	
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	let node: NodeInfoEntity?
	
	@State var hasChanges: Bool = false
	@State var wifiEnabled = false
	@State var wifiSsid = ""
	@State var wifiPsk = ""
	@State var wifiMode = 0
	@State var ntpServer = ""
	@State var rsyslogServer = ""
	@State var ethEnabled = false
	@State var ethMode = 0
	@State var addressMode = 0
	@State var staticIp = ""
	@State var staticGateway = ""
	@State var staticSubnet = ""
	@State var staticDns = ""
	@State var udpEnabled = false
	
	var body: some View {
		Form {
			ConfigHeader(title: "Network", config: \.networkConfig, node: node, onAppear: setNetworkValues)
			
			if let node {
				if node.metadata?.hasWifi ?? false {
					Section(header: Text("WiFi Options")) {
						
						Toggle(isOn: $wifiEnabled) {
							Label("Enabled", systemImage: "wifi")
							Text("Enabling WiFi will disable the bluetooth connection to the app.")
						}
						.tint(.accentColor)
						
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
								}
								.foregroundColor(.gray)
						}
						.keyboardType(.default)
					}
					if node.metadata?.hasEthernet ?? false {
						Section(header: Text("Ethernet Options")) {
							Toggle(isOn: $ethEnabled) {
								Label("Enabled", systemImage: "network")
								Text("Enabling Ethernet will disable the bluetooth connection to the app.")
							}
							.tint(.accentColor)
						}
						.tint(.accentColor)
					}
				}
				
				if node.metadata?.hasEthernet ?? false || node.metadata?.hasWifi ?? false {
					Section(header: Text("Network Servers")) {
						HStack {
							Label("NTP Server", systemImage: "clock")
							TextField("meshtastic.pool.ntp.org", text: $ntpServer)
								.foregroundColor(.gray)
								.autocapitalization(.none)
								.disableAutocorrection(true)
								.onChange(of: ntpServer) {
									var totalBytes = ntpServer.utf8.count
									while totalBytes > 32 {
										ntpServer = String(ntpServer.dropLast())
										totalBytes = ntpServer.utf8.count
									}
								}
						}
						.keyboardType(.default)
						HStack {
							Label("Rsyslog Server", systemImage: "server.rack")
							TextField("Server:Port", text: $rsyslogServer)
								.foregroundColor(.gray)
								.autocapitalization(.none)
								.disableAutocorrection(true)
								.onChange(of: rsyslogServer) {
									var totalBytes = rsyslogServer.utf8.count
									while totalBytes > 32 {
										rsyslogServer = String(rsyslogServer.dropLast())
										totalBytes = rsyslogServer.utf8.count
									}
								}
						}
						.keyboardType(.default)
					}

					Section(header: Text("Address Mode")) {
						Picker("Address Mode", selection: $addressMode) {
							Text("DHCP").tag(0)
							Text("Static").tag(1)
						}
						.pickerStyle(.segmented)
					}

					if addressMode == 1 {
						Section(header: Text("Static IPv4 Configuration")) {
							HStack {
								Label("IP", systemImage: "number")
								TextField("0.0.0.0", text: $staticIp)
									.foregroundColor(.gray)
									.keyboardType(.decimalPad)
							}
							HStack {
								Label("Gateway", systemImage: "arrow.triangle.branch")
								TextField("0.0.0.0", text: $staticGateway)
									.foregroundColor(.gray)
									.keyboardType(.decimalPad)
							}
							HStack {
								Label("Subnet", systemImage: "circle.grid.cross")
								TextField("255.255.255.0", text: $staticSubnet)
									.foregroundColor(.gray)
									.keyboardType(.decimalPad)
							}
							HStack {
								Label("DNS", systemImage: "magnifyingglass")
								TextField("0.0.0.0", text: $staticDns)
									.foregroundColor(.gray)
									.keyboardType(.decimalPad)
							}
						}
					}

					Section(header: Text("UDP Broadcast")) {
						Toggle(isOn: $udpEnabled) {
							Label("Enabled", systemImage: "point.3.connected.trianglepath.dotted")
							Text("Enable broadcasting packets via UDP over the local network.")
						}
						.tint(.accentColor)
					}
				}
			}
		}
		.scrollDismissesKeyboard(.interactively)
		.disabled(!accessoryManager.isConnected || node?.networkConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				performConfigSave(
					node: node,
					context: context,
					accessoryManager: accessoryManager,
					hasChanges: $hasChanges,
					dismiss: goBack
				) { fromUser, toUser in
					var network = Config.NetworkConfig()
					network.wifiEnabled = self.wifiEnabled
					network.wifiSsid = self.wifiSsid
					network.wifiPsk = self.wifiPsk
					network.ntpServer = self.ntpServer
					network.rsyslogServer = self.rsyslogServer
					network.ethEnabled = self.ethEnabled
					network.enabledProtocols = self.udpEnabled ? UInt32(Config.NetworkConfig.ProtocolFlags.udpBroadcast.rawValue) : UInt32(Config.NetworkConfig.ProtocolFlags.noBroadcast.rawValue)
					network.addressMode = Config.NetworkConfig.AddressMode(rawValue: self.addressMode) ?? .dhcp
					if self.addressMode == 1 {
						var ipv4 = Config.NetworkConfig.IpV4Config()
						ipv4.ip = self.ipStringToUInt32(self.staticIp)
						ipv4.gateway = self.ipStringToUInt32(self.staticGateway)
						ipv4.subnet = self.ipStringToUInt32(self.staticSubnet)
						ipv4.dns = self.ipStringToUInt32(self.staticDns)
						network.ipv4Config = ipv4
					}
					_ = try await accessoryManager.saveNetworkConfig(config: network, fromUser: fromUser, toUser: toUser)
				}
			}
			}
		}
		.navigationTitle("Network Config")
		.toolbar {
	ToolbarItem(placement: .topBarTrailing) {
		ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
	}
}
		.onAppear {
			// Need to request a NetworkConfig from the remote node before allowing changes
			if accessoryManager.isConnected && node?.networkConfig == nil {
				Logger.mesh.info("empty network config")
				if let deviceNum = accessoryManager.activeDeviceNum, let connectedNode = getNodeInfo(id: deviceNum, context: context), node != nil {
					Task {
						try await accessoryManager.requestNetworkConfig(fromUser: connectedNode.user!, toUser: node!.user!)
					}
				}
			}
		}
		.onFirstAppear {
			requestRemoteConfig(
				node: node,
				context: context,
				accessoryManager: accessoryManager,
				configIsNil: { $0.networkConfig == nil },
				request: accessoryManager.requestNetworkConfig
			)
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
		}
		.onChange(of: ntpServer) { _, newValue in
			if newValue != (node?.networkConfig?.ntpServer ?? "") { hasChanges = true }
		}
		.onChange(of: rsyslogServer) { _, newValue in
			if newValue != (node?.networkConfig?.rsyslogServer ?? "") { hasChanges = true }
		}
		.onChange(of: addressMode) { _, newValue in
			if newValue != Int(node?.networkConfig?.addressMode ?? 0) { hasChanges = true }
		}
		.onChange(of: staticIp) { _, newValue in
			if newValue != self.uint32ToIpString(UInt32(bitPattern: node?.networkConfig?.ip ?? 0)) { hasChanges = true }
		}
		.onChange(of: staticGateway) { _, newValue in
			if newValue != self.uint32ToIpString(UInt32(bitPattern: node?.networkConfig?.gateway ?? 0)) { hasChanges = true }
		}
		.onChange(of: staticSubnet) { _, newValue in
			if newValue != self.uint32ToIpString(UInt32(bitPattern: node?.networkConfig?.subnet ?? 0)) { hasChanges = true }
		}
		.onChange(of: staticDns) { _, newValue in
			if newValue != self.uint32ToIpString(UInt32(bitPattern: node?.networkConfig?.dns ?? 0)) { hasChanges = true }
		}
		.onChange(of: udpEnabled) {_, newUdpEnabled in
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
		self.ntpServer = node?.networkConfig?.ntpServer ?? ""
		self.rsyslogServer = node?.networkConfig?.rsyslogServer ?? ""
		self.ethEnabled = node?.networkConfig?.ethEnabled ?? false
		self.addressMode = Int(node?.networkConfig?.addressMode ?? 0)
		self.staticIp = self.uint32ToIpString(UInt32(bitPattern: node?.networkConfig?.ip ?? 0))
		self.staticGateway = self.uint32ToIpString(UInt32(bitPattern: node?.networkConfig?.gateway ?? 0))
		self.staticSubnet = self.uint32ToIpString(UInt32(bitPattern: node?.networkConfig?.subnet ?? 0))
		self.staticDns = self.uint32ToIpString(UInt32(bitPattern: node?.networkConfig?.dns ?? 0))
		let enabledProtocols = UInt32(node?.networkConfig?.enabledProtocols ?? Int32(Config.NetworkConfig.ProtocolFlags.noBroadcast.rawValue))
		self.udpEnabled = enabledProtocols & UInt32(Config.NetworkConfig.ProtocolFlags.udpBroadcast.rawValue) != 0
		self.hasChanges = false
	}

	func ipStringToUInt32(_ ipString: String) -> UInt32 {
		let parts = ipString.split(separator: ".").compactMap { UInt32($0) }
		guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return 0 }
		return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
	}

	func uint32ToIpString(_ value: UInt32) -> String {
		if value == 0 { return "" }
		let a = (value >> 24) & 0xFF
		let b = (value >> 16) & 0xFF
		let c = (value >> 8) & 0xFF
		let d = value & 0xFF
		return "\(a).\(b).\(c).\(d)"
	}
}

#Preview {
	NetworkConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
