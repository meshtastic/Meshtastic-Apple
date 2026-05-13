//
//  NodeList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/8/23.
//
import SwiftUI
import CoreLocation
import OSLog
import SwiftData
import Foundation

struct NodeList: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var router: Router
	@AppStorage("nodeListDensity") private var nodeListDensity: NodeListDensity = .standard
	@State private var isPresentingTraceRouteSentAlert = false
	@State private var isPresentingPositionSentAlert = false
	@State private var isPresentingPositionFailedAlert = false
	@State private var isPresentingDeleteNodeAlert = false
	@State private var deleteNodeId: Int64 = 0
	@State private var shareContactNode: NodeInfoEntity?
	@StateObject var filters = NodeFilterParameters()
	@State var isEditingFilters = false
	@State private var showingHelp = false
	@SceneStorage("selectedDetailView") var selectedDetailView: String?


	var connectedNode: NodeInfoEntity? {
		if let num = accessoryManager.activeDeviceNum {
			return getNodeInfo(id: num, context: context)
		}
		return nil
	}

	@State private var columnVisibility: NavigationSplitViewVisibility = .all

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			sidebarContent
		} detail: {
			NavigationStack {
				if let selectedNum = router.selectedNodeNum,
				   let node = getNodeInfo(id: selectedNum, context: context) {
					NodeDetail(node: node)
				} else {
					ContentUnavailableView("Select a Node", systemImage: "flipphone")
				}
			}
		}
		.navigationSplitViewStyle(.balanced)
	}

	// MARK: - Sidebar

	@ViewBuilder
	private var sidebarContent: some View {
		FilteredNodeList(
			withFilters: filters,
			connectedNode: connectedNode,
			isPresentingDeleteNodeAlert: $isPresentingDeleteNodeAlert,
			deleteNodeId: $deleteNodeId,
			shareContactNode: $shareContactNode,
			nodeListDensity: $nodeListDensity,
			selectedNodeNum: $router.selectedNodeNum
		)
		.sheet(isPresented: $isEditingFilters) {
			NodeListFilter(
				filters: filters
			)
		}
		.sheet(isPresented: $showingHelp) {
			NodeListHelp()
		}
		.safeAreaInset(edge: .bottom, alignment: .leading) {
			HStack {
				Button(action: {
					withAnimation {
						showingHelp = !showingHelp
					}
				}) {
					Image(systemName: !showingHelp ? "questionmark.circle" : "questionmark.circle.fill")
						.padding(.vertical, 5)
				}
				.tint(Color(UIColor.secondarySystemBackground))
				.foregroundColor(.accentColor)
				.buttonStyle(.borderedProminent)
				Spacer()
				Button(action: {
					withAnimation {
						isEditingFilters = !isEditingFilters
					}
				}) {
					Image(systemName: !isEditingFilters ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
						.padding(.vertical, 5)
				}
				.tint(Color(UIColor.secondarySystemBackground))
				.foregroundColor(.accentColor)
				.buttonStyle(.borderedProminent)
			}
			.controlSize(.regular)
			.padding(5)
		}
		.searchable(text: $filters.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a node")
		.autocorrectionDisabled(true)
		.scrollDismissesKeyboard(.immediately)
		.navigationTitle(String.localizedStringWithFormat("Nodes (%@)".localized, String(getNodeCount())))
		.listStyle(.plain)
		.alert("Position Exchange Requested", isPresented: $isPresentingPositionSentAlert) {
			Button("OK") { }.keyboardShortcut(.defaultAction)
		} message: {
			Text("Your position has been sent with a request for a response with their position. You will receive a notification when a position is returned.")
		}
		.alert("Position Exchange Failed", isPresented: $isPresentingPositionFailedAlert) {
			Button("OK") { }.keyboardShortcut(.defaultAction)
		} message: {
			Text("Failed to get a valid position to exchange")
		}
		.alert("Trace Route Sent", isPresented: $isPresentingTraceRouteSentAlert) {
			Button("OK") { }.keyboardShortcut(.defaultAction)
		} message: {
			Text("This could take a while, response will appear in the trace route log for the node it was sent to.")
		}
		.confirmationDialog("Are you sure?", isPresented: $isPresentingDeleteNodeAlert, titleVisibility: .visible) {
			deleteNodeButton
		}
		.sheet(item: $shareContactNode) { selectedNode in
			ShareContactQRDialog(manuallyVerified: false, node: selectedNode.toProto())
		}
		.navigationSplitViewColumnWidth(min: 100, ideal: 300, max: .infinity)
		.navigationBarItems(leading: MeshtasticLogo(), trailing: ZStack {
			ConnectedDevice(
				deviceConnected: accessoryManager.isConnected,
				name: accessoryManager.activeConnection?.device.shortName ?? "?",
				phoneOnly: true
			)
		}
		.accessibilityElement(children: .contain))
	}

	// Helper to get the count of nodes for the navigation title
	private func getNodeCount() -> Int {
		var descriptor = FetchDescriptor<NodeInfoEntity>()
		descriptor.predicate = filters.buildSwiftDataPredicate()
		return (try? context.fetchCount(descriptor)) ?? 0
	}

	@ViewBuilder
	private var deleteNodeButton: some View {
		Button("Delete Node", role: .destructive) {
			let deleteNode = getNodeInfo(id: deleteNodeId, context: context)
			if connectedNode != nil {
				if let node = deleteNode {
					Task {
						do {
							try await accessoryManager.removeNode(node: node, connectedNodeNum: accessoryManager.activeDeviceNum ?? -1)
						} catch {
							let nodeName = node.user?.longName ?? "Unknown"
							Logger.data.error("Failed to delete node \(nodeName, privacy: .public)")
						}
					}
				}
			}
		}
	}
}

//
//  FilteredNodeList.swift
//  Meshtastic
//
private struct FilteredNodeList: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Query(sort: \NodeInfoEntity.lastHeard, order: .reverse)
	private var allNodes: [NodeInfoEntity]
	@Environment(\.modelContext) private var context

	var connectedNode: NodeInfoEntity?
	@Binding var isPresentingDeleteNodeAlert: Bool
	@Binding var deleteNodeId: Int64
	@Binding var shareContactNode: NodeInfoEntity?
	@Binding var nodeListDensity: NodeListDensity
	@Binding var selectedNodeNum: Int64?
	var filters: NodeFilterParameters

	init(
		withFilters: NodeFilterParameters,
		connectedNode: NodeInfoEntity?,
		isPresentingDeleteNodeAlert: Binding<Bool>,
		deleteNodeId: Binding<Int64>,
		shareContactNode: Binding<NodeInfoEntity?>,
		nodeListDensity: Binding<NodeListDensity>,
		selectedNodeNum: Binding<Int64?>
	) {
		self.filters = withFilters
		self.connectedNode = connectedNode
		self._isPresentingDeleteNodeAlert = isPresentingDeleteNodeAlert
		self._deleteNodeId = deleteNodeId
		self._shareContactNode = shareContactNode
		self._nodeListDensity = nodeListDensity
		self._selectedNodeNum = selectedNodeNum

		// Push simple filters into the SwiftData predicate to reduce in-memory work
		let showIgnored = withFilters.isIgnored
		let showFavorite = withFilters.isFavorite
		let filterViaLoraOnly = withFilters.viaLora && !withFilters.viaMqtt
		let filterViaMqttOnly = !withFilters.viaLora && withFilters.viaMqtt
		let filterHopsDirect = withFilters.hopsAway == 0.0
		let filterHopsMax = withFilters.hopsAway > 0.0
		let maxHops = Int32(withFilters.hopsAway)

		_allNodes = Query(
			filter: #Predicate<NodeInfoEntity> { node in
				// Ignored filter (always applied)
				(showIgnored || !node.ignored) &&
				(!showIgnored || node.ignored) &&
				// Favorite filter
				(!showFavorite || node.favorite) &&
				// Via LoRa only (exclude MQTT)
				(!filterViaLoraOnly || !node.viaMqtt) &&
				// Via MQTT only
				(!filterViaMqttOnly || node.viaMqtt) &&
				// Direct nodes only
				(!filterHopsDirect || node.hopsAway == 0) &&
				// Hops within range
				(!filterHopsMax || (node.hopsAway > 0 && node.hopsAway <= maxHops))
			},
			sort: \NodeInfoEntity.lastHeard,
			order: .reverse
		)
	}

	private var filteredNodes: [NodeInfoEntity] {
		allNodes
			.filter { filters.matchesPostPredicate($0) }
			.sorted {
				if $0.ignored != $1.ignored { return !$0.ignored && $1.ignored }
				if $0.favorite != $1.favorite { return $0.favorite && !$1.favorite }
				return ($0.lastHeard ?? .distantPast) > ($1.lastHeard ?? .distantPast)
			}
	}

	// The body of the view
	var body: some View {
		// If the connected node passes filters, always show it first
		let nodesWithConnectedFirst = filteredNodes.filter { $0.num == accessoryManager.activeDeviceNum } + filteredNodes.filter { $0.num != accessoryManager.activeDeviceNum }
		List(nodesWithConnectedFirst, id: \.self, selection: $selectedNodeNum) { node in
			NavigationLink(value: node.num) {
				switch nodeListDensity {
				case .compact:
					NodeListItemCompact(
						node: node,
						isDirectlyConnected: node.num == accessoryManager.activeDeviceNum,
						connectedNode: accessoryManager.activeConnection?.device.num ?? -1)
				case .standard:
					NodeListItem(
						node: node,
						isDirectlyConnected: node.num == accessoryManager.activeDeviceNum,
						connectedNode: accessoryManager.activeConnection?.device.num ?? -1
					)
				}
			}
			.contextMenu {
				contextMenuActions(
					node: node,
					connectedNode: connectedNode
				)
			}
		}
	}

	@ViewBuilder
	func contextMenuActions(
		node: NodeInfoEntity,
		connectedNode: NodeInfoEntity?
	) -> some View {
		if let user = node.user {
			NodeAlertsButton(context: context, node: node, user: user)
			if !user.unmessagable && user.num == UserDefaults.preferredPeripheralNum {
				Button(action: {
					shareContactNode = node
				}) {
					Label("Share Contact QR", systemImage: "qrcode")
				}
			}
		}
		if let connectedNode {
			FavoriteNodeButton(node: node)
			if connectedNode.num != node.num {
				if !(node.user?.unmessagable ?? true) {
					Button(action: {
						if let url = URL(string: "meshtastic:///messages?userNum=\(node.num)") {
							UIApplication.shared.open(url)
						}
					}) {
						Label("Message", systemImage: "message")
					}
				}
				Button {
					Task {
						do {
							try await accessoryManager.sendPosition(
								channel: node.channel,
								destNum: node.num,
								wantResponse: true
							)
							Task { @MainActor in
								// Update state to show alert
							}
						} catch {
							Logger.mesh.warning("Failed to sendPosition")
						}
					}
				} label: {
					Label("Exchange Positions", systemImage: "arrow.triangle.2.circlepath")
				}
				Button {
					Task {
						if let fromUser = connectedNode.user, let toUser = node.user {
							do {
								_ = try await accessoryManager.exchangeUserInfo(fromUser: fromUser, toUser: toUser)
							} catch {
								Logger.mesh.warning("Failed to exchange user info")
							}
						}
					}
				} label: {
					Label("Exchange User Info", systemImage: "person.2.badge.gearshape")
				}
				TraceRouteButton(
					node: node
				)
				IgnoreNodeButton(
					node: node
				)
				Button(role: .destructive) {
					deleteNodeId = node.num
					isPresentingDeleteNodeAlert = true
				} label: {
					Label("Delete Node", systemImage: "trash")
				}
			}
		}
	}
}

//
//  NodeFilterParameters+Predicate.swift
//  Meshtastic
//

fileprivate extension NodeFilterParameters {
	/// In-memory filter matching for use with @Query results
	func matches(_ node: NodeInfoEntity) -> Bool {
		// Search text
		if !searchText.isEmpty {
			let text = searchText.lowercased()
			let matchesSearch = [
				node.user?.userId,
				node.user?.numString,
				node.user?.hwModel,
				node.user?.hwDisplayName,
				node.user?.longName,
				node.user?.shortName
			].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(text) }
			if !matchesSearch { return false }
		}

		// Favorite filter
		if isFavorite && !node.favorite { return false }

		// Via Lora/MQTT filters
		if viaLora && !viaMqtt && node.viaMqtt { return false }
		if !viaLora && viaMqtt && !node.viaMqtt { return false }

		// Role filter
		if roleFilter && !deviceRoles.isEmpty {
			guard let role = node.user?.role else { return false }
			if !deviceRoles.contains(Int(role)) { return false }
		}

		// Hops Away filter
		if hopsAway == 0.0 {
			if node.hopsAway != 0 { return false }
		} else if hopsAway > 0.0 {
			if node.hopsAway <= 0 || node.hopsAway > Int32(hopsAway) { return false }
		}

		// Online filter
		if isOnline {
			guard let lastHeard = node.lastHeard,
				  let threshold = Calendar.current.date(byAdding: .minute, value: -120, to: Date()) else {
				return false
			}
			if lastHeard < threshold { return false }
		}

		// Encrypted filter
		if isPkiEncrypted {
			if node.user?.pkiEncrypted != true { return false }
		}

		// Ignored filter
		if isIgnored {
			if !node.ignored { return false }
		} else {
			if node.ignored { return false }
		}

		// Environment filter
		if isEnvironment {
			let hasEnvironmentTelemetry = node.telemetries.contains { $0.metricsType == 1 }
			if !hasEnvironmentTelemetry { return false }
		}

		// Distance filter
		if distanceFilter {
			if let pointOfInterest = LocationsHandler.currentLocation {
				if pointOfInterest.latitude != LocationsHandler.DefaultLocation.latitude &&
					pointOfInterest.longitude != LocationsHandler.DefaultLocation.longitude {
					let d: Double = maxDistance * 1.1
					let r: Double = 6371009
					let meanLatitude = pointOfInterest.latitude * .pi / 180
					let deltaLatitude = d / r * 180 / .pi
					let deltaLongitude = d / (r * cos(meanLatitude)) * 180 / .pi
					let minLatitude = pointOfInterest.latitude - deltaLatitude
					let maxLatitude = pointOfInterest.latitude + deltaLatitude
					let minLongitude = pointOfInterest.longitude - deltaLongitude
					let maxLongitude = pointOfInterest.longitude + deltaLongitude

					let hasPositionInRange = node.positions.contains { position in
						guard position.latest else { return false }
						let lon = Double(position.longitudeI) / 1e7
						let lat = Double(position.latitudeI) / 1e7
						return lon >= minLongitude && lon <= maxLongitude && lat >= minLatitude && lat <= maxLatitude
					}
					if !hasPositionInRange { return false }
				}
			}
		}

		return true
	}

	/// Post-predicate in-memory filter for filters that can't be expressed in SwiftData #Predicate.
	/// Filters already pushed into the @Query predicate: ignored, favorite, viaLora/viaMqtt, hopsAway.
	func matchesPostPredicate(_ node: NodeInfoEntity) -> Bool {
		// Search text (requires relationship traversal)
		if !searchText.isEmpty {
			let text = searchText.lowercased()
			let matchesSearch = [
				node.user?.userId,
				node.user?.numString,
				node.user?.hwModel,
				node.user?.hwDisplayName,
				node.user?.longName,
				node.user?.shortName
			].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(text) }
			if !matchesSearch { return false }
		}

		// Role filter (requires relationship traversal)
		if roleFilter && !deviceRoles.isEmpty {
			guard let role = node.user?.role else { return false }
			if !deviceRoles.contains(Int(role)) { return false }
		}

		// Online filter (requires date computation)
		if isOnline {
			guard let lastHeard = node.lastHeard,
				  let threshold = Calendar.current.date(byAdding: .minute, value: -120, to: Date()) else {
				return false
			}
			if lastHeard < threshold { return false }
		}

		// Encrypted filter (requires relationship traversal)
		if isPkiEncrypted {
			if node.user?.pkiEncrypted != true { return false }
		}

		// Environment filter (requires to-many relationship traversal)
		if isEnvironment {
			let hasEnvironmentTelemetry = node.telemetries.contains { $0.metricsType == 1 }
			if !hasEnvironmentTelemetry { return false }
		}

		// Distance filter (requires to-many relationship + math)
		if distanceFilter {
			if let pointOfInterest = LocationsHandler.currentLocation {
				if pointOfInterest.latitude != LocationsHandler.DefaultLocation.latitude &&
					pointOfInterest.longitude != LocationsHandler.DefaultLocation.longitude {
					let d: Double = maxDistance * 1.1
					let r: Double = 6371009
					let meanLatitude = pointOfInterest.latitude * .pi / 180
					let deltaLatitude = d / r * 180 / .pi
					let deltaLongitude = d / (r * cos(meanLatitude)) * 180 / .pi
					let minLatitude = pointOfInterest.latitude - deltaLatitude
					let maxLatitude = pointOfInterest.latitude + deltaLatitude
					let minLongitude = pointOfInterest.longitude - deltaLongitude
					let maxLongitude = pointOfInterest.longitude + deltaLongitude

					let hasPositionInRange = node.positions.contains { position in
						guard position.latest else { return false }
						let lon = Double(position.longitudeI) / 1e7
						let lat = Double(position.latitudeI) / 1e7
						return lon >= minLongitude && lon <= maxLongitude && lat >= minLatitude && lat <= maxLatitude
					}
					if !hasPositionInRange { return false }
				}
			}
		}

		return true
	}

	/// SwiftData predicate for count queries — simplified version that handles the most common case (ignored filter)
	func buildSwiftDataPredicate() -> Predicate<NodeInfoEntity>? {
		if isIgnored {
			return #Predicate<NodeInfoEntity> { $0.ignored == true }
		} else {
			return #Predicate<NodeInfoEntity> { $0.ignored == false }
		}
	}
}
