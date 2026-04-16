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
	/// Debounce delay for node selection changes (100ms)
	private static let nodeSelectionDebounceNs: UInt64 = 100_000_000

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@StateObject var router: Router
	@State private var selectedNode: NodeInfoEntity?
	@State private var nodeSelectionTask: Task<Void, Never>?
	@State private var isPresentingTraceRouteSentAlert = false
	@State private var isPresentingPositionSentAlert = false
	@State private var isPresentingPositionFailedAlert = false
	@State private var isPresentingDeleteNodeAlert = false
	@State private var deleteNodeId: Int64 = 0
	@State private var shareContactNode: NodeInfoEntity?
	@StateObject var filters = NodeFilterParameters()
	@State var isEditingFilters = false
	@State private var filteredNodeCount: Int = 0
	@SceneStorage("selectedDetailView") var selectedDetailView: String?

	var connectedNode: NodeInfoEntity? {
		if let num = accessoryManager.activeDeviceNum {
			return getNodeInfo(id: num, context: context)
		}
		return nil
	}

	var body: some View {
		NavigationSplitView {
			FilteredNodeList(
				router: router,
				withFilters: filters,
				selectedNode: $selectedNode,
				connectedNode: connectedNode,
				isPresentingDeleteNodeAlert: $isPresentingDeleteNodeAlert,
				deleteNodeId: $deleteNodeId,
				shareContactNode: $shareContactNode,
				filteredNodeCount: $filteredNodeCount
			)
			.sheet(isPresented: $isEditingFilters) {
				NodeListFilter(
					filters: filters
				)
			}
			.safeAreaInset(edge: .bottom, alignment: .trailing) {
				HStack {
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
			.navigationTitle(String.localizedStringWithFormat("Nodes (%@)".localized, String(filteredNodeCount)))
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
				Button("Delete Node", role: .destructive) {
					let deleteNode = getNodeInfo(id: deleteNodeId, context: context)
					if connectedNode != nil {
						if let node = deleteNode {
							Task {
								do {
									try await accessoryManager.removeNode(node: node, connectedNodeNum: Int64(accessoryManager.activeDeviceNum ?? -1))
								} catch {
									Logger.data.error("Failed to delete node \(node.user?.longName ?? "Unknown".localized, privacy: .public)")
								}
							}
						}
					}
				}
			}
			.sheet(item: $shareContactNode) { selectedNode in
				ShareContactQRDialog(node: selectedNode.toProto())
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
		} detail: {
			if let node = selectedNode {
				NodeDetail(
					connectedNode: connectedNode,
					node: node
				)
			} else {
				ContentUnavailableView("Select a Node", systemImage: "flipphone")
			}
		}
		.onChange(of: router.nodeListSelectedNodeNum) { _, newNum in
			// Debounce rapid route changes — only process the last selection after a short delay
			nodeSelectionTask?.cancel()
			nodeSelectionTask = Task { @MainActor in
				do {
					try await Task.sleep(nanoseconds: Self.nodeSelectionDebounceNs)
				} catch {
					return // Cancelled by a newer selection
				}
				if let num = newNum {
					self.selectedNode = router.cachedNodeInfo(id: num, context: context)
				} else {
					self.selectedNode = nil
				}
			}
		}
		.onChange(of: selectedNode) { _, node in
			if let num = node?.num {
				router.nodeListSelectedNodeNum = num
			} else {
				router.nodeListSelectedNodeNum = nil
			}
		}
	}

}

//
//  FilteredNodeList.swift
//  Meshtastic
//
fileprivate struct FilteredNodeList: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Query(sort: \NodeInfoEntity.lastHeard, order: .reverse)
	private var allNodes: [NodeInfoEntity]
	@Environment(\.modelContext) private var context
	var router: Router

	@Binding var selectedNode: NodeInfoEntity?
	var connectedNode: NodeInfoEntity?
	@Binding var isPresentingDeleteNodeAlert: Bool
	@Binding var deleteNodeId: Int64
	@Binding var shareContactNode: NodeInfoEntity?
	@Binding var filteredNodeCount: Int
	private var filters: NodeFilterParameters

	// The initializer for the FetchRequest
	init(
		router: Router,
		withFilters: NodeFilterParameters,
		selectedNode: Binding<NodeInfoEntity?>,
		connectedNode: NodeInfoEntity?,
		isPresentingDeleteNodeAlert: Binding<Bool>,
		deleteNodeId: Binding<Int64>,
		shareContactNode: Binding<NodeInfoEntity?>,
		filteredNodeCount: Binding<Int>
	) {
		self.router = router
		self.filters = withFilters
		self._selectedNode = selectedNode
		self.connectedNode = connectedNode
		self._isPresentingDeleteNodeAlert = isPresentingDeleteNodeAlert
		self._deleteNodeId = deleteNodeId
		self._shareContactNode = shareContactNode
		self._filteredNodeCount = filteredNodeCount
	}

	private var nodes: [NodeInfoEntity] {
		allNodes.filter { filters.matches(node: $0) }
	}

	// The body of the view
	var body: some View {
		// If the connected node passes filters, always show it first (single-pass)
		let nodesWithConnectedFirst: [NodeInfoEntity] = {
			let activeNum = accessoryManager.activeDeviceNum
			var result: [NodeInfoEntity] = []
			result.reserveCapacity(nodes.count)
			var connectedNode: NodeInfoEntity?
			for node in nodes {
				if node.num == activeNum {
					connectedNode = node
				} else {
					result.append(node)
				}
			}
			if let connectedNode {
				result.insert(connectedNode, at: 0)
			}
			return result
		}()
		List(nodesWithConnectedFirst, id: \.self, selection: $selectedNode) { node in
			NavigationLink(value: node) {
				NodeListItem(
					node: node,
					isDirectlyConnected: node.num == accessoryManager.activeDeviceNum,
					connectedNode: accessoryManager.activeConnection?.device.num ?? -1
				)
			}
			.contextMenu {
				contextMenuActions(
					node: node,
					connectedNode: connectedNode
				)
			}
		}
		.onAppear {
			router.updateNodeIndex(from: nodes)
			filteredNodeCount = nodes.count
		}
		.onChange(of: nodes.count) { _, newCount in
			router.updateNodeIndex(from: nodes)
			filteredNodeCount = newCount
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
	func matches(node: NodeInfoEntity) -> Bool {
		// Search text
		if !searchText.isEmpty {
			let text = searchText.lowercased()
			let fields = [node.user?.userId, node.user?.numString, node.user?.hwModel,
						  node.user?.hwDisplayName, node.user?.longName, node.user?.shortName]
			let matchesSearch = fields.compactMap { $0?.lowercased() }.contains { $0.contains(text) }
			if !matchesSearch { return false }
		}
		// Favorite
		if isFavorite && !node.favorite { return false }
		// Via Lora/MQTT
		if viaLora && !viaMqtt && node.viaMqtt { return false }
		if !viaLora && viaMqtt && !node.viaMqtt { return false }
		// Roles
		if roleFilter && !deviceRoles.isEmpty {
			let userRole = Int(node.user?.role ?? 0)
			if !deviceRoles.contains(userRole) { return false }
		}
		// Hops Away
		if hopsAway == 0 && node.hopsAway != 0 { return false }
		if hopsAway > 0 && (node.hopsAway <= 0 || node.hopsAway > Int32(hopsAway)) { return false }
		// Online
		if isOnline {
			let twoHoursAgo = Calendar.current.date(byAdding: .minute, value: -120, to: Date()) ?? Date.distantPast
			if let lastHeard = node.lastHeard, lastHeard < twoHoursAgo { return false }
			if node.lastHeard == nil { return false }
		}
		// Encrypted
		if isPkiEncrypted && node.user?.pkiEncrypted != true { return false }
		// Ignored
		if isIgnored {
			if !node.ignored { return false }
		} else {
			if node.ignored { return false }
		}
		// Environment
		if isEnvironment {
			let hasEnvTelemetry = (node.telemetries ?? []).contains { $0.metricsType == 1 }
			if !hasEnvTelemetry { return false }
		}
		// Distance
		if distanceFilter {
			if let poi = LocationsHandler.currentLocation,
			   poi.latitude != LocationsHandler.DefaultLocation.latitude,
			   poi.longitude != LocationsHandler.DefaultLocation.longitude {
				let d = maxDistance * 1.1
				let r: Double = 6371009
				let meanLat = poi.latitude * .pi / 180
				let deltaLat = d / r * 180 / .pi
				let deltaLon = d / (r * cos(meanLat)) * 180 / .pi
				let minLat = poi.latitude - deltaLat
				let maxLat = poi.latitude + deltaLat
				let minLon = poi.longitude - deltaLon
				let maxLon = poi.longitude + deltaLon
				let hasNearbyPosition = (node.positions ?? []).contains { pos in
					guard pos.latest else { return false }
					let lon = Double(pos.longitudeI) / 1e7
					let lat = Double(pos.latitudeI) / 1e7
					return lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat
				}
				if !hasNearbyPosition { return false }
			}
		}
		return true
	}

	func buildPredicate() -> NSPredicate? {
		var predicates: [NSPredicate] = []

		// Search text predicates
		if !searchText.isEmpty {
			let searchKeys = [
				"user.userId", "user.numString", "user.hwModel",
				"user.hwDisplayName", "user.longName", "user.shortName"
			]
			let textPredicates = searchKeys.map {
				NSPredicate(format: "%K CONTAINS[c] %@", $0, searchText)
			}
			predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: textPredicates))
		}

		// Favorite filter
		if isFavorite {
			predicates.append(NSPredicate(format: "favorite == YES"))
		}

		// Via Lora/MQTT filters
		if viaLora && !viaMqtt {
			predicates.append(NSPredicate(format: "viaMqtt == NO"))
		} else if !viaLora && viaMqtt {
			predicates.append(NSPredicate(format: "viaMqtt == YES"))
		}

		// Role filter
		if roleFilter && !deviceRoles.isEmpty {
			let rolesPredicates = deviceRoles.map {
				NSPredicate(format: "user.role == %i", Int32($0))
			}
			predicates.append(NSCompoundPredicate(type: .or, subpredicates: rolesPredicates))
		}

		// Hops Away filter
		if hopsAway == 0.0 {
			predicates.append(NSPredicate(format: "hopsAway == %i", 0))
		} else if hopsAway > 0.0 {
			predicates.append(NSPredicate(format: "hopsAway > 0 AND hopsAway <= %i", Int32(hopsAway)))
		}

		// Online filter
		if isOnline {
			let isOnlinePredicate = NSPredicate(format: "lastHeard >= %@", Calendar.current.date(byAdding: .minute, value: -120, to: Date())! as NSDate)
			predicates.append(isOnlinePredicate)
		}

		// Encrypted filter
		if isPkiEncrypted {
			predicates.append(NSPredicate(format: "user.pkiEncrypted == YES"))
		}

		// Ignored filter
		if isIgnored {
			predicates.append(NSPredicate(format: "ignored == YES"))
		} else {
			predicates.append(NSPredicate(format: "ignored == NO"))
		}

		// Environment filter
		if isEnvironment {
			predicates.append(NSPredicate(format: "SUBQUERY(telemetries, $tel, $tel.metricsType == 1).@count > 0"))
		}

		// Distance filter
		if distanceFilter {
			if let pointOfInterest = LocationsHandler.currentLocation {

				if pointOfInterest.latitude != LocationsHandler.DefaultLocation.latitude && pointOfInterest.longitude != LocationsHandler.DefaultLocation.longitude {
					let d: Double = maxDistance * 1.1
					let r: Double = 6371009
					let meanLatitidue = pointOfInterest.latitude * .pi / 180
					let deltaLatitude = d / r * 180 / .pi
					let deltaLongitude = d / (r * cos(meanLatitidue)) * 180 / .pi
					let minLatitude: Double = pointOfInterest.latitude - deltaLatitude
					let maxLatitude: Double = pointOfInterest.latitude + deltaLatitude
					let minLongitude: Double = pointOfInterest.longitude - deltaLongitude
					let maxLongitude: Double = pointOfInterest.longitude + deltaLongitude
					let distancePredicate = NSPredicate(format: "(SUBQUERY(positions, $position, $position.latest == TRUE && (%lf <= ($position.longitudeI / 1e7)) AND (($position.longitudeI / 1e7) <= %lf) AND (%lf <= ($position.latitudeI / 1e7)) AND (($position.latitudeI / 1e7) <= %lf))).@count > 0", minLongitude, maxLongitude, minLatitude, maxLatitude)
					predicates.append(distancePredicate)
				}
			}
		}
		return predicates.isEmpty ? nil : NSCompoundPredicate(type: .and, subpredicates: predicates)
	}
}
