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
		case meshMapRecentering
		case meshMapShowNodeHistory
		case enableMapRecentering
		case enableMapNodeHistoryPins
		case enableOverlayServer
		case mapTilesAboveLabels
		case enableDetectionNotifications
		case enableSmartPosition
		case newNodeNotifications
		case lowBatteryNotifications
		case channelMessageNotifications
		case modemPreset
		case firmwareVersion
		case testIntEnum
		case filterFavorite
		case filterOnline
		case ignoreMQTT
	}

	func reset() {
		Keys.allCases.forEach { key in
			removeObject(forKey: key.rawValue)
		}
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

	@UserDefault(.enableMapRecentering, defaultValue: false)
	static var enableMapRecentering: Bool

	@UserDefault(.enableMapNodeHistoryPins, defaultValue: false)
	static var enableMapNodeHistoryPins: Bool

	@UserDefault(.mapTilesAboveLabels, defaultValue: false)
	static var mapTilesAboveLabels: Bool

	@UserDefault(.enableDetectionNotifications, defaultValue: false)
	static var enableDetectionNotifications: Bool

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

	@UserDefault(.testIntEnum, defaultValue: .one)
	static var testIntEnum: TestIntEnum

	@UserDefault(.filterFavorite, defaultValue: false)
	static var filterFavorite: Bool

	@UserDefault(.filterOnline, defaultValue: false)
	static var filterOnline: Bool

	@UserDefault(.ignoreMQTT, defaultValue: false)
	static var ignoreMQTT: Bool
}

enum TestIntEnum: Int, Decodable {
	case one = 1
	case two
	case three
}
