//
//  UserDefaults.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/24/23.
//

import Foundation

extension UserDefaults {
	
	enum Keys: String, CaseIterable {
		case meshtasticUsername
		case preferredPeripheralId
		case provideLocation
		case provideLocationInterval
		case keyboardType
		case meshMapType
		case meshMapCenteringMode
		case meshMapRecentering
		case meshMapCustomTileServer
		case meshMapShowNodeHistory
		case meshMapShowRouteLines
	}

	func reset() {
		Keys.allCases.forEach { removeObject(forKey: $0.rawValue) }
	}
	
	static var hasBeenLaunched: Bool {
		get {
			let result = UserDefaults.standard.bool(forKey: "hasBeenLaunched")
			UserDefaults.standard.set(true, forKey: "hasBeenLaunched")
			return result
		} set {
			UserDefaults.standard.set(newValue, forKey: "hasBeenLaunched")
		}
	}
	
	static var mapType: Int {
		get {
			UserDefaults.standard.integer(forKey: "meshMapType")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "meshMapType")
		}
	}
	
	static var enableMapRecentering: Bool {
		get {
			UserDefaults.standard.bool(forKey: "meshMapRecentering")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "meshMapRecentering")
		}
	}

	static var enableMapNodeHistoryPins: Bool {
		get {
			UserDefaults.standard.bool(forKey: "meshMapShowNodeHistory")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "meshMapShowNodeHistory")
		}
	}
	
	static var enableMapRouteLines: Bool {
		get {
			UserDefaults.standard.bool(forKey: "meshMapShowRouteLines")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "meshMapShowRouteLines")
		}
	}
	
	static var enableOfflineMaps: Bool {
		get {
			UserDefaults.standard.bool(forKey: "enableOfflineMaps")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "enableOfflineMaps")
		}
	}
	
	static var mapTileServer: String {
		get {
			UserDefaults.standard.string(forKey: "mapTileServer") ?? ""
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "mapTileServer")
		}
	}
}
