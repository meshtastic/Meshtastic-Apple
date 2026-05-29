//
//  NWHost.swift
//  Meshtastic
//
//  Created by jake on 12/20/25.
//

import Foundation
import Network

extension NWEndpoint.Host {
	/// Returns the underlying string value (domain name or IP address)
	/// without extra debug formatting.
	var stringValue: String {
		switch self {
		case .name(let name, _):
			return name
		case .ipv4(let ip):
			return String(describing: ip)
		case .ipv6(let ip):
			return String(describing: ip)
		@unknown default:
			return String(describing: self)
		}
	}
}
