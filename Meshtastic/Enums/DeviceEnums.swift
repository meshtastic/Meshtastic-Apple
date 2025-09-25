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
	case router = 2
	case routerLate = 11
	case clientBase = 12

	var id: Int { self.rawValue }
	var name: String {
		switch self {
		case .client:
			return "Client".localized
		case .clientMute:
			return "Client Mute".localized
		case .router:
			return "Router".localized
		case .tracker:
			return "Tracker".localized
		case .sensor:
			return "Sensor".localized
		case .tak:
			return "TAK".localized
		case .takTracker:
			return "TAK Tracker".localized
		case .clientHidden:
			return "Client Hidden".localized
		case .lostAndFound:
			return "Lost and Found".localized
		case .routerLate:
			return "Router Late".localized
		case .clientBase:
			return "Client Base".localized
		}

	}
	var description: String {
		switch self {
		case .client:
			return "App connected or stand alone messaging device.".localized
		case .clientMute:
			return "Device that does not forward packets from other devices.".localized
		case .router:
			return "Infrastructure node on a tower or mountain top only.  Not to be used for roofs or mobile nodes.  Needs exceptional coverage. Visible in Nodes list.".localized
		case .tracker:
			return "Broadcasts GPS position packets as priority.".localized
		case .sensor:
			return "Broadcasts telemetry packets as priority.".localized
		case .tak:
			return "Optimized for ATAK system communication, reduces routine broadcasts.".localized
		case .takTracker:
			return "Enables automatic TAK PLI broadcasts and reduces routine broadcasts.".localized
		case .clientHidden:
			return "Device that only broadcasts as needed for stealth or power savings.".localized
		case .lostAndFound:
			return "Broadcasts location as message to default channel regularly for to assist with device recovery.".localized
		case .routerLate:
			return "Infrastructure node that always rebroadcasts packets once but only after all other modes. Visible in Nodes list. Not a good choice for rooftop nodes.".localized
		case .clientBase:
			return "Used for rooftop nodes to distribute messages more widely from multiple nearby client mute nodes.".localized
		}
	}

	var systemName: String {
		switch self {
		case .client:
			return "apps.iphone"
		case .clientMute:
			return "speaker.slash"
		case .router, .routerLate:
			return "wifi.router"
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
		case .clientBase:
			return "house"
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
		case .clientBase:
			return Config.DeviceConfig.Role.clientBase
		}
	}
}

enum RebroadcastModes: Int, CaseIterable, Identifiable {

	case all = 0
	case allSkipDecoding = 1
	case localOnly = 2
	case knownOnly = 3
	case none = 4
	case corePortnums = 5

	var id: Int { self.rawValue }

	var name: String {
		switch self {
		case .all:
			return "All".localized
		case .allSkipDecoding:
			return "All Skip Decoding".localized
		case .localOnly:
			return "Local Only".localized
		case .knownOnly:
			return "Known Only".localized
		case .none:
			return "None".localized
		case .corePortnums:
			return "Core Portnums Only".localized
		}
	}
	var description: String {
		switch self {
		case .all:
			return "Rebroadcast any observed message, if it was on our private channel or from another mesh with the same lora params.".localized
		case .allSkipDecoding:
			return "Same as behavior as ALL but skips packet decoding and simply rebroadcasts them. Only available in Repeater role. Setting this on any other roles will result in ALL behavior.".localized
		case .localOnly:
			return "Ignores observed messages from foreign meshes that are open or those which it cannot decrypt. Only rebroadcasts message on the nodes local primary / secondary channels.".localized
		case .knownOnly:
			return "Ignores observed messages from foreign meshes like Local Only, but takes it step further by also ignoring messages from nodes not already in the node's known list.".localized
		case .none:
			return "Only permitted for SENSOR, TRACKER and TAK_TRACKER roles, this will inhibit all rebroadcasts, not unlike CLIENT_MUTE role.".localized
		case .corePortnums:
			return "Only rebroadcasts packets from the core portnums: NodeInfo, Text, Position, Telemetry, and Routing.".localized
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
		case .none:
			return Config.DeviceConfig.RebroadcastMode.none
		case .corePortnums:
			return Config.DeviceConfig.RebroadcastMode.corePortnumsOnly
		}
	}
}
