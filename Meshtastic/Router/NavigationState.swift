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
	case statusMessage
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
}

struct NavigationState: Hashable {
	enum Tab: String, Hashable {
		case messages
		case nodes
		case map
		case settings
		case connect
	}

	var selectedTab: Tab = .connect
	var messages: MessagesNavigationState?
	var nodeListSelectedNodeNum: Int64?
	var map: MapNavigationState?
	var settings: SettingsNavigationState?
}
