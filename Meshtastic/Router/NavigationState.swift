import Foundation

// MARK: Messages

enum MessagesNavigationState: Hashable {
	case channels(
		channelId: Int32? = nil,
		messageId: Int64? = nil
	)
	case directMessages(
		userNum: Int64? = nil,
		messageId: Int64? = nil
	)
}

// MARK: Map

enum MapNavigationState: Hashable {
	case selectedNode(Int64)
	case waypoint(Int64)
}

// MARK: Settings

enum SettingsNavigationState: String {
	case about
	case appSettings
	case routes
	case routeRecorder
	case lora
	case channels
	case shareQRCode
	case user
	case bluetooth
	case device
	case display
	case network
	case position
	case power
	case ambientLighting
	case cannedMessages
	case detectionSensor
	case externalNotification
	case mqtt
	case rangeTest
	case paxCounter
	case ringtone
	case serial
	case security
	case storeAndForward
	case telemetry
	case meshLog
	case debugLogs
	case appFiles
	case firmwareUpdates
}

enum NavigationState: Hashable {
	case messages(MessagesNavigationState? = nil)
	case bluetooth
	case nodes(selectedNodeNum: Int64? = nil)
	case map(MapNavigationState? = nil)
	case settings(SettingsNavigationState? = nil)
}

// MARK: Tab Bar

extension NavigationState {
	enum Tab: String, Hashable {
		case messages
		case bluetooth
		case nodes
		case map
		case settings
	}

	var tab: Tab {
		get {
			switch self {
			case .messages:
				.messages
			case .bluetooth:
				.bluetooth
			case .nodes:
				.nodes
			case .map:
				.map
			case .settings:
				.settings
			}
		}
		set {
			self = switch newValue {
			case .messages:
				.messages()
			case .bluetooth:
				.bluetooth
			case .nodes:
				.nodes()
			case .map:
				.map()
			case .settings:
				.settings()
			}
		}
	}
}
