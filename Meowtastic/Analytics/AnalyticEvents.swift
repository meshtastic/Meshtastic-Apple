import FirebaseAnalytics
import Foundation

enum AnalyticEvents: String {
	// MARK: - app
	case appLaunch

	// MARK: - screens
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

	// MARK: - events
	case ble
	case bleTimeout
	case bleCancelConnecting
	case bleConnect
	case bleDisconnect
	case bleTraceRoute
	case peripheral
	case mqttConnect
	case mqttDisconnect
	case mqttMessage
	case mqttError
	case nodeListCount

	// MARK: - specific events
	enum PeripheralEvents: String {
		case didDiscoverServices
		case didDiscoverCharacteristics
		case didUpdate

		enum Characteristics: String {
			case fromRadio
			case logRadio
			case logRadioLegacy
			case unhandled
		}

		enum App: String {
			case admin
			case message
			case nodeInfo
			case paxCounter
			case position
			case rangeTest
			case reply
			case routing
			case storeAndForward
			case telemetry
			case traceRoute
			case waypoint
			case unhandled
			case unknown
		}
	}

	enum BLERequest: String {
		case bluetoothConfig
		case bluetoothConfigSave
		case cannedMessages
		case channel
		case channelSave
		case deviceConfig
		case deviceConfigSave
		case deviceMetadata
		case displayConfig
		case displayConfigSave
		case factoryReset
		case favoriteNodeSet
		case favoriteNodeRemove
		case fixedPositionRemove
		case fixedPositionSet
		case licensedUserSave
		case loraConfig
		case loraConfigSave
		case message
		case mqttConfig
		case mqttConfigSave
		case nodeRemove
		case networkConfig
		case networkConfigSave
		case position
		case positionConfig
		case positionConfigSave
		case powerConfig
		case powerConfigSave
		case reboot
		case rebootOTA
		case resetDB
		case shutdown
		case userSave
		case wantConfig
		case wantConfigComplete
	}

	// MARK: - operation status
	enum OperationStatus {
		case success
		case error(String)
		case failureProcess
		case failureSend

		var description: String {
			switch self {
			case .success:
				return "success"

			case let .error(error):
				return "error_" + error

			case .failureProcess:
				return "failure_process"

			case .failureSend:
				return "failure_send"
			}
		}
	}

	// MARK: - supporting stuff
	var id: String {
		self.rawValue
	}

	static func trackBLEEvent(
		for operation: BLERequest,
		status: OperationStatus
	) {
		Analytics.logEvent(
			AnalyticEvents.ble.id,
			parameters: [
				operation.rawValue: status.description
			]
		)
	}

	static func trackPeripheralEvent(
		for operation: PeripheralEvents,
		status: OperationStatus,
		characteristic: PeripheralEvents.Characteristics? = nil,
		app: PeripheralEvents.App? = nil
	) {
		var params = [
			operation.rawValue: status.description
		]

		if let characteristic {
			params["characteristic"] = characteristic.rawValue
		}

		if let app {
			params["app"] = app.rawValue
		}

		Analytics.logEvent(AnalyticEvents.peripheral.id, parameters: params)
	}

	static func getParams(
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
