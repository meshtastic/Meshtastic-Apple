//
//  UserDefaults.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/24/23.
//
//
//  UserDefaults.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/24/23.
//

import Foundation

extension UserDefaults {
	enum Keys: String, CaseIterable {
		case preferredPeripheralId
		case preferredPeripheralNum
		case provideLocation
		case provideLocationInterval
		case mapLayer
		case meshMapDistance
		case enableMapWaypoints
		case meshMapRecentering
		case meshMapShowNodeHistory
		case meshMapShowRouteLines
		case enableMapConvexHull
		case enableMapTraffic
		case enableMapPointsOfInterest
		case enableOfflineMaps
		case mapTileServer
		case mapTilesAboveLabels
		case mapUseLegacy
		case enableDetectionNotifications
		case detectionSensorRole
		case enableSmartPosition
		case modemPreset
		case firmwareVersion
	}

	func reset() {
		Keys.allCases.forEach { removeObject(forKey: $0.rawValue) }
	}
	static var preferredPeripheralId: String {
		get {
			UserDefaults.standard.string(forKey: "preferredPeripheralId") ?? ""
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "preferredPeripheralId")
		}
	}
	static var preferredPeripheralNum: Int {
		get {
			UserDefaults.standard.integer(forKey: "preferredPeripheralNum")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "preferredPeripheralNum")
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
	static var meshMapDistance: Double {
		get {
			UserDefaults.standard.double(forKey: "meshMapDistance")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "meshMapDistance")
		}
	}
	static var enableMapWaypoints: Bool {
		get {
			UserDefaults.standard.bool(forKey: "enableMapWaypoints")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "enableMapWaypoints")
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
	static var enableMapConvexHull: Bool {
		get {
			UserDefaults.standard.bool(forKey: "enableMapConvexHull")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "enableMapConvexHull")
		}
	}
	static var enableMapTraffic: Bool {
		get {
			UserDefaults.standard.bool(forKey: "enableMapTraffic")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "enableMapTraffic")
		}
	}
	static var enableMapPointsOfInterest: Bool {
		get {
			UserDefaults.standard.bool(forKey: "enableMapPointsOfInterest")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "enableMapPointsOfInterest")
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
	
	static var mapUseLegacy: Bool {
		get {
			UserDefaults.standard.bool(forKey: "mapUseLegacy")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "mapUseLegacy")
		}
	}
	
	static var enableDetectionNotifications: Bool {
		get {
			UserDefaults.standard.bool(forKey: "enableDetectionNotifications")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "enableDetectionNotifications")
		}
	}
	
	static var detectionSensorRole: DetectionSensorRole {
		get {
			DetectionSensorRole(rawValue: UserDefaults.standard.string(forKey: "detectionSensorRole") ?? DetectionSensorRole.sensor.rawValue) ?? DetectionSensorRole.sensor
		}
		set {
			UserDefaults.standard.set(newValue.rawValue, forKey: "detectionSensorRole")
		}
	}
	static var enableSmartPosition: Bool {
		get {
			UserDefaults.standard.bool(forKey: "enableSmartPosition")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "enableSmartPosition")
		}
	}
	static var modemPreset: Int {
		get {
			UserDefaults.standard.integer(forKey: "modemPreset")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "modemPreset")
		}
	}
	static var firmwareVersion: String {
		get {
			UserDefaults.standard.string(forKey: "firmwareVersion") ?? "0.0.0"
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "firmwareVersion")
		}
	}
}

//import Foundation
//
//@propertyWrapper
//struct UserDefault<T> {
//	let key: UserDefaults.Keys
//	let defaultValue: T
//
//	init(_ key: UserDefaults.Keys, defaultValue: T) {
//		self.key = key
//		self.defaultValue = defaultValue
//	}
//
//	var wrappedValue: T {
//		get {
//			UserDefaults.standard.object(forKey: key.rawValue) as? T ?? defaultValue
//		}
//		set {
//			UserDefaults.standard.set(newValue, forKey: key.rawValue)
//		}
//	}
//}
//
//extension UserDefaults {
//	enum Keys: String, CaseIterable {
//		case preferredPeripheralId
//		case preferredPeripheralNum
//		case provideLocation
//		case provideLocationInterval
//		case mapLayer
//		case meshMapDistance
//		case enableMapWaypoints
//		case meshMapRecentering
//		case meshMapShowNodeHistory
//		case meshMapShowRouteLines
//		case enableMapConvexHull
//		case enableMapRecentering
//		case enableMapNodeHistoryPins
//		case enableMapRouteLines
//		case enableMapTraffic
//		case enableMapPointsOfInterest
//		case enableOfflineMaps
//		case enableOfflineMapsMBTiles
//		case mapTileServer
//		case enableOverlayServer
//		case mapOverlayServer
//		case mapTilesAboveLabels
//		case mapUseLegacy
//		case enableDetectionNotifications
//		case detectionSensorRole
//		case enableSmartPosition
//		case modemPreset
//		case firmwareVersion
//	}
//
//	func reset() {
//		Keys.allCases.forEach { removeObject(forKey: $0.rawValue) }
//	}
//
//	@UserDefault(.preferredPeripheralId, defaultValue: "")
//	static var preferredPeripheralId: String
//
//	@UserDefault(.preferredPeripheralNum, defaultValue: 0)
//	static var preferredPeripheralNum: Int
//
//	@UserDefault(.provideLocation, defaultValue: false)
//	static var provideLocation: Bool
//
//	@UserDefault(.provideLocationInterval, defaultValue: 0)
//	static var provideLocationInterval: Int
//
//	@UserDefault(.mapLayer, defaultValue: .standard)
//	static var mapLayer: MapLayer
//
//	@UserDefault(.meshMapDistance, defaultValue: 800000)
//	static var meshMapDistance: Double
//	
//	@UserDefault(.enableMapWaypoints, defaultValue: false)
//	static var enableMapWaypoints: Bool
//	
//	@UserDefault(.enableMapRecentering, defaultValue: false)
//	static var enableMapRecentering: Bool
//
//	@UserDefault(.enableMapNodeHistoryPins, defaultValue: false)
//	static var enableMapNodeHistoryPins: Bool
//
//	@UserDefault(.enableMapRouteLines, defaultValue: false)
//	static var enableMapRouteLines: Bool
//
//	@UserDefault(.enableMapConvexHull, defaultValue: false)
//	static var enableMapConvexHull: Bool
//
//	@UserDefault(.enableMapTraffic, defaultValue: false)
//	static var enableMapTraffic: Bool
//
//	@UserDefault(.enableMapPointsOfInterest, defaultValue: false)
//	static var enableMapPointsOfInterest: Bool
//
//	@UserDefault(.enableOfflineMaps, defaultValue: false)
//	static var enableOfflineMaps: Bool
//
//	@UserDefault(.enableOfflineMapsMBTiles, defaultValue: false)
//	static var enableOfflineMapsMBTiles: Bool
//
//	@UserDefault(.mapTileServer, defaultValue: .openStreetMap)
//	static var mapTileServer: MapTileServer
//
//	@UserDefault(.enableOverlayServer, defaultValue: false)
//	static var enableOverlayServer: Bool
//
//	@UserDefault(.mapOverlayServer, defaultValue: .baseReReflectivityCurrent)
//	static var mapOverlayServer: MapOverlayServer
//
//	@UserDefault(.mapTilesAboveLabels, defaultValue: false)
//	static var mapTilesAboveLabels: Bool
//
//	@UserDefault(.mapUseLegacy, defaultValue: false)
//	static var mapUseLegacy: Bool
//
//	@UserDefault(.enableDetectionNotifications, defaultValue: false)
//	static var enableDetectionNotifications: Bool
//
//	@UserDefault(.detectionSensorRole, defaultValue: .sensor)
//	static var detectionSensorRole: DetectionSensorRole
//
//	@UserDefault(.enableSmartPosition, defaultValue: false)
//	static var enableSmartPosition: Bool
//
//	@UserDefault(.modemPreset, defaultValue: 0)
//	static var modemPreset: Int
//
//	@UserDefault(.firmwareVersion, defaultValue: "0.0.0")
//	static var firmwareVersion: String
//}
