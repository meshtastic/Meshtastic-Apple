//
//  NodeListSplit.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/8/23.
//
import SwiftUI
import CoreLocation
import OSLog

struct NodeList: View {
	@Environment(\.managedObjectContext)
	var context

	@EnvironmentObject
	var bleManager: BLEManager

	@ObservedObject
	var router: Router

	@State private var columnVisibility = NavigationSplitViewVisibility.all
	@State private var selectedNode: NodeInfoEntity?
	@State private var searchText = ""
	@State private var viaLora = true
	@State private var viaMqtt = true
	@State private var isOnline = false
	@State private var isPkiEncrypted = false
	@State private var isFavorite = false
	@State private var isIgnored = false
	@State private var isEnvironment = false
	// Force refresh ID to make SwiftUI rebuild the view hierarchy
	@State private var forceRefreshID = UUID()
	@State private var distanceFilter = false
	@State private var maxDistance: Double = 800000
	@State private var hopsAway: Double = -1.0
	@State private var roleFilter = false
	@State private var deviceRoles: Set<Int> = []
	@State private var isPresentingTraceRouteSentAlert = false
	@State private var isPresentingPositionSentAlert = false
	@State private var isPresentingPositionFailedAlert = false
	@State private var isPresentingDeleteNodeAlert = false
	@State private var deleteNodeId: Int64 = 0
    @State private var isPresentingShareContactQR = false
    @State private var shareContactNode: NodeInfoEntity?

	var boolFilters: [Bool] {[
		isFavorite,
		isIgnored,
		isOnline,
		isPkiEncrypted,
		isEnvironment,
		distanceFilter,
		roleFilter
	]}

	@State var isEditingFilters = false

	@SceneStorage("selectedDetailView") var selectedDetailView: String?

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "ignored", ascending: true),
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		],
		animation: .spring
	)
	var nodes: FetchedResults<NodeInfoEntity>

	var connectedNode: NodeInfoEntity? {
		getNodeInfo(id: bleManager.connectedPeripheral?.num ?? 0, context: context)
	}

	@ViewBuilder
	func contextMenuActions(
		node: NodeInfoEntity,
		connectedNode: NodeInfoEntity?
	) -> some View {
		/// Allow users to mute notifications for a node even if they are not connected
		if let user = node.user {
			NodeAlertsButton(context: context, node: node, user: user)
			if !user.unmessagable {
				Button(action: {
					shareContactNode = node
					isPresentingShareContactQR = true
				}) {
					Label("Share Contact QR", systemImage: "qrcode")
				}
			}
		}
		if let connectedNode {
			/// Favoriting a node requires being connected
			FavoriteNodeButton(bleManager: bleManager, context: context, node: node)
			/// Don't show message, trace route, position exchange or delete context menu items for the connected node
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
					bleManager: bleManager,
					node: node
				)
				Button {
					let positionSent = bleManager.sendPosition(
						channel: node.channel,
						destNum: node.num,
						wantResponse: true
					)
					if positionSent {
						isPresentingPositionSentAlert = true
						DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
							isPresentingPositionSentAlert = false
						}
					} else {
						isPresentingPositionFailedAlert = true
						DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
							isPresentingPositionFailedAlert = false
						}
					}
				} label: {
					Label("Exchange Positions", systemImage: "arrow.triangle.2.circlepath")
				}
				IgnoreNodeButton(
					bleManager: bleManager,
					context: context,
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

	var body: some View {
		// Use forceRefreshID to completely rebuild the view when notifications update the selected node
		NavigationSplitView(columnVisibility: $columnVisibility) {
			List(nodes, id: \.self, selection: $selectedNode) { node in
				NodeListItem(
					node: node,
					connected: bleManager.connectedPeripheral?.num ?? -1 == node.num,
					connectedNode: bleManager.connectedPeripheral?.num ?? -1
				)
				.contextMenu {
					contextMenuActions(
						node: node,
						connectedNode: connectedNode
					)
				}
			}
			.sheet(isPresented: $isEditingFilters) {
				NodeListFilter(
					viaLora: $viaLora,
					viaMqtt: $viaMqtt,
					isOnline: $isOnline,
					isPkiEncrypted: $isPkiEncrypted,
					isFavorite: $isFavorite,
					isIgnored: $isIgnored,
					isEnvironment: $isEnvironment,
					distanceFilter: $distanceFilter,
					maximumDistance: $maxDistance,
					hopsAway: $hopsAway,
					roleFilter: $roleFilter,
					deviceRoles: $deviceRoles
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
			.searchable(text: $searchText, placement: .automatic, prompt: "Find a node")
			.disableAutocorrection(true)
			.scrollDismissesKeyboard(.immediately)
			.navigationTitle(String.localizedStringWithFormat("Nodes (%@)".localized, String(nodes.count)))
			.listStyle(.plain)
			.alert(
				"Position Exchange Requested",
				isPresented: $isPresentingPositionSentAlert) {
					Button("OK") {	}.keyboardShortcut(.defaultAction)
				} message: {
				Text("Your position has been sent with a request for a response with their position. You will receive a notification when a position is returned.")
			}
			.alert(
				"Position Exchange Failed",
				isPresented: $isPresentingPositionFailedAlert) {
					Button("OK") {	}.keyboardShortcut(.defaultAction)
				} message: {
				Text("Failed to get a valid position to exchange")
			}
			.alert(
				"Trace Route Sent",
				isPresented: $isPresentingTraceRouteSentAlert) {
					Button("OK") {	}.keyboardShortcut(.defaultAction)
				} message: {
					Text("This could take a while, response will appear in the trace route log for the node it was sent to.")
			}
			.confirmationDialog(
				"Are you sure?",
				isPresented: $isPresentingDeleteNodeAlert,
				titleVisibility: .visible
			) {
				Button("Delete Node") {
					let deleteNode = getNodeInfo(id: deleteNodeId, context: context)
					if connectedNode != nil {
						if deleteNode != nil {
							let success = bleManager.removeNode(node: deleteNode!, connectedNodeNum: Int64(bleManager.connectedPeripheral?.num ?? -1))
							if !success {
								Logger.data.error("Failed to delete node \(deleteNode?.user?.longName ?? "Unknown".localized, privacy: .public)")
							}
						}
					}
				}
			 }
			.sheet(isPresented: $isPresentingShareContactQR) {
				if let node = shareContactNode {
					ShareContactQRDialog(node: node.toProto())
				} else {
					EmptyView()
				}
			}
			.navigationSplitViewColumnWidth(min: 100, ideal: 250, max: 500)
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: bleManager.connectedPeripheral?.shortName ?? "?",
						phoneOnly: true
					)
				}
				// Make sure the ZStack passes through accessibility to the ConnectedDevice component
				.accessibilityElement(children: .contain)
			)
		} content: {
			if let node = selectedNode {
				NavigationStack {
					NodeDetail(
						connectedNode: connectedNode,
						node: node,
						columnVisibility: columnVisibility
					)
					.edgesIgnoringSafeArea([.leading, .trailing])
					.navigationBarItems(
						trailing: ZStack {
							if UIDevice.current.userInterfaceIdiom != .phone {
								Button {
									columnVisibility = .detailOnly
								} label: {
									Image(systemName: "rectangle")
								}
								.accessibilityLabel("Hide sidebar")
							}
							ConnectedDevice(
								bluetoothOn: bleManager.isSwitchedOn,
								deviceConnected: bleManager.connectedPeripheral != nil,
								name: bleManager.connectedPeripheral?.shortName ?? "?",
								phoneOnly: true
							)
						}
						// Make sure the ZStack passes through accessibility to the ConnectedDevice component
						.accessibilityElement(children: .contain)
					)
				}
			 } else {
				ContentUnavailableView("Select Node", systemImage: "flipphone")
			 }
		} detail: {
			ContentUnavailableView("", systemImage: "line.3.horizontal")
		}
		.navigationSplitViewStyle(.balanced)
		.onChange(of: searchText) {
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: viaLora) {
			if !viaLora && !viaMqtt {
				viaMqtt = true
			}
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: viaMqtt) {
			if !viaLora && !viaMqtt {
				viaLora = true
			}
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: [boolFilters]) {
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: [deviceRoles]) {
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: hopsAway) {
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: maxDistance) {
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: distanceFilter) {
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: selectedNode) {
			if selectedNode === nil {
				router.navigationState.nodeListSelectedNodeNum = nil
			}
		}
		.onChange(of: router.navigationState) {
			if let selected = router.navigationState.nodeListSelectedNodeNum {
				// Force a complete view rebuild by generating a new UUID
				Logger.services.info("Forcing view rebuild with new ID: \(self.forceRefreshID)")
				// First clear selection
				self.forceRefreshID = UUID()
				self.selectedNode = nil
				// Then after a short delay, set the new selection. Makes it obvious to use page is refreshing too.
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
					// Generate another UUID to ensure view gets rebuilt
					self.forceRefreshID = UUID()
					self.selectedNode = getNodeInfo(id: selected, context: context)
					Logger.services.info("Complete view refresh with node: \(selected, privacy: .public)")
				}
			} else {
				self.selectedNode = nil
			}
		}
		.onAppear {
			// Set up notification observer for forced refreshes from notifications
			NotificationCenter.default.addObserver(forName: NSNotification.Name("ForceNavigationRefresh"), object: nil, queue: .main) { notification in
				if let nodeNum = notification.userInfo?["nodeNum"] as? Int64 {
					// Force complete refresh of view
					self.forceRefreshID = UUID()
					self.selectedNode = getNodeInfo(id: nodeNum, context: self.context)
					Logger.services.info("NodeList directly updated from notification for node: \(nodeNum, privacy: .public)")
				}
			}
			Task {
				await searchNodeList()
			}
		}
		.onDisappear {
			// Remove observer when view disappears
			NotificationCenter.default.removeObserver(self, name: NSNotification.Name("ForceNavigationRefresh"), object: nil)
		}
	}

	private func searchNodeList() async {
		/// Case Insensitive Search Text Predicates
		let searchPredicates = ["user.userId", "user.numString", "user.hwModel", "user.hwDisplayName", "user.longName", "user.shortName"].map { property in
			return NSPredicate(format: "%K CONTAINS[c] %@", property, searchText)
		}
		/// Create a compound predicate using each text search preicate as an OR
		let textSearchPredicate = NSCompoundPredicate(type: .or, subpredicates: searchPredicates)
		/// Create an array of predicates to hold our AND predicates
		var predicates: [NSPredicate] = []
		/// Mqtt
		if !(viaLora && viaMqtt) {
			if viaLora {
				let loraPredicate = NSPredicate(format: "viaMqtt == NO")
				predicates.append(loraPredicate)
			} else {
				let mqttPredicate = NSPredicate(format: "viaMqtt == YES")
				predicates.append(mqttPredicate)
			}
		}
		/// Role
		if roleFilter && deviceRoles.count > 0 {
			var rolesArray: [NSPredicate] = []
			for dr in deviceRoles {
				let deviceRolePredicate = NSPredicate(format: "user.role == %i", Int32(dr))
				rolesArray.append(deviceRolePredicate)
			}
			let compoundPredicate = NSCompoundPredicate(type: .or, subpredicates: rolesArray)
			predicates.append(compoundPredicate)
		}
		/// Hops Away
		if hopsAway == 0.0 {
			let hopsAwayPredicate = NSPredicate(format: "hopsAway == %i", Int32(hopsAway))
			predicates.append(hopsAwayPredicate)
		} else if hopsAway > -1.0 {
			let hopsAwayPredicate = NSPredicate(format: "hopsAway > 0 AND hopsAway <= %i", Int32(hopsAway))
			predicates.append(hopsAwayPredicate)
		}
		/// Online
		if isOnline {
			let isOnlinePredicate = NSPredicate(format: "lastHeard >= %@", Calendar.current.date(byAdding: .minute, value: -120, to: Date())! as NSDate)
			predicates.append(isOnlinePredicate)
		}
		/// Encrypted
		if isPkiEncrypted {
			let isPkiEncryptedPredicate = NSPredicate(format: "user.pkiEncrypted == YES")
			predicates.append(isPkiEncryptedPredicate)
		}
		/// Favorites
		if isFavorite {
			let isFavoritePredicate = NSPredicate(format: "favorite == YES")
			predicates.append(isFavoritePredicate)
		}
		/// Ignored
		if isIgnored {
			let isIgnoredPredicate = NSPredicate(format: "ignored == YES")
			predicates.append(isIgnoredPredicate)
		} else if !isIgnored {
			let isIgnoredPredicate = NSPredicate(format: "ignored == NO")
			predicates.append(isIgnoredPredicate)
		}
		/// Environment
		if isEnvironment {
			let environmentPredicate = NSPredicate(format: "SUBQUERY(telemetries, $tel, $tel.metricsType == 1).@count > 0")
			predicates.append(environmentPredicate)
		}
		/// Distance
		if distanceFilter {
			let pointOfInterest = LocationsHandler.currentLocation

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
		if predicates.count > 0 || !searchText.isEmpty {
			if !searchText.isEmpty {
				let filterPredicates = NSCompoundPredicate(type: .and, subpredicates: predicates)
				nodes.nsPredicate = NSCompoundPredicate(type: .and, subpredicates: [textSearchPredicate, filterPredicates])
			} else {
				nodes.nsPredicate = NSCompoundPredicate(type: .and, subpredicates: predicates)
			}
		} else {
			nodes.nsPredicate = nil
		}
	}
}
