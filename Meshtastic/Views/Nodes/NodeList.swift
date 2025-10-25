//
//  NodeList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/8/23.
//
import SwiftUI
import SwiftUIBackports
import NavigationBackport
import CoreLocation
import OSLog
import CoreData
import Foundation

struct NodeList: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@StateObject var router: Router
	@State private var selectedNode: NodeInfoEntity?
	@State private var isPresentingTraceRouteSentAlert = false
	@State private var isPresentingPositionSentAlert = false
	@State private var isPresentingPositionFailedAlert = false
	@State private var isPresentingDeleteNodeAlert = false
	@State private var deleteNodeId: Int64 = 0
	@State private var shareContactNode: NodeInfoEntity?
	@StateObject var filters = NodeFilterParameters()
	@State var isEditingFilters = false
	@SceneStorage("selectedDetailView") var selectedDetailView: String?
	
	var connectedNode: NodeInfoEntity? {
		if let num = accessoryManager.activeDeviceNum {
			return getNodeInfo(id: num, context: context)
		}
		return nil
	}
	
	var body: some View {
		Group {
			if #available(iOS 16, *) {
				splitViewBody
			} else {
				legacyBody
			}
		}
		.backport.onChange(of: router.navigationState.nodeListSelectedNodeNum) { _, newNum in
			if let num = newNum {
				self.selectedNode = getNodeInfo(id: num, context: context)
			} else {
				self.selectedNode = nil
			}
		}
		.backport.onChange(of: selectedNode) { _, node in
			if let num = node?.num {
				router.navigationState.nodeListSelectedNodeNum = num
			} else {
				router.navigationState.nodeListSelectedNodeNum = nil
			}
		}
	}

	@available(iOS 16, *)
	private var splitViewBody: some View {
		NavigationSplitView {
			sharedListContent
				.navigationSplitViewColumnWidth(min: 100, ideal: 300, max: .infinity)
		} detail: {
			if let node = selectedNode {
				NodeDetail(
					connectedNode: connectedNode,
					node: node
				)
			} else {
				Backport.ContentUnavailableView("Select a Node", systemImage: "flipphone")
			}
		}
		.navigationBarItems(leading: MeshtasticLogo(), trailing: ZStack {
			ConnectedDevice(
				deviceConnected: accessoryManager.isConnected,
				name: accessoryManager.activeConnection?.device.shortName ?? "?",
				phoneOnly: true
			)
		}
		.accessibilityElement(children: .contain))
	}

	private var legacyBody: some View {
		NBNavigationStack {
			sharedListContent
				.navigationBarItems(leading: MeshtasticLogo(), trailing: ZStack {
					ConnectedDevice(
						deviceConnected: accessoryManager.isConnected,
						name: accessoryManager.activeConnection?.device.shortName ?? "?",
						phoneOnly: true
					)
				}
				.accessibilityElement(children: .contain))
		}
	}

	@ViewBuilder
	private var sharedListContent: some View {
		FilteredNodeList(
			withFilters: filters,
			selectedNode: $selectedNode,
			connectedNode: connectedNode,
			isPresentingDeleteNodeAlert: $isPresentingDeleteNodeAlert,
			deleteNodeId: $deleteNodeId,
			shareContactNode: $shareContactNode
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
		.backport.scrollDismissesKeyboard(.immediately)
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
	}
	
	// Helper to get the count of nodes for the navigation title
	private func getNodeCount() -> Int {
		let request: NSFetchRequest<NodeInfoEntity> = NodeInfoEntity.fetchRequest()
		request.predicate = filters.buildPredicate()
		return (try? context.count(for: request)) ?? 0
	}
}

//
//  FilteredNodeList.swift
//  Meshtastic
//
fileprivate struct FilteredNodeList: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@FetchRequest private var nodes: FetchedResults<NodeInfoEntity>
	@Environment(\.managedObjectContext) var context
	
	@Binding var selectedNode: NodeInfoEntity?
	var connectedNode: NodeInfoEntity?
	@Binding var isPresentingDeleteNodeAlert: Bool
	@Binding var deleteNodeId: Int64
	@Binding var shareContactNode: NodeInfoEntity?

	// The initializer for the FetchRequest
	init(
		withFilters: NodeFilterParameters,
		selectedNode: Binding<NodeInfoEntity?>,
		connectedNode: NodeInfoEntity?,
		isPresentingDeleteNodeAlert: Binding<Bool>,
		deleteNodeId: Binding<Int64>,
		shareContactNode: Binding<NodeInfoEntity?>
	) {
		let request: NSFetchRequest<NodeInfoEntity> = NodeInfoEntity.fetchRequest()
		request.sortDescriptors = [
			NSSortDescriptor(key: "ignored", ascending: true),
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		]
		request.predicate = withFilters.buildPredicate()
		self._nodes = FetchRequest(fetchRequest: request)
		
		self._selectedNode = selectedNode
		self.connectedNode = connectedNode
		self._isPresentingDeleteNodeAlert = isPresentingDeleteNodeAlert
		self._deleteNodeId = deleteNodeId
		self._shareContactNode = shareContactNode
	}
	
	// The body of the view
	var body: some View {
		if #available(iOS 16, *) {
			splitList
		} else {
			legacyList
		}
	}

	@available(iOS 16, *)
	private var splitList: some View {
		List(nodes, id: \.self, selection: $selectedNode) { node in
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
	}

	private var legacyList: some View {
		List(nodes, id: \.self) { node in
			NavigationLink {
				NodeDetail(
					connectedNode: connectedNode,
					node: node
				)
				.onAppear {
					selectedNode = node
				}
				.onDisappear {
					if selectedNode == node {
						selectedNode = nil
					}
				}
			} label: {
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
