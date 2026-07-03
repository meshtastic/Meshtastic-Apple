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
		let staticValid = staticConfigIsValid
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
								TextField("192.168.1.10", text: $staticIp)
									.foregroundColor(Self.isRequiredIPv4FieldValid(staticIp) ? .gray : .red)
									.keyboardType(.numbersAndPunctuation)
							}
							HStack {
								Label("Gateway", systemImage: "arrow.triangle.branch")
								TextField("192.168.1.1", text: $staticGateway)
									.foregroundColor(Self.isRequiredIPv4FieldValid(staticGateway) ? .gray : .red)
									.keyboardType(.numbersAndPunctuation)
							}
							HStack {
								Label("Subnet", systemImage: "circle.grid.cross")
								TextField("255.255.255.0", text: $staticSubnet)
									.foregroundColor(Self.isRequiredIPv4FieldValid(staticSubnet) ? .gray : .red)
									.keyboardType(.numbersAndPunctuation)
							}
							HStack {
								Label("DNS", systemImage: "magnifyingglass")
								TextField("Optional", text: $staticDns)
									.foregroundColor(Self.isValidIPv4Field(staticDns) ? .gray : .red)
									.keyboardType(.numbersAndPunctuation)
							}
							if !staticValid {
								Text("IP, gateway, and subnet are required and must be valid IPv4 addresses (e.g. 192.168.1.10). DNS may be left blank.")
									.font(.callout)
									.foregroundColor(.red)
									.fixedSize(horizontal: false, vertical: true)
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
			.disabled(!staticValid)
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

	// Firmware stores IPv4 addresses little-endian (first octet = least-significant
	// byte), matching the Arduino IPAddress / Android convention. Encode and decode
	// must use the same order or addresses display and write byte-reversed.
	func ipStringToUInt32(_ ipString: String) -> UInt32 {
		let parts = ipString.split(separator: ".").compactMap { UInt32($0) }
		guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return 0 }
		return parts[0] | (parts[1] << 8) | (parts[2] << 16) | (parts[3] << 24)
	}

	/// True when the field holds a well-formed IPv4 address. An empty field is allowed here —
	/// callers decide whether a blank value is acceptable for a given field (see
	/// `staticConfigIsValid`). A non-empty value must be a complete, in-range dotted quad with
	/// each octet 1-3 ASCII digits, which also rejects sign characters and whitespace that
	/// `UInt32` alone would accept. Without this, `ipStringToUInt32` silently turns a typo like
	/// `192.168.1` or `192.168.1.300` into 0.0.0.0 and writes it to the firmware.
	static func isValidIPv4Field(_ ipString: String) -> Bool {
		if ipString.isEmpty { return true }
		let parts = ipString.split(separator: ".", omittingEmptySubsequences: false)
		guard parts.count == 4 else { return false }
		return parts.allSatisfy { part in
			guard part.count <= 3,
				part.allSatisfy({ $0.isASCII && $0.isNumber }),
				let value = UInt32(part) else { return false }
			return value <= 255
		}
	}

	/// Field-tint helper for IP / gateway / subnet, which are required in static mode: blank
	/// reads as invalid so the field shows red and the user can see what is blocking Save.
	/// DNS keeps the plain `isValidIPv4Field` check since blank DNS is allowed.
	static func isRequiredIPv4FieldValid(_ ipString: String) -> Bool {
		!ipString.isEmpty && isValidIPv4Field(ipString)
	}

	/// Pure save-gating logic, kept free of `@State` so it can be unit-tested directly. Always
	/// true in DHCP mode, where the static fields are ignored. In static mode the save is
	/// blocked when any field holds a malformed address (e.g. `192.168.1` or `192.168.1.300`,
	/// which `ipStringToUInt32` would silently write as 0.0.0.0), and when IP, gateway, or
	/// subnet is blank — a static config without them is non-functional, the same class of
	/// silently-broken config as a typo. DNS is the one optional field: blank means "unset"
	/// (written as 0.0.0.0), matching how the firmware round-trips an unconfigured field
	/// (`uint32ToIpString(0)` is "").
	static func isStaticConfigValid(addressMode: Int, ip: String, gateway: String, subnet: String, dns: String) -> Bool {
		guard addressMode == 1 else { return true }
		return !ip.isEmpty && isValidIPv4Field(ip)
			&& !gateway.isEmpty && isValidIPv4Field(gateway)
			&& !subnet.isEmpty && isValidIPv4Field(subnet)
			&& isValidIPv4Field(dns)
	}

	/// Drives the Save button's `.disabled` and the inline error text. Thin wrapper over the
	/// testable `isStaticConfigValid(...)`.
	var staticConfigIsValid: Bool {
		Self.isStaticConfigValid(addressMode: addressMode, ip: staticIp, gateway: staticGateway, subnet: staticSubnet, dns: staticDns)
	}

	func uint32ToIpString(_ value: UInt32) -> String {
		if value == 0 { return "" }
		let a = value & 0xFF
		let b = (value >> 8) & 0xFF
		let c = (value >> 16) & 0xFF
		let d = (value >> 24) & 0xFF
		return "\(a).\(b).\(c).\(d)"
	}
}

#Preview {
	NetworkConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
