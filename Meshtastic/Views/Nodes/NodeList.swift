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
	@State private var nodeForDisplayNameEdit: NodeInfoEntity?
	@ObservedObject var filters = NodeFilterParameters.shared
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
					if opensSeededLocalStatsLog {
						LocalStatsLog(node: node)
					} else {
						NodeDetail(node: node)
					}
				} else {
					ContentUnavailableView("Select a Node", systemImage: "flipphone")
				}
			}
		}
		.navigationSplitViewStyle(.balanced)
		.onAppear {
			filters.fallbackLocation = connectedNode?.latestPosition?.nodeCoordinate
		}
		.onChange(of: accessoryManager.activeDeviceNum) {
			filters.fallbackLocation = connectedNode?.latestPosition?.nodeCoordinate
		}
	}

	private var opensSeededLocalStatsLog: Bool {
		#if DEBUG
		ProcessInfo.processInfo.arguments.contains("--meshtastic-perf-start-local-stats")
		#else
		false
		#endif
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
			nodeForDisplayNameEdit: $nodeForDisplayNameEdit,
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
				if filters.isFiltering {
					Button(action: {
						withAnimation {
							filters.reset()
						}
					}) {
						Image(systemName: "arrow.counterclockwise.circle")
							.padding(.vertical, 5)
					}
					.tint(Color(UIColor.secondarySystemBackground))
					.foregroundColor(.accentColor)
					.buttonStyle(.borderedProminent)
					.accessibilityLabel("Reset node filters")
					.accessibilityHint("Clears all active node filters.")
				}
				Button(action: {
					withAnimation {
						isEditingFilters = !isEditingFilters
					}
				}) {
					Image(systemName: filters.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
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
		.displayNameAlert(node: $nodeForDisplayNameEdit)
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
/// Wraps a NodeInfoEntity with a pre-extracted stable identity so that List/ForEach never
/// reads a key path on a live SwiftData object during diffing. If the backing object is
/// faulted between snapshot and render, the identity comparison still works safely.
private struct NodeListEntry: Identifiable {
	let id: Int64
	let node: NodeInfoEntity
}

/// Sendable inputs for the SwiftData `#Predicate` shared by the live `@Query` and the off-main
/// recompute, so the two can never drift (both build the predicate from the same source).
private struct NodePredicateInputs: Equatable {
	let showIgnored: Bool
	let showFavorite: Bool
	let filterViaLoraOnly: Bool
	let filterViaMqttOnly: Bool
	let filterHopsDirect: Bool
	let filterHopsMax: Bool
	let maxHops: Int32

	/// Single construction site for the predicate inputs, shared by the `@Query` and the off-main
	/// fetch so the two can't drift.
	@MainActor init(_ f: NodeFilterParameters) {
		showIgnored = f.isIgnored
		showFavorite = f.isFavorite
		filterViaLoraOnly = f.viaLora && !f.viaMqtt
		filterViaMqttOnly = !f.viaLora && f.viaMqtt
		filterHopsDirect = f.hopsAway == 0.0
		filterHopsMax = f.hopsAway > 0.0
		maxHops = Int32(f.hopsAway)
	}
}

/// Builds the query-level predicate (ignored/favorite/viaLora/viaMqtt/hopsAway). Used by BOTH the
/// `@Query` in `FilteredNodeList.init` and the off-main `computeNodeOrder`, guaranteeing identical
/// filtering on both sides of the isolation boundary.
private func makeNodeListPredicate(_ p: NodePredicateInputs) -> Predicate<NodeInfoEntity> {
	let showIgnored = p.showIgnored
	let showFavorite = p.showFavorite
	let filterViaLoraOnly = p.filterViaLoraOnly
	let filterViaMqttOnly = p.filterViaMqttOnly
	let filterHopsDirect = p.filterHopsDirect
	let filterHopsMax = p.filterHopsMax
	let maxHops = p.maxHops
	return #Predicate<NodeInfoEntity> { node in
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
	}
}

/// A fully-Sendable snapshot of the filter state, built on the main actor and consumed by the
/// off-main scan. Carrying only value types means no `@MainActor` object or SwiftData model crosses
/// the isolation boundary.
private struct FilterSnapshot: Sendable {
	let predicate: NodePredicateInputs
	let normalizedSearchText: String
	let roleFilter: Bool
	let deviceRoles: Set<Int>
	let onlineThreshold: Date?
	let isPkiEncrypted: Bool
	let isEnvironment: Bool
	let distanceFilter: Bool
	let distanceBounds: NodeDistanceFilterBounds?
	let activeNodeNum: Int64?

	@MainActor init(_ f: NodeFilterParameters, activeNodeNum: Int64?) {
		predicate = NodePredicateInputs(f)
		normalizedSearchText = f.searchText.lowercased()
		roleFilter = f.roleFilter
		deviceRoles = f.deviceRoles
		onlineThreshold = f.isOnline ? Date().addingTimeInterval(-7_200) : nil
		isPkiEncrypted = f.isPkiEncrypted
		isEnvironment = f.isEnvironment
		distanceFilter = f.distanceFilter
		distanceBounds = f.currentDistanceBounds
		self.activeNodeNum = activeNodeNum
	}
}

/// Equatable key over every result-affecting filter field; a change fires a recompute.
private struct NodeListFilterKey: Equatable {
	let search: String
	let isOnline: Bool
	let isPkiEncrypted: Bool
	let isFavorite: Bool
	let isIgnored: Bool
	let isEnvironment: Bool
	let distanceFilter: Bool
	let roleFilter: Bool
	let maxDistance: Double
	let hopsAway: Double
	let deviceRoles: Set<Int>
	let viaLora: Bool
	let viaMqtt: Bool
	let activeNodeNum: Int64?

	@MainActor init(_ f: NodeFilterParameters, active: Int64?) {
		search = f.searchText
		isOnline = f.isOnline
		isPkiEncrypted = f.isPkiEncrypted
		isFavorite = f.isFavorite
		isIgnored = f.isIgnored
		isEnvironment = f.isEnvironment
		distanceFilter = f.distanceFilter
		roleFilter = f.roleFilter
		maxDistance = f.maxDistance
		hopsAway = f.hopsAway
		deviceRoles = f.deviceRoles
		viaLora = f.viaLora
		viaMqtt = f.viaMqtt
		activeNodeNum = active
	}
}

/// Cheap signature of the node set; a change (insert/delete/reorder/new packet at top) fires a recompute.
private struct NodeListSetSignature: Equatable {
	let count: Int
	let topNum: Int64?
	let topHeard: Date?
}

/// Holds the recompute driver's stream continuation so `onChange` handlers can poke it. A reference
/// type kept in `@State` so the identity stays stable across body re-evaluations.
private final class NodeListRecomputeTrigger {
	var continuation: AsyncStream<Void>.Continuation?
}

/// The off-main scan (Fix 1): fetch + match, returning the matching node nums in lastHeard-desc order
/// as Sendable `[Int64]`. Runs on a fresh `ModelContext` created and fully consumed here with no
/// `await`, so nothing non-Sendable can escape. Moving OFF the main actor is the decisive win — the
/// O(N) search scan (which faults `\.user`) no longer blocks input, regardless of its absolute cost.
///
/// Deliberately does NOT partition into connected/favorite/regular: that ordering depends on
/// `node.favorite` and the active device, which the caller applies on the main actor from the LIVE
/// @Query objects. Otherwise an in-place favorite toggle (possibly not yet saved to the store this
/// background context reads) would be invisible until the write committed.
private func computeNodeOrder(container: ModelContainer, snapshot s: FilterSnapshot) -> [Int64] {
	let context = ModelContext(container)
	let descriptor = FetchDescriptor<NodeInfoEntity>(
		predicate: makeNodeListPredicate(s.predicate),
		sortBy: [SortDescriptor(\NodeInfoEntity.lastHeard, order: .reverse)]
	)
	guard let nodes = try? context.fetch(descriptor) else { return [] }

	let lookup = NodeListFilterLookup(
		nodes: nodes,
		needsEnvironment: s.isEnvironment,
		distanceBounds: s.distanceFilter ? s.distanceBounds : nil,
		context: context
	)
	var seen = Set<Int64>()
	seen.reserveCapacity(nodes.count)
	var matching: [Int64] = []
	matching.reserveCapacity(nodes.count)
	for node in nodes where matchesPostPredicate(node, snapshot: s, lookup: lookup) {
		let num = node.num
		if seen.insert(num).inserted { matching.append(num) }
	}
	return matching
}

private struct FilteredNodeList: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var router: Router
	@Query(sort: \NodeInfoEntity.lastHeard, order: .reverse)
	private var allNodes: [NodeInfoEntity]
	@Environment(\.modelContext) private var context
	/// Snapshot of the filtered/sorted nodes actually shown. Recomputed OFF the main actor by
	/// `recompute()`, driven by real change signals (filter/search edits + node-set changes) and
	/// coalesced — replacing the old unconditional poll. See the `.task` driver in `body`.
	@State private var displayedNodes: [NodeListEntry] = []
	/// Stable continuation holder for the recompute driver; `onChange` handlers poke it to request a pass.
	@State private var recomputeTrigger = NodeListRecomputeTrigger()
	/// False until the first off-main recompute lands, so the view shows a loading indicator instead of
	/// flashing an empty "Nodes (0)" list during the initial off-main fetch on a cold, large DB.
	@State private var hasCompletedFirstRecompute = false

	var connectedNode: NodeInfoEntity?
	@Binding var isPresentingDeleteNodeAlert: Bool
	@Binding var deleteNodeId: Int64
	@Binding var shareContactNode: NodeInfoEntity?
	@Binding var nodeForDisplayNameEdit: NodeInfoEntity?
	@Binding var nodeListDensity: NodeListDensity
	@Binding var selectedNodeNum: Int64?
	var filters: NodeFilterParameters

	init(
		withFilters: NodeFilterParameters,
		connectedNode: NodeInfoEntity?,
		isPresentingDeleteNodeAlert: Binding<Bool>,
		deleteNodeId: Binding<Int64>,
		shareContactNode: Binding<NodeInfoEntity?>,
		nodeForDisplayNameEdit: Binding<NodeInfoEntity?>,
		nodeListDensity: Binding<NodeListDensity>,
		selectedNodeNum: Binding<Int64?>
	) {
		self.filters = withFilters
		self.connectedNode = connectedNode
		self._isPresentingDeleteNodeAlert = isPresentingDeleteNodeAlert
		self._deleteNodeId = deleteNodeId
		self._shareContactNode = shareContactNode
		self._nodeForDisplayNameEdit = nodeForDisplayNameEdit
		self._nodeListDensity = nodeListDensity
		self._selectedNodeNum = selectedNodeNum

		// Push simple filters into the SwiftData predicate to reduce in-memory work. The SAME
		// predicate feeds both this @Query and the off-main computeNodeOrder (see
		// makeNodeListPredicate), so the two fetched sets can never drift.
		_allNodes = Query(
			filter: makeNodeListPredicate(NodePredicateInputs(withFilters)),
			sort: \NodeInfoEntity.lastHeard,
			order: .reverse
		)
	}

	/// Equatable key over every result-affecting filter field; drives a recompute on change.
	private var filterKey: NodeListFilterKey {
		NodeListFilterKey(filters, active: accessoryManager.activeDeviceNum)
	}

	/// Cheap node-set signature; fires an instant recompute on insert/delete and on a new packet
	/// reaching the top of the list. Coarse by design (reading every node's fields here would re-fault
	/// the whole set on the main actor on each body eval); non-top reorders and in-place edits are
	/// picked up by the periodic off-main refresh in the `.task` driver instead.
	private var nodeSetSignature: NodeListSetSignature {
		NodeListSetSignature(count: allNodes.count, topNum: allNodes.first?.num, topHeard: allNodes.first?.lastHeard)
	}

	/// Recompute the displayed list. The expensive fetch + search match runs OFF the main actor on a
	/// fresh, confined `ModelContext` and returns only matching `[Int64]` node nums (Sendable). Back on
	/// the main actor those nums are mapped onto the LIVE `@Query` objects the `List` renders and
	/// partitioned into connected → favorites → regular using their CURRENT state — so no
	/// background-context model ever reaches the List (SIGTRAP hardening) and in-place favorite/connect
	/// changes re-section immediately without waiting for the background store read to catch up.
	@MainActor private func recompute() async {
		let snapshot = FilterSnapshot(filters, activeNodeNum: accessoryManager.activeDeviceNum)
		// Use the @Query's own container (via the environment context) rather than a hard-coded global,
		// so the off-main fetch always reads the SAME store the List renders from (previews/tests/any
		// injected container included).
		let container = context.container
		let matching = await Task.detached(priority: .userInitiated) {
			computeNodeOrder(container: container, snapshot: snapshot)
		}.value
		guard !Task.isCancelled else { return }

		// Map matching nums onto the LIVE @Query objects and partition using their current favorite /
		// active-device state (cheap scalar reads — no relationship fault). The `modelContext != nil`
		// guard keeps the existing SIGTRAP hardening; transient byNum misses self-heal on the next pass.
		let activeNodeNum = accessoryManager.activeDeviceNum
		var byNum = [Int64: NodeInfoEntity](minimumCapacity: allNodes.count)
		for node in allNodes { byNum[node.num] = node }
		var connected: NodeListEntry?
		var favorites: [NodeListEntry] = []
		var regular: [NodeListEntry] = []
		favorites.reserveCapacity(matching.count / 20)
		regular.reserveCapacity(matching.count)
		for num in matching {
			guard let node = byNum[num], node.modelContext != nil else { continue }
			let entry = NodeListEntry(id: num, node: node)
			if let activeNodeNum, num == activeNodeNum {
				connected = entry
			} else if node.favorite {
				favorites.append(entry)
			} else {
				regular.append(entry)
			}
		}
		var entries: [NodeListEntry] = []
		entries.reserveCapacity((connected == nil ? 0 : 1) + favorites.count + regular.count)
		if let connected { entries.append(connected) }
		entries.append(contentsOf: favorites)
		entries.append(contentsOf: regular)
		replaceDisplayedNodesIfNeeded(with: entries)
		hasCompletedFirstRecompute = true
	}

	private func replaceDisplayedNodesIfNeeded(with newNodes: [NodeListEntry]) {
		guard displayedNodeIDsDiffer(from: newNodes) else { return }
		displayedNodes = newNodes
	}

	private func displayedNodeIDsDiffer(from newNodes: [NodeListEntry]) -> Bool {
		guard displayedNodes.count == newNodes.count else { return true }
		for (currentNode, newNode) in zip(displayedNodes, newNodes)
			where currentNode.id != newNode.id || currentNode.node !== newNode.node {
			return true
		}
		return false
	}

	// The body of the view
	var body: some View {
		List(displayedNodes, selection: $selectedNodeNum) { entry in
			if entry.node.modelContext != nil {
				NavigationLink(value: entry.id) {
					switch nodeListDensity {
					case .compact:
						NodeListItemCompact(
							node: entry.node,
							isDirectlyConnected: entry.id == accessoryManager.activeDeviceNum,
							connectedNode: accessoryManager.activeConnection?.device.num ?? -1)
					case .standard:
						NodeListItem(
							node: entry.node,
							isDirectlyConnected: entry.id == accessoryManager.activeDeviceNum,
							connectedNode: accessoryManager.activeConnection?.device.num ?? -1
						)
					}
				}
				.contextMenu {
					contextMenuActions(
						node: entry.node,
						connectedNode: connectedNode
					)
				}
			}
		}
		.overlay {
			// Avoid flashing an empty "Nodes (0)" list while the first off-main recompute is in flight
			// on a cold, large DB.
			if !hasCompletedFirstRecompute && displayedNodes.isEmpty {
				ProgressView()
			}
		}
		.navigationTitle(hasCompletedFirstRecompute
			? String.localizedStringWithFormat("Nodes (%@)".localized, String(displayedNodes.count))
			: "Nodes".localized)
		.task {
			// Change-driven, coalesced recompute — replaces the old unconditional 350ms poll.
			// A single long-lived consumer drains a bufferingNewest(1) stream: a burst (e.g. a reconnect
			// nodeDB dump firing thousands of node-set changes) collapses to one pending pass, and the
			// 300ms throttle caps recompute at ~3/sec. The heavy scan runs off the main actor, so even
			// during the storm the main thread stays ~idle. The stream is created HERE (not in @State)
			// so it is rebuilt cleanly on every disappear/reappear.
			let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
			recomputeTrigger.continuation = continuation
			defer { continuation.finish() }
			// Periodic off-main refresh for inputs that fire NO change signal: device GPS movement (with
			// the distance filter on), wall-clock crossing a node's online window, non-top lastHeard
			// reorders, and in-place favorite toggles. The old 350ms MAIN-thread poll covered these by
			// brute force; this is the same idea but off-main and gentler (~1.5s). Interactive changes
			// (search/filter edits, node inserts/deletes) still refresh instantly via the onChange
			// triggers below — this only backstops the un-observable inputs.
			let backstop = Task {
				while !Task.isCancelled {
					try? await Task.sleep(for: .milliseconds(1500))
					continuation.yield(())
				}
			}
			defer { backstop.cancel() }
			await recompute()   // first paint
			var last = ContinuousClock.now
			for await _ in stream {
				let elapsed = ContinuousClock.now - last
				if elapsed < .milliseconds(300) {
					try? await Task.sleep(for: .milliseconds(300) - elapsed)
				}
				if Task.isCancelled { break }
				await recompute()
				last = .now
			}
		}
		.onChange(of: filterKey) { _, _ in
			recomputeTrigger.continuation?.yield(())
		}
		.onChange(of: nodeSetSignature) { _, _ in
			recomputeTrigger.continuation?.yield(())
		}
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
		// Local-only rename — never touches the mesh (NodeDisplayNameStore), so unlike the actions
		// below it doesn't need an active device connection. Available for any node in the local
		// database regardless of connection state.
		Button {
			nodeForDisplayNameEdit = node
		} label: {
			Label("Display name", systemImage: "person.crop.circle")
		}
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
	/// Node nums that have at least one `latest` PositionEntity. Used by `isWithinDistance`
	/// so that nodes with no position data pass through the distance filter rather than
	/// being silently excluded.
	private let positionedNodeNums: Set<Int64>?

	init(
		nodes: [NodeInfoEntity],
		needsEnvironment: Bool,
		distanceBounds: NodeDistanceFilterBounds?,
		context: ModelContext
	) {
		// Only materialize the node-num set (a scan over every node) when a filter actually
		// needs it; the common no-filter case skips this work entirely.
		guard needsEnvironment || distanceBounds != nil else {
			self.environmentNodeNums = nil
			self.distanceNodeNums = nil
			self.positionedNodeNums = nil
			return
		}
		let nodeNums = Array(Set(nodes.map(\.num)))
		if needsEnvironment {
			self.environmentNodeNums = Self.fetchEnvironmentNodeNums(nodeNums: nodeNums, context: context)
		} else {
			self.environmentNodeNums = nil
		}
		if let distanceBounds {
			let (within, positioned) = Self.fetchDistanceNodeNums(nodeNums: nodeNums, bounds: distanceBounds, context: context)
			self.distanceNodeNums = within
			self.positionedNodeNums = positioned
		} else {
			self.distanceNodeNums = nil
			self.positionedNodeNums = nil
		}
	}

	func hasEnvironmentMetrics(_ node: NodeInfoEntity) -> Bool {
		environmentNodeNums?.contains(node.num) ?? node.hasEnvironmentMetrics
	}

	func isWithinDistance(_ node: NodeInfoEntity) -> Bool {
		guard let distanceNodeNums else { return true }
		// Nodes with no known position are not excluded by the distance filter.
		guard positionedNodeNums?.contains(node.num) == true else { return true }
		return distanceNodeNums.contains(node.num)
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
	) -> (withinBounds: Set<Int64>, withAnyPosition: Set<Int64>) {
		guard !nodeNums.isEmpty else { return ([], []) }
		let descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> {
				$0.latest == true
				&& $0.nodePosition != nil
				&& ($0.nodePosition.flatMap { nodeNums.contains($0.num) } ?? false)
			}
		)
		let positions = (try? context.fetch(descriptor)) ?? []
		var withinBounds = Set<Int64>()
		var withAnyPosition = Set<Int64>()
		for position in positions {
			guard let num = position.nodePosition?.num else { continue }
			withAnyPosition.insert(num)
			if bounds.contains(position) {
				withinBounds.insert(num)
			}
		}
		return (withinBounds, withAnyPosition)
	}
}

//
//  NodeFilterParameters+Predicate.swift
//  Meshtastic
//

/// The in-memory post-predicate match (search + role/online/pki/environment/distance), reading a
/// Sendable `FilterSnapshot` so it can run OFF the main actor. Mirrors the filters NOT pushed into
/// the @Query predicate. (Was a `NodeFilterParameters` extension; converted to a free function so
/// the off-main scan doesn't touch the @MainActor filter object.)
private func matchesPostPredicate(
	_ node: NodeInfoEntity,
	snapshot s: FilterSnapshot,
	lookup: NodeListFilterLookup
) -> Bool {
	// Search text (requires relationship traversal)
	if !s.normalizedSearchText.isEmpty {
		let matchesSearch = [
			node.user?.userId,
			node.user?.numString,
			node.user?.hwModel,
			node.user?.hwDisplayName,
			node.user?.longName,
			node.user?.shortName
		].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(s.normalizedSearchText) }
		if !matchesSearch { return false }
	}

	// Role filter (requires relationship traversal)
	if s.roleFilter && !s.deviceRoles.isEmpty {
		guard let role = node.user?.role else { return false }
		if !s.deviceRoles.contains(Int(role)) { return false }
	}

	// Online filter (threshold is non-nil only when the online filter is active)
	if let threshold = s.onlineThreshold {
		guard let lastHeard = node.lastHeard, lastHeard >= threshold else { return false }
	}

	// Encrypted filter (requires relationship traversal)
	if s.isPkiEncrypted {
		if node.user?.pkiEncrypted != true { return false }
	}

	// Environment filter (requires to-many relationship traversal)
	if s.isEnvironment {
		if !lookup.hasEnvironmentMetrics(node) { return false }
	}

	// Distance filter (requires latest position lookup)
	if s.distanceFilter, s.distanceBounds != nil {
		guard lookup.isWithinDistance(node) else {
			return false
		}
	}

	return true
}
