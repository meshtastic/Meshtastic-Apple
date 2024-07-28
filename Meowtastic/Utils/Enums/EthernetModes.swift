//
//  NetworkEnums.swift
//  Meshtastic
//
//  Copyright(C) Garth Vander Houwen 11/25/22.
//

import Foundation
import MeshtasticProtobufs

enum EthernetMode: Int, CaseIterable, Identifiable {

	case dhcp = 0
	case staticip = 1

	var id: Int { self.rawValue }
	var description: String {

		switch self {
		case .dhcp:
			return "DHCP"
		case .staticip:
			return "Static IP"
		}
	}
	func protoEnumValue() -> Config.NetworkConfig.AddressMode {

		switch self {

		case .dhcp:
			return Config.NetworkConfig.AddressMode.dhcp
		case .staticip:
			return Config.NetworkConfig.AddressMode.static
		}
	}
}
