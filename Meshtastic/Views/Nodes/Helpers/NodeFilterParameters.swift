//
//  NodeListFilterParameters.swift
//  Meshtastic
//
//  Created by jake on 9/4/25.
//

import SwiftUI

@MainActor
final class NodeFilterParameters: ObservableObject {
	// Public variables
	@Published var searchText = ""
	@Published var isOnline = false
	@Published var isPkiEncrypted = false
	@Published var isFavorite = false
	@Published var isIgnored = false
	@Published var isEnvironment = false
	@Published var distanceFilter = false
	@Published var maxDistance: Double = 800_000
	@Published var hopsAway: Double = -1.0
	@Published var roleFilter = false
	@Published var deviceRoles: Set<Int> = []
	
	// Private backing vars
	@Published private var _viaLora = true
	@Published private var _viaMqtt = true
	
	// Public computed wrappers with enforcement
	var viaLora: Bool {
		get { _viaLora }
		set {
			objectWillChange.send()
			_viaLora = newValue
			if !_viaLora && !_viaMqtt {
				_viaMqtt = true   // enforce at least one ON
			}
		}
	}
	
	var viaMqtt: Bool {
		get { _viaMqtt }
		set {
			objectWillChange.send()
			_viaMqtt = newValue
			if !_viaLora && !_viaMqtt {
				_viaLora = true   // enforce at least one ON
			}
		}
	}
}
