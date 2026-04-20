//
//  NodeListFilterParameters.swift
//  Meshtastic
//
//  Created by jake on 9/4/25.
//

import SwiftUI

@MainActor
final class NodeFilterParameters: ObservableObject {
	@AppStorage("nodeFilter.searchText") var searchText = ""
	@AppStorage("nodeFilter.isOnline") var isOnline = false
	@AppStorage("nodeFilter.isPkiEncrypted") var isPkiEncrypted = false
	@AppStorage("nodeFilter.isFavorite") var isFavorite = false
	@AppStorage("nodeFilter.isIgnored") var isIgnored = false
	@AppStorage("nodeFilter.isEnvironment") var isEnvironment = false
	@AppStorage("nodeFilter.distanceFilter") var distanceFilter = false
	@AppStorage("nodeFilter.maxDistance") var maxDistance: Double = 800_000
	@AppStorage("nodeFilter.hopsAway") var hopsAway: Double = -1.0
	@AppStorage("nodeFilter.roleFilter") var roleFilter = false
	
	// deviceRoles requires custom storage since Set<Int> isn't directly supported by @AppStorage
	@Published var deviceRoles: Set<Int> = [] {
		didSet {
			let array = Array(deviceRoles)
			UserDefaults.standard.set(array, forKey: "nodeFilter.deviceRoles")
		}
	}
	
	@AppStorage("nodeFilter.viaLora") private var _viaLora = true
	@AppStorage("nodeFilter.viaMqtt") private var _viaMqtt = true
	
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
	
	// Initialize and load the deviceRoles from UserDefaults
	init() {
		if let storedRoles = UserDefaults.standard.array(forKey: "nodeFilter.deviceRoles") as? [Int] {
			self.deviceRoles = Set(storedRoles)
		}
	}
}
