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
	var description: String {
		switch self {
		case .client:
			return "device.role.client".localized
		case .clientMute:
			return "device.role.clientmute".localized
		case .router:
			return "device.role.router".localized
		case .routerClient:
			return "device.role.routerclient".localized
		case .repeater:
			return "device.role.repeater".localized
		case .tracker:
			return "device.role.tracker".localized
		case .sensor:
			return "device.role.sensor".localized
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
		switch self {
		case .all:
			return "All"
		case .allSkipDecoding:
			return "All Skip Decoding"
		case .localOnly:
			return "Local Only"
		}
	}
	var description: String {
		switch self {
		case .all:
			return "Rebroadcast any observed message, if it was on our private channel or from another mesh with the same lora params."
		case .allSkipDecoding:
			return "Same as behavior as ALL but skips packet decoding and simply rebroadcasts them. Only available in Repeater role. Setting this on any other roles will result in ALL behavior."
		case .localOnly:
			return "Ignores observed messages from foreign meshes that are open or those which it cannot decrypt. Only rebroadcasts message on the nodes local primary / secondary channels."
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
