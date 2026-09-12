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

	/// The Messages sidebar section this state belongs to, with the deep-link payload
	/// (channelId/messageId, userNum) stripped.
	///
	/// The sidebar `List` only offers `.channels()` and `.directMessages()` rows, so its selection
	/// (`Router.messagesSection`) must stay payload-free — a payload-carrying value such as
	/// `.channels(channelId: 2, messageId: 5)` matches no row and corrupts the collapsed
	/// `NavigationSplitView` back stack (tap back → empty channel list). `Router` derives
	/// `messagesSection` from each deep-link `messagesState` via this property, keeping the correct
	/// row selected while the full payload stays on `messagesState` for the Messages view to
	/// consume once.
	var sidebarSection: MessagesNavigationState {
		switch self {
		case .channels: return .channels()
		case .directMessages: return .directMessages()
		}
	}
}

// MARK: Map

enum MapNavigationState: Hashable {
	case selectedNode(Int64)
	case waypoint(Int64)
	/// Show a specific trace route (by its request id) drawn on the map.
	case traceRoute(Int64)
	/// Open the Site Planner coverage-estimate flow prefilled from a node (by its node number).
	case coverageEstimate(Int64)
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
	case audio
	case cannedMessages
	case detectionSensor
	case meshBeacon
	case externalNotification
	case mqtt
	case neighborInfo
	case rangeTest
	case paxCounter
	case ringtone
	case serial
	case security
	case storeAndForward
	case telemetry
	case trafficManagement
	case debugLogs
	case traceRoutes
	case appFiles
	case firmwareUpdates
	case deviceLinks
	case tak
	case takConfig
	case tools
	case coreDataBrowser
	case localMeshDiscovery
	case helpDocs
	case backupManagement

	/// Screen name reported to RUM. Written out rather than derived from the raw value, for the
	/// same reason as `NavigationState.Tab.screenName`: these are the grouping key for a screen's
	/// crashes and hangs. Not localized — a name that changed with the device language would
	/// scatter one screen across as many buckets as there are languages.
	var screenName: String {
		switch self {
		case .about: return "About Meshtastic"
		case .appSettings: return "App Settings"
		case .routes: return "Routes"
		case .routeRecorder: return "Route Recorder"
		case .lora: return "LoRa Config"
		case .channels: return "Channel Config"
		case .shareQRCode: return "Share QR Code"
		case .user: return "User Config"
		case .bluetooth: return "Bluetooth Config"
		case .device: return "Device Config"
		case .display: return "Display Config"
		case .network: return "Network Config"
		case .position: return "Position Config"
		case .power: return "Power Config"
		case .ambientLighting: return "Ambient Lighting Config"
		case .audio: return "Audio Config"
		case .cannedMessages: return "Canned Messages Config"
		case .detectionSensor: return "Detection Sensor Config"
		case .meshBeacon: return "Mesh Beacon Config"
		case .externalNotification: return "External Notification Config"
		case .mqtt: return "MQTT Config"
		case .neighborInfo: return "Neighbor Info Config"
		case .rangeTest: return "Range Test Config"
		case .paxCounter: return "PAX Counter Config"
		case .ringtone: return "Ringtone Config"
		case .serial: return "Serial Config"
		case .security: return "Security Config"
		case .storeAndForward: return "Store and Forward Config"
		case .telemetry: return "Telemetry Config"
		case .trafficManagement: return "Traffic Management Config"
		case .debugLogs: return "Logs"
		case .traceRoutes: return "Trace Routes"
		case .appFiles: return "App Files"
		case .firmwareUpdates: return "Firmware Updates"
		case .deviceLinks: return "Device Links"
		case .tak: return "TAK Server"
		case .takConfig: return "TAK Module Config"
		case .tools: return "Tools"
		case .coreDataBrowser: return "Data Browser"
		case .localMeshDiscovery: return "Local Mesh Discovery"
		case .helpDocs: return "Help and Documentation"
		case .backupManagement: return "Backup Management"
		}
	}
}

struct NavigationState: Hashable {
	enum Tab: String, Hashable {
		case messages
		case nodes
		case map
		case settings
		case connect

		/// Screen name reported to RUM. Written out rather than derived from the raw value:
		/// these names are the grouping key for a screen's crashes and hangs, so they need to
		/// survive a rename of the case.
		var screenName: String {
			switch self {
			case .messages: return "Messages"
			case .nodes: return "Nodes"
			case .map: return "Map"
			case .settings: return "Settings"
			case .connect: return "Connect"
			}
		}
	}

	var selectedTab: Tab = .connect
	var messages: MessagesNavigationState?
	var nodeListSelectedNodeNum: Int64?
	var map: MapNavigationState?
	var settings: SettingsNavigationState?
}
