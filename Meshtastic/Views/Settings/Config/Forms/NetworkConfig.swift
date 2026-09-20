//
//  NetworkConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import SwiftUI
import MeshtasticProtobufs

extension Config.NetworkConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, NetworkConfigEntity?> = \NodeInfoEntity.networkConfig

	init(entity: NetworkConfigEntity) {
		self.init()
		wifiEnabled = entity.wifiEnabled
		wifiSsid = entity.wifiSsid ?? ""
		wifiPsk = entity.wifiPsk ?? ""
		ethEnabled = entity.ethEnabled
		addressMode = AddressMode(rawValue: Int(entity.addressMode)) ?? .dhcp
		ntpServer = entity.ntpServer ?? ""
		rsyslogServer = entity.rsyslogServer ?? ""
		enabledProtocols = UInt32(truncatingIfNeeded: entity.enabledProtocols)
		var ipv4 = IpV4Config()
		ipv4.ip = UInt32(truncatingIfNeeded: entity.ip)
		ipv4.gateway = UInt32(truncatingIfNeeded: entity.gateway)
		ipv4.subnet = UInt32(truncatingIfNeeded: entity.subnet)
		ipv4.dns = UInt32(truncatingIfNeeded: entity.dns)
		ipv4Config = ipv4
	}
}

struct NetworkConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = Config.NetworkConfig.Fields

	/// A static configuration the radio cannot use is worse than no change at all: a
	/// half-typed address lands as 0.0.0.0 and the node comes back unreachable. Address,
	/// gateway and subnet must all be present and well formed. A blank DNS means unset.
	static func canSave(_ config: Config.NetworkConfig) -> Bool {
		guard config.addressMode == .static else { return true }
		let ipv4 = config.ipv4Config
		return IPv4Address.isRequiredFieldValid(IPv4Address.toString(ipv4.ip))
			&& IPv4Address.isRequiredFieldValid(IPv4Address.toString(ipv4.gateway))
			&& IPv4Address.isRequiredFieldValid(IPv4Address.toString(ipv4.subnet))
			&& IPv4Address.isFieldValid(IPv4Address.toString(ipv4.dns))
	}

	static func overlay() -> ConfigFormOverlay<Config.NetworkConfig> {
		// Which of these a radio has is hardware, not configuration, so the schema
		// cannot say. A board with neither shows nothing below the header.
		let hasWifi = ConfigFormCondition<Config.NetworkConfig>.hasWifi
		let hasEthernet = ConfigFormCondition<Config.NetworkConfig>.hasEthernet
		let networked = ConfigFormCondition<Config.NetworkConfig>.any([hasWifi, hasEthernet])
		let isStatic = ConfigFormCondition<Config.NetworkConfig>
			.equals(F.addressMode, Config.NetworkConfig.AddressMode.static)
		return .init(sections: [
			.init(title: String(localized: "WiFi Options", comment: "Settings section"),
				  shownWhen: hasWifi, fields: [
				.init(F.wifiEnabled, symbol: "wifi"),
				.init(F.wifiSsid, symbol: "network", byteCap: 32),
				.init(F.wifiPsk, symbol: "wallet.pass", control: .secure, byteCap: 63)
			]),
			// Its own section rather than nested inside the WiFi one, which is where it
			// used to live: an Ethernet-only board never saw this toggle.
			.init(title: String(localized: "Ethernet Options", comment: "Settings section"),
				  shownWhen: hasEthernet, fields: [
				.init(F.ethEnabled, symbol: "network")
			]),
			.init(title: String(localized: "Network Servers", comment: "Settings section"),
				  shownWhen: networked, fields: [
				.init(F.ntpServer, symbol: "clock", byteCap: 32),
				.init(F.rsyslogServer, symbol: "server.rack", byteCap: 32)
			]),
			.init(title: String(localized: "Address Mode", comment: "Settings section"),
				  shownWhen: networked, fields: [
				.init(F.addressMode, control: .segmented)
			]),
			.init(title: String(localized: "Static IPv4 Configuration", comment: "Settings section"),
				  footer: String(localized: "Address, gateway and subnet are required and must be valid IPv4 addresses. DNS may be left blank.",
								 comment: "Static IPv4 section footer"),
				  shownWhen: .all([networked, isStatic]), fields: [
				.init(F.ipv4Config_ip, symbol: "number", control: .ipv4Address(required: true)),
				.init(F.ipv4Config_gateway, symbol: "arrow.triangle.branch", control: .ipv4Address(required: true)),
				.init(F.ipv4Config_subnet, symbol: "circle.grid.cross", control: .ipv4Address(required: true)),
				.init(F.ipv4Config_dns, symbol: "magnifyingglass", control: .ipv4Address(required: false))
			]),
			.init(title: String(localized: "UDP Broadcast", comment: "Settings section"),
				  shownWhen: networked, fields: [
				.init(F.enabledProtocols, control: .flags([
					.init(rawValue: Config.NetworkConfig.ProtocolFlags.udpBroadcast.rawValue,
						  label: { FieldMetadataRegistry.get("meshtastic.Config.NetworkConfig.ProtocolFlags", tag: 1)?.label },
						  symbol: "point.3.connected.trianglepath.dotted")
				]))
			])
		], omitted: [
			.init(F.ipv6Enabled, "not yet offered by this client; unlabelled upstream")
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Network", overlay: Self.overlay(),
			canSave: Self.canSave,
			request: accessoryManager.requestNetworkConfig,
			save: { config, from, to in
				var config = config
				// DHCP ignores the static fields; sending stale ones invites a later
				// switch to Static to come up with an address nobody chose.
				if config.addressMode != .static { config.ipv4Config = Config.NetworkConfig.IpV4Config() }
				_ = try await accessoryManager.saveNetworkConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Network Config")
	}
}
