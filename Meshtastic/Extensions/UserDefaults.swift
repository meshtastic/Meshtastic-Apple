//
//  UserDefaults.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/24/23.
//

import Foundation

extension UserDefaults {
	enum Keys: String, CaseIterable {
		case enableRangeTest
		case meshtasticUsername
		case preferredPeripheralId
		case provideLocation
		case provideLocationInterval
		case mapLayer
		case meshMapRecentering
		case meshMapShowNodeHistory
		case meshMapShowRouteLines
		case enableOfflineMaps
		case mapTileServer
		case mapTilesAboveLabels
		case unreadMessages
	}

	func reset() {
		Keys.allCases.forEach { removeObject(forKey: $0.rawValue) }
	}
	static var blockRangeTest: Bool {
		get {
			UserDefaults.standard.bool(forKey: "blockRangeTest") 
		} set {
			UserDefaults.standard.set(newValue, forKey: "blockRangeTest")
		}
	}
	static var meshtasticUsername: String {
		get {
			UserDefaults.standard.string(forKey: "meshtasticUsername") ?? ""
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "meshtasticUsername")
		}
	}

	static var preferredPeripheralId: String {
		get {
			UserDefaults.standard.string(forKey: "preferredPeripheralId") ?? ""
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "preferredPeripheralId")
		}
	}
	static var provideLocation: Bool {
		get {
			UserDefaults.standard.bool(forKey: "provideLocation")
		} set {
			UserDefaults.standard.set(newValue, forKey: "provideLocation")
		}
	}
	static var provideLocationInterval: Int {
		get {
			UserDefaults.standard.integer(forKey: "provideLocationInterval")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "provideLocationInterval")
		}
	}
	static var mapLayer: MapLayer {
		get {
			MapLayer(rawValue: UserDefaults.standard.string(forKey: "mapLayer") ?? MapLayer.standard.rawValue) ?? MapLayer.standard
		}
		set {
			UserDefaults.standard.set(newValue.rawValue, forKey: "mapLayer")
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
	static var enableOfflineMapsMBTiles: Bool {
		get {
			UserDefaults.standard.bool(forKey: "enableOfflineMapsMBTiles")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "enableOfflineMapsMBTiles")
		}
	}
	static var mapTileServer: MapTileServer {
		get {
			MapTileServer(rawValue: UserDefaults.standard.string(forKey: "mapTileServer") ?? MapTileServer.openStreetMap.rawValue) ?? MapTileServer.openStreetMap
		}
		set {
			UserDefaults.standard.set(newValue.rawValue, forKey: "mapTileServer")
		}
	}
	static var enableOverlayServer: Bool {
		get {
			UserDefaults.standard.bool(forKey: "enableOverlayServer")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "enableOverlayServer")
		}
	}
	static var mapOverlayServer: MapOverlayServer {
		get {
			MapOverlayServer(rawValue: UserDefaults.standard.string(forKey: "mapOverlayServer") ?? MapOverlayServer.baseReReflectivityCurrent.rawValue) ?? MapOverlayServer.baseReReflectivityCurrent
		}
		set {
			UserDefaults.standard.set(newValue.rawValue, forKey: "mapOverlayServer")
		}
	}
	static var mapTilesAboveLabels: Bool {
		get {
			UserDefaults.standard.bool(forKey: "mapTilesAboveLabels")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "mapTilesAboveLabels")
		}
	}
	
	static var unreadMessages: Int {
		get {
			UserDefaults.standard.integer(forKey: "unreadMessages")
		} set {
			UserDefaults.standard.set(newValue, forKey: "unreadMessages")
		}
	}
}
