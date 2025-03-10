//
//  DeviceRoles.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation
import MeshtasticProtobufs

// Default of 0 is Client
enum DeviceRoles: Int, CaseIterable, Identifiable {

	case client = 0
	case clientMute = 1
	case clientHidden = 8
	case tracker = 5
	case lostAndFound = 9
	case sensor = 6
	case tak = 7
	case takTracker = 10
	case repeater = 4
	case router = 2
	case routerClient = 3
	case routerLate = 11

	var id: Int { self.rawValue }
	var name: String {
		switch self {
		case .client:
			return "device.role.name.client".localized
		case .clientMute:
			return "device.role.name.clientMute".localized
		case .router:
			return "device.role.name.router".localized
		case .routerClient:
			return "device.role.name.routerClient".localized
		case .repeater:
			return "device.role.name.repeater".localized
		case .tracker:
			return "device.role.name.tracker".localized
		case .sensor:
			return "device.role.name.sensor".localized
		case .tak:
			return "device.role.name.tak".localized
		case .takTracker:
			return "device.role.name.takTracker".localized
		case .clientHidden:
			return "device.role.name.clientHidden".localized
		case .lostAndFound:
			return "device.role.name.lostAndFound".localized
		case .routerLate:
			return "device.role.name.routerlate".localized
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
		case .tak:
			return "device.role.tak".localized
		case .takTracker:
			return "device.role.taktracker".localized
		case .clientHidden:
			return "device.role.clienthidden".localized
		case .lostAndFound:
			return "device.role.lostandfound".localized
		case .routerLate:
			return "device.role.routerlate".localized
		}
	}

	var systemName: String {
		switch self {
		case .client:
			return "apps.iphone"
		case .clientMute:
			return "speaker.slash"
		case .router, .routerClient, .routerLate:
			return "wifi.router"
		case .repeater:
			return "repeat"
		case .tracker:
			return "mappin.and.ellipse.circle"
		case .sensor:
			return "sensor"
		case .tak:
			return "shield.checkered"
		case .takTracker:
			return "dog"
		case .clientHidden:
			return "eye.slash"
		case .lostAndFound:
			return "map"
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
		case .tak:
			return Config.DeviceConfig.Role.tak
		case .takTracker:
			return Config.DeviceConfig.Role.takTracker
		case .clientHidden:
			return Config.DeviceConfig.Role.clientHidden
		case .lostAndFound:
			return Config.DeviceConfig.Role.lostAndFound
		case .routerLate:
			return Config.DeviceConfig.Role.routerLate
		}
	}
}

enum RebroadcastModes: Int, CaseIterable, Identifiable {

	case all = 0
	case allSkipDecoding = 1
	case localOnly = 2
	case knownOnly = 3
	case corePortnums = 4

	var id: Int { self.rawValue }

	var name: String {
		switch self {
		case .all:
			return "All"
		case .allSkipDecoding:
			return "All Skip Decoding"
		case .localOnly:
			return "Local Only"
		case .knownOnly:
			return "Known Only"
		case .corePortnums:
			return "Core Portnums Only"
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
		case .knownOnly:
			return "Ignores observed messages from foreign meshes like Local Only, but takes it step further by also ignoring messages from nodes not already in the node's known list."
		case .corePortnums:
			return "Only rebroadcasts packets from the core portnums: NodeInfo, Text, Position, Telemetry, and Routing."
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
		case .knownOnly:
			return Config.DeviceConfig.RebroadcastMode.knownOnly
		case .corePortnums:
			return Config.DeviceConfig.RebroadcastMode.corePortnumsOnly
		}
	}
}
