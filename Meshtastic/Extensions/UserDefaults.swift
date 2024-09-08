//
//  UserDefaults.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/24/23.
//

import Foundation

@propertyWrapper
struct UserDefault<T: Decodable> {
	let key: UserDefaults.Keys
	let defaultValue: T

	init(_ key: UserDefaults.Keys, defaultValue: T) {
		self.key = key
		self.defaultValue = defaultValue
	}

	var wrappedValue: T {
		get {
			if defaultValue as? any RawRepresentable != nil {
				let storedValue = UserDefaults.standard.object(forKey: key.rawValue)

				guard let storedValue,
				let jsonString = (storedValue as? String != nil) ? "\"\(storedValue)\"" : "\(storedValue)",
				let data = jsonString.data(using: .utf8),
				let value = (try? JSONDecoder().decode(T.self, from: data)) else { return defaultValue }

				return value
			}

			return UserDefaults.standard.object(forKey: key.rawValue) as? T ?? defaultValue
		}
		set {
			UserDefaults.standard.set((newValue as? any RawRepresentable)?.rawValue ?? newValue, forKey: key.rawValue)
		}
	}
}

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
		case meshMapShowLocationPrecision
		case enableMapConvexHull
		case enableMapRecentering
		case enableMapNodeHistoryPins
		case enableMapRouteLines
		case enableMapTraffic
		case enableMapPointsOfInterest
		case enableOfflineMaps
		case mapTileServer
		case enableOverlayServer
		case mapOverlayServer
		case mapTilesAboveLabels
		case mapUseLegacy
		case enableDetectionNotifications
		case detectionSensorRole
		case enableSmartPosition
		case newNodeNotifications
		case lowBatteryNotifications
		case channelMessageNotifications
		case modemPreset
		case firmwareVersion
		case environmentEnableWeatherKit
		case enableAdministration
		case testIntEnum
	}

	func reset() {
		Keys.allCases.forEach { removeObject(forKey: $0.rawValue) }
	}

	@UserDefault(.preferredPeripheralId, defaultValue: "")
	static var preferredPeripheralId: String

	@UserDefault(.preferredPeripheralNum, defaultValue: 0)
	static var preferredPeripheralNum: Int

	@UserDefault(.provideLocation, defaultValue: false)
	static var provideLocation: Bool

	@UserDefault(.provideLocationInterval, defaultValue: 30)
	static var provideLocationInterval: Int

	@UserDefault(.mapLayer, defaultValue: .standard)
	static var mapLayer: MapLayer

	@UserDefault(.meshMapDistance, defaultValue: 800000)
	static var meshMapDistance: Double
	
	@UserDefault(.meshMapShowLocationPrecision, defaultValue: true)
	static var meshMapShowLocationPrecision: Bool

	@UserDefault(.enableMapWaypoints, defaultValue: false)
	static var enableMapWaypoints: Bool

	@UserDefault(.enableMapRecentering, defaultValue: false)
	static var enableMapRecentering: Bool

	@UserDefault(.enableMapNodeHistoryPins, defaultValue: false)
	static var enableMapNodeHistoryPins: Bool

	@UserDefault(.enableMapRouteLines, defaultValue: false)
	static var enableMapRouteLines: Bool

	@UserDefault(.enableMapConvexHull, defaultValue: false)
	static var enableMapConvexHull: Bool

	@UserDefault(.enableMapTraffic, defaultValue: false)
	static var enableMapTraffic: Bool

	@UserDefault(.enableMapPointsOfInterest, defaultValue: false)
	static var enableMapPointsOfInterest: Bool

	@UserDefault(.enableOfflineMaps, defaultValue: false)
	static var enableOfflineMaps: Bool

	@UserDefault(.mapTileServer, defaultValue: .openStreetMap)
	static var mapTileServer: MapTileServer

	@UserDefault(.enableOverlayServer, defaultValue: false)
	static var enableOverlayServer: Bool

	@UserDefault(.mapOverlayServer, defaultValue: .baseReReflectivityCurrent)
	static var mapOverlayServer: MapOverlayServer

	@UserDefault(.mapTilesAboveLabels, defaultValue: false)
	static var mapTilesAboveLabels: Bool

	@UserDefault(.mapUseLegacy, defaultValue: false)
	static var mapUseLegacy: Bool

	@UserDefault(.enableDetectionNotifications, defaultValue: false)
	static var enableDetectionNotifications: Bool

	@UserDefault(.detectionSensorRole, defaultValue: .sensor)
	static var detectionSensorRole: DetectionSensorRole

	@UserDefault(.enableSmartPosition, defaultValue: false)
	static var enableSmartPosition: Bool

	@UserDefault(.channelMessageNotifications, defaultValue: true)
	static var channelMessageNotifications: Bool

	@UserDefault(.newNodeNotifications, defaultValue: true)
	static var newNodeNotifications: Bool

	@UserDefault(.lowBatteryNotifications, defaultValue: true)
	static var lowBatteryNotifications: Bool

	@UserDefault(.modemPreset, defaultValue: 0)
	static var modemPreset: Int

	@UserDefault(.firmwareVersion, defaultValue: "0.0.0")
	static var firmwareVersion: String

	@UserDefault(.environmentEnableWeatherKit, defaultValue: true)
	static var environmentEnableWeatherKit: Bool

	@UserDefault(.enableAdministration, defaultValue: false)
	static var enableAdministration: Bool

	@UserDefault(.testIntEnum, defaultValue: .one)
	static var testIntEnum: TestIntEnum
}

enum TestIntEnum: Int, Decodable {
	case one = 1
	case two
	case three
}
