//
//  DeviceRoles.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation

// Default of 0 is Client
enum DeviceRoles: Int, CaseIterable, Identifiable {

	case client = 0
	case clientMute = 1
	case router = 2
	case routerClient = 3

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			
			case .client:
				return NSLocalizedString("device.role.client", comment: "Client (default) - App connected client.")
			case .clientMute:
				return NSLocalizedString("device.role.clientmute", comment: "Client Mute - Same as a client except packets will not hop over this node, does not contribute to routing packets for mesh.")
			case .router:
				return NSLocalizedString("device.role.router", comment: "Router -  Mesh packets will prefer to be routed over this node. This node will not be used by client apps. The wifi/ble radios and the oled screen will be put to sleep.")
			case .routerClient:
				return NSLocalizedString("device.role.routerclient", comment: "Router Client - Mesh packets will prefer to be routed over this node. The Router Client can be used as both a Router and an app connected Client.")
			}
		}
	}
	func protoEnumValue() -> Config.DeviceConfig.Role {
		
		switch self {
			
		case .client:
			return Config.DeviceConfig.Role.client
		case .clientMute:
			return Config.DeviceConfig.Role.clientMute
		case .router:
			return Config.DeviceConfig.Role.router
		case .routerClient:
			return Config.DeviceConfig.Role.routerClient
		}
	}
}
