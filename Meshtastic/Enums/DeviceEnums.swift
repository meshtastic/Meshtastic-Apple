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
	case repeater = 4
	case tracker = 5
	case sensor = 6

	var id: Int { self.rawValue }
	var name: String {
		get {
			switch self {
			
			case .client:
				return "Client"
			case .clientMute:
				return "Muted Client"
			case .router:
				return "Router"
			case .routerClient:
				return "Router & Client"
			case .repeater:
				return "Repeater"
			case .tracker:
				return "Tracker"
			case .sensor:
				return "Sensor"
			}
		}
	}
	var description: String {
		get {
			switch self {
			
			case .client:
				return NSLocalizedString("device.role.client", comment: "Client (default) - App connected client.")
			case .clientMute:
				return NSLocalizedString("device.role.clientmute", comment: "Client Mute - Same as a client except packets will not hop over this node, does not contribute to routing packets for mesh.")
			case .router:
				return NSLocalizedString("device.role.router", comment: "Router -  Mesh packets will prefer to be routed over this node. Assumes device will operate in a standalone manner while placed in a location with a coverage advantage. WARNING: The BLE/Wi-Fi radios and the OLED screen will be put to sleep.")
			case .routerClient:
				return NSLocalizedString("device.role.routerclient", comment: "Router Client - Hybrid of the Client and Router roles. Similar to Router, except the Router Client can be used as both a Router and an app connected Client. BLE/Wi-Fi and OLED screen will not be put to sleep.")
			case .repeater:
				return NSLocalizedString("device.role.repeater", comment: "Repeater - Mesh packets will prefer to be routed over this node. This role eliminates unnecessary overhead such as NodeInfo, DeviceTelemetry, and any other mesh packet, resulting in the device not appearing as part of the network.  Please see Rebroadcast Mode for additional settings specific to this role.")
			case .tracker:
				return NSLocalizedString("device.role.tracker", comment: "Tracker - For use with devices intended as a GPS tracker. Position packets sent from this device will be higher priority, with position broadcasting every two minutes. Smart Position Broadcast will default to off.")
			case .sensor:
				return NSLocalizedString("device.role.sensor", comment: "Sensor - For use with remote telemetry sensors. Setting this role will turn on environment telemetry. Telemetry packets sent from this device will be higher priority, with telemetry broadcasting every 7 minutes")
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
		case .repeater:
			return Config.DeviceConfig.Role.repeater
		case .tracker:
			return Config.DeviceConfig.Role.tracker
		case .sensor:
			return Config.DeviceConfig.Role.sensor
		}
	}
}

enum RebroadcastModes: Int, CaseIterable, Identifiable {

	case all = 0
	case allSkipDecoding = 1
	case localOnly = 2

	var id: Int { self.rawValue }
	
	var name: String {
		get {
			switch self {
			
			case .all:
				return "All"
			case .allSkipDecoding:
				return "All Skip Decoding"
			case .localOnly:
				return "Local Only"
			}
		}
	}
	var description: String {
		get {
			switch self {
			case .all:
				return "Rebroadcast any observed message, if it was on our private channel or from another mesh with the same lora params."
			case .allSkipDecoding:
				return "Same as behavior as ALL but skips packet decoding and simply rebroadcasts them. Only available in Repeater role. Setting this on any other roles will result in ALL behavior."
			case .localOnly:
				return "Inverted top bar for 2 Color display"
			}
		}
	}
	func protoEnumValue() -> Config.DeviceConfig.RebroadcastMode {
		
		switch self {
		case .all:
			return Config.DeviceConfig.RebroadcastMode.all
		case .allSkipDecoding:
			return Config.DeviceConfig.RebroadcastMode.allSkipDecoding
		case .localOnly:
			return Config.DeviceConfig.RebroadcastMode.localOnly
		}
	}
}
