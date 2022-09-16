//
//  WiFiModes.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation

enum WiFiModes: Int, CaseIterable, Identifiable {

	case client = 0
	case accessPoint = 1
	case accessPointHidden = 2

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .client:
				return "Client"
			case .accessPoint:
				return "Software Access Point"
			case .accessPointHidden:
				return "Software Access Point (Hidden)"
			
			}
		}
	}
	func protoEnumValue() -> Config.NetworkConfig.WiFiMode {
		
		switch self {
			
		case .client:
			return Config.NetworkConfig.WiFiMode.client
		case .accessPoint:
			return Config.NetworkConfig.WiFiMode.accessPoint
		case .accessPointHidden:
			return Config.NetworkConfig.WiFiMode.accessPointHidden
		}
	}
}
