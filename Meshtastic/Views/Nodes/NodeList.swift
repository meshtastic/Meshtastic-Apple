//
//  NodeList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/8/23.
//
import SwiftUI
import CoreLocation
import OSLog
@preconcurrency import SwiftData
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
				   let node = router.cachedNodeInfo(id: selectedNum, context: context) {
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
		.toolbar {
			ToolbarItem(placement: .topBarLeading) {
				MeshtasticLogo()
			}
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(
					deviceConnected: accessoryManager.isConnected,
					name: accessoryManager.activeConnection?.device.shortName ?? "?",
					phoneOnly: true
				)
				.accessibilityElement(children: .contain)
			}
		}
	}

	@ViewBuilder
	private var deleteNodeButton: some View {
		Button("Remove", role: .destructive) {
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
	@EnvironmentObject var router: Router
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

	private func displayNodes(activeNodeNum: Int64?) -> [NodeInfoEntity] {
		let searchText = filters.searchText.lowercased()
		let onlineThreshold = filters.isOnline ? Date().addingTimeInterval(-7_200) : nil
		let distanceBounds = filters.currentDistanceBounds
		let filterLookup = NodeListFilterLookup(
			nodes: allNodes,
			needsEnvironment: filters.isEnvironment,
			distanceBounds: filters.distanceFilter ? distanceBounds : nil,
			context: context
		)
		var seenNodeNums = Set<Int64>()
		seenNodeNums.reserveCapacity(allNodes.count)
		var connectedNode: NodeInfoEntity?
		var favoriteNodes: [NodeInfoEntity] = []
		var regularNodes: [NodeInfoEntity] = []
		favoriteNodes.reserveCapacity(allNodes.count / 20)
		regularNodes.reserveCapacity(allNodes.count)

		for node in allNodes where filters.matchesPostPredicate(
			node,
			normalizedSearchText: searchText,
			onlineThreshold: onlineThreshold,
			distanceBounds: distanceBounds,
			lookup: filterLookup
		) {
			guard seenNodeNums.insert(node.num).inserted else { continue }
			if let activeNodeNum, node.num == activeNodeNum {
				connectedNode = node
			} else if node.favorite {
				favoriteNodes.append(node)
			} else {
				regularNodes.append(node)
			}
		}

		var nodes: [NodeInfoEntity] = []
		nodes.reserveCapacity((connectedNode == nil ? 0 : 1) + favoriteNodes.count + regularNodes.count)
		if let connectedNode {
			nodes.append(connectedNode)
		}
		nodes.append(contentsOf: favoriteNodes)
		nodes.append(contentsOf: regularNodes)
		return nodes
	}

	// The body of the view
	var body: some View {
		let uniqueNodes = displayNodes(activeNodeNum: accessoryManager.activeDeviceNum)
		List(uniqueNodes, id: \.num, selection: $selectedNodeNum) { node in
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
		.navigationTitle(String.localizedStringWithFormat("Nodes (%@)".localized, String(uniqueNodes.count)))
		.onAppear {
			router.updateNodeIndex(from: allNodes)
		}
		.onChange(of: allNodes.count) { _, _ in
			router.updateNodeIndex(from: allNodes)
		}
	}

	@ViewBuilder
	func contextMenuActions(
		node: NodeInfoEntity,
		connectedNode: NodeInfoEntity?
	) -> some View {
		if let connectedNode {
			FavoriteNodeButton(node: node)
			if let user = node.user {
				NodeAlertsButton(context: context, node: node, user: user)
			}
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
					Label("Remove", systemImage: "trash")
				}
			}
		}
	}
}

private struct NodeListFilterLookup {
	private let environmentNodeNums: Set<Int64>?
	private let distanceNodeNums: Set<Int64>?

	init(
		nodes: [NodeInfoEntity],
		needsEnvironment: Bool,
		distanceBounds: NodeDistanceFilterBounds?,
		context: ModelContext
	) {
		let nodeNums = Array(Set(nodes.map(\.num)))
		if needsEnvironment {
			self.environmentNodeNums = Self.fetchEnvironmentNodeNums(nodeNums: nodeNums, context: context)
		} else {
			self.environmentNodeNums = nil
		}
		if let distanceBounds {
			self.distanceNodeNums = Self.fetchDistanceNodeNums(nodeNums: nodeNums, bounds: distanceBounds, context: context)
		} else {
			self.distanceNodeNums = nil
		}
	}

	func hasEnvironmentMetrics(_ node: NodeInfoEntity) -> Bool {
		environmentNodeNums?.contains(node.num) ?? node.hasEnvironmentMetrics
	}

	func isWithinDistance(_ node: NodeInfoEntity) -> Bool {
		distanceNodeNums?.contains(node.num) ?? false
	}

	private static func fetchEnvironmentNodeNums(nodeNums: [Int64], context: ModelContext) -> Set<Int64> {
		guard !nodeNums.isEmpty else { return [] }
		let metricsType: Int32 = 1
		let descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> {
				$0.metricsType == metricsType
				&& $0.nodeTelemetry != nil
				&& ($0.nodeTelemetry.flatMap { nodeNums.contains($0.num) } ?? false)
			}
		)
		let metrics = (try? context.fetch(descriptor)) ?? []
		return Set(metrics.compactMap { $0.nodeTelemetry?.num })
	}

	private static func fetchDistanceNodeNums(
		nodeNums: [Int64],
		bounds: NodeDistanceFilterBounds,
		context: ModelContext
	) -> Set<Int64> {
		guard !nodeNums.isEmpty else { return [] }
		let descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> {
				$0.latest == true
				&& $0.nodePosition != nil
				&& ($0.nodePosition.flatMap { nodeNums.contains($0.num) } ?? false)
			}
		)
		let positions = (try? context.fetch(descriptor)) ?? []
		return Set(positions.compactMap { position in
			guard bounds.contains(position) else { return nil }
			return position.nodePosition?.num
		})
	}
}

//
//  NodeFilterParameters+Predicate.swift
//  Meshtastic
//

fileprivate extension NodeFilterParameters {
	/// Filters already pushed into the @Query predicate: ignored, favorite, viaLora/viaMqtt, hopsAway.
	func matchesPostPredicate(
		_ node: NodeInfoEntity,
		normalizedSearchText: String,
		onlineThreshold: Date?,
		distanceBounds: NodeDistanceFilterBounds?,
		lookup: NodeListFilterLookup
	) -> Bool {
		// Search text (requires relationship traversal)
		if !normalizedSearchText.isEmpty {
			let matchesSearch = [
				node.user?.userId,
				node.user?.numString,
				node.user?.hwModel,
				node.user?.hwDisplayName,
				node.user?.longName,
				node.user?.shortName
			].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(normalizedSearchText) }
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
				  let threshold = onlineThreshold else {
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
			if !lookup.hasEnvironmentMetrics(node) { return false }
		}

		// Distance filter (requires latest position lookup)
		if distanceFilter, distanceBounds != nil {
			guard lookup.isWithinDistance(node) else {
				return false
			}
		}

		return true
	}
}
