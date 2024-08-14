import Foundation

enum AnalyticEvents: String {
	// MARK: - App
	case appLaunch

	// MARK: - Screen
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

	// MARK: - Supporting Stuff
	var id: String {
		self.rawValue
	}

	static func getAnalParams(
		for node: NodeInfoEntity,
		_ additionalParams: [String: Any]? = nil
	) -> [String: Any] {
		var params = [String: Any]()

		params["id"] = node.num

		if let shortName = node.user?.shortName {
			params["shortName"] = shortName
		}
		else {
			params["shortName"] = "N/A"
		}

		if let longName = node.user?.longName {
			params["longName"] = longName
		}
		else {
			params["longName"] = "N/A"
		}

		if let additionalParams {
			for (key, value) in additionalParams {
				params[key] = value
			}
		}

		return params
	}
}
