//
//  Character.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation

extension Character {
	var isEmoji: Bool {
		guard let scalar = unicodeScalars.first else { return false }
		return scalar.properties.isEmoji && (scalar.value >= 0x203C || unicodeScalars.count > 1)
	}
}
