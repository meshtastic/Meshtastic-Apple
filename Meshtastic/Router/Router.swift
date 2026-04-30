import Combine
import SwiftData
import OSLog
import SwiftUI

@MainActor
class Router: ObservableObject {

	@Published
	var selectedTab: NavigationState.Tab

	@Published
	var messagesState: MessagesNavigationState?

	@Published
	var nodeListSelectedNodeNum: Int64?

	@Published
	var mapState: MapNavigationState?

	@Published
	var settingsState: SettingsNavigationState?

	@Published
	var discoveryShowHistory: Bool = false

	/// Computed property that assembles the individual per-tab properties into a `NavigationState`.
	/// Provided for backward compatibility (e.g. tests) and convenience.
	var navigationState: NavigationState {
		get {
			NavigationState(
				selectedTab: selectedTab,
				messages: messagesState,
				nodeListSelectedNodeNum: nodeListSelectedNodeNum,
				map: mapState,
				settings: settingsState
			)
		}
		set {
			selectedTab = newValue.selectedTab
			messagesState = newValue.messages
			nodeListSelectedNodeNum = newValue.nodeListSelectedNodeNum
			mapState = newValue.map
			settingsState = newValue.settings
		}
	}

	// MARK: Node Object ID Cache

	/// In-memory cache mapping node numbers to their SwiftData `PersistentIdentifier` for O(1) lookups.
	/// Thread-safe by virtue of Router's @MainActor isolation — all access is on the main thread.
	private var nodeObjectIDCache: [Int64: PersistentIdentifier] = [:]

	/// Updates the node cache from a set of fetched nodes. Call this when the node list changes.
	func updateNodeIndex<C: Collection>(from nodes: C) where C.Element: NodeInfoEntity {
		nodeObjectIDCache = Dictionary(
			nodes.map { ($0.num, $0.persistentModelID) },
			uniquingKeysWith: { _, new in new }
		)
	}

	/// Looks up a node using the in-memory cache for O(1) performance, falling back to a SwiftData fetch.
	func cachedNodeInfo(id: Int64, context: ModelContext) -> NodeInfoEntity? {
		if let persistentID = nodeObjectIDCache[id] {
			if let node = context.model(for: persistentID) as? NodeInfoEntity {
				return node
			}
			// Stale entry (object deleted or faulted) — evict and fall back to a fresh fetch
			nodeObjectIDCache.removeValue(forKey: id)
		}
		// Cache miss — fall back to standard fetch
		let node = getNodeInfo(id: id, context: context)
		if let node {
			nodeObjectIDCache[id] = node.persistentModelID
		}
		return node
	}

	private var cancellables: Set<AnyCancellable> = []

	init(
		navigationState: NavigationState = NavigationState(
			selectedTab: .connect
		)
	) {
		self.selectedTab = navigationState.selectedTab
		self.messagesState = navigationState.messages
		self.nodeListSelectedNodeNum = navigationState.nodeListSelectedNodeNum
		self.mapState = navigationState.map
		self.settingsState = navigationState.settings

		$selectedTab.sink { tab in
			Logger.services.info("🛣 [App] Routed to \(tab.rawValue, privacy: .public)")
		}.store(in: &cancellables)
	}

	func route(url: URL) {
		guard url.scheme == "meshtastic" else {
			Logger.services.error("🛣 [App] Received routing URL \(url, privacy: .public) with invalid scheme. Ignoring route.")
			return
		}
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			Logger.services.error("🛣 [App] Received routing URL \(url, privacy: .public) with invalid host path. Ignoring route.")
			return
		}

		if components.path == "/messages" {
			routeMessages(components)
		} else if components.path == "/connect" {
			selectedTab = .connect
		} else if components.path == "/nodes" {
			routeNodes(components)
		} else if components.path == "/map" {
			routeMap(components)
		} else if components.path.hasPrefix("/settings") {
			routeSettings(components)
		} else {
			Logger.services.warning("🛣 [App] Failed to route url: \(url, privacy: .public)")
		}
	}

	// MARK: Routing Helpers

	private func routeMessages(
		_ components: URLComponents
	) {
		let channelId = components.queryItems?
			.first(where: { $0.name == "channelId" })?
			.value
			.flatMap(Int32.init)
		let userNum = components.queryItems?
			.first(where: { $0.name == "userNum" })?
			.value
			.flatMap(Int64.init)
		let messageId = components.queryItems?
			.first(where: { $0.name == "messageId" })?
			.value
			.flatMap(Int64.init)

		let state: MessagesNavigationState? = if let channelId {
			.channels(channelId: channelId, messageId: messageId)
		} else if let userNum {
			.directMessages(userNum: userNum, messageId: messageId)
		} else {
			nil
		}
		selectedTab = .messages
		messagesState = state
	}

	private func routeNodes(_ components: URLComponents) {
		let nodeId = components.queryItems?
			.first(where: { $0.name == "nodenum" })?
			.value
			.flatMap(Int64.init)

		selectedTab = .nodes
		nodeListSelectedNodeNum = nodeId
	}
	func navigateToNodeDetail(nodeNum: Int64) {
		Logger.services.info("🛣 [App] Direct route to node detail \(nodeNum, privacy: .public)")
		selectedTab = .nodes
		nodeListSelectedNodeNum = nodeNum
	}

	private func routeMap(_ components: URLComponents) {
		let nodeId = components.queryItems?
			.first(where: { $0.name == "nodenum" })?
			.value
			.flatMap(Int64.init)
		let waypointId = components.queryItems?
			.first(where: { $0.name == "waypointId" })?
			.value
			.flatMap(Int64.init)

		selectedTab = .map
		mapState = if let nodeId {
			.selectedNode(nodeId)
		} else if let waypointId {
			.waypoint(waypointId)
		} else {
			nil
		}
	}

	private func routeSettings(_ components: URLComponents) {
		let segments = components.path
			.split(separator: "/")
			.dropFirst()
			.map(String.init)

		let settingFromPath = segments.first
			.flatMap(SettingsNavigationState.init(rawValue:))

		selectedTab = .settings
		settingsState = settingFromPath

		if settingFromPath == .localMeshDiscovery && segments.count > 1 && segments[1] == "history" {
			discoveryShowHistory = true
		}
	}
}
