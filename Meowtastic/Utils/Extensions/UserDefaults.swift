import Foundation

@propertyWrapper
struct UserDefault<T: Decodable> {
	let key: UserDefaults.Keys
	let defaultValue: T

	var wrappedValue: T {
		get {
			if defaultValue as? any RawRepresentable != nil {
				guard let storedValue = UserDefaults.standard.object(forKey: key.rawValue),
					  let jsonString = storedValue as? String != nil ? "\"\(storedValue)\"" : "\(storedValue)",
					  let data = jsonString.data(using: .utf8),
					  let value = try? JSONDecoder().decode(T.self, from: data)
				else {
					return defaultValue
				}

				return value
			}

			return UserDefaults.standard.object(forKey: key.rawValue) as? T ?? defaultValue
		}

		set {
			UserDefaults.standard.set(
				(newValue as? any RawRepresentable)?.rawValue ?? newValue,
				forKey: key.rawValue
			)
		}
	}

	init(_ key: UserDefaults.Keys, defaultValue: T) {
		self.key = key
		self.defaultValue = defaultValue
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
		case meshMapShowNodeHistory
		case enableMapNodeHistoryPins
		case enableDetectionNotifications
		case newNodeNotifications
		case lowBatteryNotifications
		case channelMessageNotifications
		case modemPreset
		case firmwareVersion
		case ignoreMQTT
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

	@UserDefault(.enableMapNodeHistoryPins, defaultValue: false)
	static var enableMapNodeHistoryPins: Bool

	@UserDefault(.enableDetectionNotifications, defaultValue: false)
	static var enableDetectionNotifications: Bool

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

	@UserDefault(.ignoreMQTT, defaultValue: false)
	static var ignoreMQTT: Bool

	func reset() {
		Keys.allCases.forEach { key in
			removeObject(forKey: key.rawValue)
		}
	}
}
