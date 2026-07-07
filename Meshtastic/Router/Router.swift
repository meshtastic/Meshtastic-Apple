import Combine
import SwiftData
import OSLog
import SwiftUI

@MainActor
class Router: ObservableObject {

	@Published
	var selectedTab: NavigationState.Tab

	/// Transient deep-link *command* for the Messages tab (carries the channelId/userNum payload).
	/// Set by `route(url:)` / restoration and consumed exactly once by the Messages view, which
	/// resolves it into a selected conversation and then clears it. Kept separate from
	/// `messagesSection` so the one-shot payload never reaches the sidebar selection and so a later
	/// tab re-appear can't re-resolve it and snap the user back into the notified conversation.
	@Published
	var messagesState: MessagesNavigationState?

	/// Durable, payload-free Messages sidebar/section selection (`.channels()` / `.directMessages()`
	/// / nil). Drives the sidebar `List` selection and the content column. Because it only ever
	/// holds payload-free values it always matches a sidebar row, keeping the collapsed
	/// `NavigationSplitView` back stack intact. Survives across tab switches; reset by `popToRoot`.
	@Published
	var messagesSection: MessagesNavigationState?

	@Published
	var mapState: MapNavigationState?

	@Published
	var settingsPath: [SettingsNavigationState] = []

	@Published
	var discoveryShowHistory: Bool = false

	/// Computed property that assembles the individual per-tab properties into a `NavigationState`.
	/// Provided for backward compatibility (e.g. tests) and convenience.
	var navigationState: NavigationState {
		get {
			return NavigationState(
				selectedTab: selectedTab,
				messages: messagesState,
				nodeListSelectedNodeNum: selectedNodeNum,
				map: mapState,
				settings: settingsPath.last
			)
		}
		set {
			selectedTab = newValue.selectedTab
			messagesState = newValue.messages
			messagesSection = newValue.messages?.sidebarSection
			selectedNodeNum = newValue.nodeListSelectedNodeNum
			mapState = newValue.map
			if let setting = newValue.settings {
				settingsPath = [setting]
			} else {
				settingsPath = []
			}
		}
	}

	/// The currently selected node in the NavigationSplitView detail pane.
	@Published var selectedNodeNum: Int64?

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
		self.messagesSection = navigationState.messages?.sidebarSection
		if let num = navigationState.nodeListSelectedNodeNum {
			self.selectedNodeNum = num
		}
		self.mapState = navigationState.map
		if let setting = navigationState.settings {
			self.settingsPath = [setting]
		}

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
		} else if components.path == "/importGeoJSON" {
			routeImportGeoJSON(components)
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
		messagesSection = state?.sidebarSection
	}

	private func routeNodes(_ components: URLComponents) {
		let nodeId = components.queryItems?
			.first(where: { $0.name == "nodenum" })?
			.value
			.flatMap(Int64.init)

		selectedTab = .nodes
		if let nodeId {
			selectedNodeNum = nodeId
		} else {
			selectedNodeNum = nil
		}
	}

	func navigateToNodeDetail(nodeNum: Int64) {
		Logger.services.info("🛣 [App] Direct route to node detail \(nodeNum, privacy: .public)")
		selectedTab = .nodes
		selectedNodeNum = nodeNum
	}

	func popToRoot(tab: NavigationState.Tab) {
		switch tab {
		case .messages:
			messagesState = nil
			messagesSection = nil
		case .nodes:
			selectedNodeNum = nil
		case .map:
			mapState = nil
		case .settings:
			settingsPath = []
		default:
			break
		}
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
		let traceRouteId = components.queryItems?
			.first(where: { $0.name == "tracerouteId" })?
			.value
			.flatMap(Int64.init)

		selectedTab = .map
		mapState = if let nodeId {
			.selectedNode(nodeId)
		} else if let waypointId {
			.waypoint(waypointId)
		} else if let traceRouteId {
			.traceRoute(traceRouteId)
		} else {
			nil
		}
	}

	/// Downloads (http/https) or reads (file) a GeoJSON map overlay from the `url` query param and
	/// imports it via `MapDataManager`, reusing the same pipeline as the in-app file picker. Lets a
	/// coverage map be imported hands-free, e.g. `xcrun simctl openurl <udid> "meshtastic:///importGeoJSON?url=<encoded-url>"`.
	private func routeImportGeoJSON(_ components: URLComponents) {
		guard let urlString = components.queryItems?.first(where: { $0.name == "url" })?.value else {
			Logger.services.warning("🛣 [App] importGeoJSON route missing required 'url' query param.")
			return
		}

		selectedTab = .map

		Task {
			do {
				let metadata = try await MapDataManager.shared.importFromRemote(urlString: urlString)
				Logger.services.info("🗺️ [App] Imported '\(metadata.originalName, privacy: .public)' (\(metadata.overlayCount, privacy: .public) overlays) via importGeoJSON deep link.")
			} catch {
				Logger.services.error("🗺️ [App] importGeoJSON deep link failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// Imports a GeoJSON map overlay handed to the app as a file URL — e.g. via "Open in Meshtastic"
	/// from the Share Sheet, the Files app, or a drag-and-drop — reusing the same pipeline as the
	/// in-app file picker and the `importGeoJSON` deep link. Called from `onOpenURL` for file URLs,
	/// which is a distinct path from `route(url:)` (that only handles `meshtastic://` scheme URLs).
	func importMapFile(url: URL) {
		selectedTab = .map

		Task {
			do {
				let metadata = try await MapDataManager.shared.processUploadedFile(from: url)
				Logger.services.info("🗺️ [App] Imported '\(metadata.originalName, privacy: .public)' (\(metadata.overlayCount, privacy: .public) overlays) via Open In.")
			} catch {
				Logger.services.error("🗺️ [App] Open In GeoJSON import failed: \(error.localizedDescription, privacy: .public)")
			}
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
		if let settingFromPath {
			settingsPath = [settingFromPath]
		} else {
			settingsPath = []
		}

		if settingFromPath == .localMeshDiscovery && segments.count > 1 && segments[1] == "history" {
			discoveryShowHistory = true
		}
	}
}
