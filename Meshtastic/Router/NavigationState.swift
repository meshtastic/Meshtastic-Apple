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

	/// Screen name reported to RUM, written out rather than derived from the raw value so a
	/// rename of the case cannot move a screen to a different bucket. See `ScreenName`.
	var screenName: ScreenName {
		switch self {
		case .about: return .about
		case .appSettings: return .appSettings
		case .routes: return .routes
		case .routeRecorder: return .routeRecorder
		case .lora: return .lora
		case .channels: return .channels
		case .shareQRCode: return .shareQRCode
		case .user: return .user
		case .bluetooth: return .bluetooth
		case .device: return .device
		case .display: return .display
		case .network: return .network
		case .position: return .position
		case .power: return .power
		case .ambientLighting: return .ambientLighting
		case .audio: return .audio
		case .cannedMessages: return .cannedMessages
		case .detectionSensor: return .detectionSensor
		case .meshBeacon: return .meshBeacon
		case .externalNotification: return .externalNotification
		case .mqtt: return .mqtt
		case .neighborInfo: return .neighborInfo
		case .rangeTest: return .rangeTest
		case .paxCounter: return .paxCounter
		case .ringtone: return .ringtone
		case .serial: return .serial
		case .security: return .security
		case .storeAndForward: return .storeAndForward
		case .telemetry: return .telemetry
		case .trafficManagement: return .trafficManagement
		case .debugLogs: return .debugLogs
		case .traceRoutes: return .traceRoutes
		case .appFiles: return .appFiles
		case .firmwareUpdates: return .firmwareUpdates
		case .deviceLinks: return .deviceLinks
		case .tak: return .tak
		case .takConfig: return .takConfig
		case .tools: return .tools
		case .coreDataBrowser: return .coreDataBrowser
		case .localMeshDiscovery: return .localMeshDiscovery
		case .helpDocs: return .helpDocs
		case .backupManagement: return .backupManagement
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
		var screenName: ScreenName {
			switch self {
			case .messages: return .messages
			case .nodes: return .nodes
			case .map: return .map
			case .settings: return .settings
			case .connect: return .connect
			}
		}
	}

	var selectedTab: Tab = .connect
	var messages: MessagesNavigationState?
	var nodeListSelectedNodeNum: Int64?
	var map: MapNavigationState?
	var settings: SettingsNavigationState?
}
