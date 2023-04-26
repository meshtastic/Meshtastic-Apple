//
//  Data.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation

extension Data {
	var macAddressString: String {
		let mac: String = reduce("") {$0 + String(format: "%02x:", $1)}
		return String(mac.dropLast())
	}
	var hexDescription: String {
		return reduce("") {$0 + String(format: "%02x", $1)}
	}
}
