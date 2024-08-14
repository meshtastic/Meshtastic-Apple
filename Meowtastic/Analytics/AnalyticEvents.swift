import Foundation

enum AnalyticEvents: String {
	// App
	case appLaunch

	// Screen
	case connect
	case meshMap
	case messages
	case messageList
	case nodeDetail
	case nodeList
	case nodeMap
	case options
	case optionsAbout
	case optionsAppSettings
	case optionsChannels
	case optionsUser
	case optionsMQTT
	case optionsBluetooth
	case optionsDevice
	case optionsDisplay
	case optionsLoRa
	case optionsPosition
	case optionsNetwork
	case optionsPower
	case traceRoute

	var id: String {
		self.rawValue
	}

	static func getAnalParams(
		for node: NodeInfoEntity,
		_ additionalParams: [String: Any]? = nil
	) -> [String: Any] {
		var params = [String: Any]()

		if let name = node.user?.longName {
			params["name"] = name
		}
		else {
			params["name"] = "N/A"
		}
		params["id"] = node.num

		if let additionalParams {
			for (key, value) in additionalParams {
				params[key] = value
			}
		}

		return params
	}
}
