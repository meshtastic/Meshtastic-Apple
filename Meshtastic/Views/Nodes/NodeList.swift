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
	@State private var isFavorite = false
	@State private var isEnvironment = false
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

	var boolFilters: [Bool] {[
		isOnline,
		isFavorite,
		isEnvironment,
		distanceFilter,
		roleFilter
	]}

	@State var isEditingFilters = false

	@SceneStorage("selectedDetailView") var selectedDetailView: String?

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		],
		animation: .spring
	)
	var nodes: FetchedResults<NodeInfoEntity>

	var connectedNode: NodeInfoEntity? {
		getNodeInfo(
			id: bleManager.connectedPeripheral?.num ?? 0,
			context: context
		)
	}

	@ViewBuilder
	func contextMenuActions(
		node: NodeInfoEntity,
		connectedNode: NodeInfoEntity?
	) -> some View {
		/// Allow users to mute notifications for a node even if they are not connected
		if let user = node.user {
			NodeAlertsButton(
				context: context,
				node: node,
				user: user
			)
		}
		if let connectedNode {
			/// Favoriting a node requires being connected
			FavoriteNodeButton(
				bleManager: bleManager,
				context: context,
				node: node
			)
			/// Don't show trace route, position exchange or delete context menu items for the connected node
			if connectedNode.num != node.num {
				Button {
					let traceRouteSent = bleManager.sendTraceRouteRequest(
						destNum: node.num,
						wantResponse: true
					)
					if traceRouteSent {
						isPresentingTraceRouteSentAlert = true
						DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
							isPresentingTraceRouteSentAlert = false
						}
					}

				} label: {
					Label("Trace Route", systemImage: "signpost.right.and.left")
				}
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
					isFavorite: $isFavorite,
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
			.padding(.bottom, 5)
			.searchable(text: $searchText, placement: .automatic, prompt: "Find a node")
			.disableAutocorrection(true)
			.scrollDismissesKeyboard(.immediately)
			.navigationTitle(String.localizedStringWithFormat("nodes %@".localized, String(nodes.count)))
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
				"are.you.sure",
				isPresented: $isPresentingDeleteNodeAlert,
				titleVisibility: .visible
			) {
				Button("Delete Node") {
					let deleteNode = getNodeInfo(id: deleteNodeId, context: context)
					if connectedNode != nil {
						if deleteNode != nil {
							let success = bleManager.removeNode(node: deleteNode!, connectedNodeNum: Int64(bleManager.connectedPeripheral?.num ?? -1))
							if !success {
								Logger.data.error("Failed to delete node \(deleteNode?.user?.longName ?? "unknown".localized)")
							}
						}
					}
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
					.navigationBarTitle(String(node.user?.longName ?? "unknown".localized), displayMode: .inline)
					.navigationBarItems(
						trailing: ZStack {
							if UIDevice.current.userInterfaceIdiom != .phone {
								Button {
									columnVisibility = .detailOnly
								} label: {
									Image(systemName: "rectangle")
								}
							}
							ConnectedDevice(
								bluetoothOn: bleManager.isSwitchedOn,
								deviceConnected: bleManager.connectedPeripheral != nil,
								name: bleManager.connectedPeripheral?.shortName ?? "?",
								phoneOnly: true
							)
						}
					)
				}
			 } else {
				 if #available (iOS 17, *) {
					 ContentUnavailableView("select.node", systemImage: "flipphone")
				 } else {
					 Text("select.node")
				 }
			 }
		} detail: {
			if #available (iOS 17, *) {
				ContentUnavailableView("", systemImage: "line.3.horizontal")
			} else {
				Text("Select something to view")
			}
		}
		.navigationSplitViewStyle(.balanced)
		.onChange(of: searchText) { _ in
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: viaLora) { _ in
			if !viaLora && !viaMqtt {
				viaMqtt = true
			}
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: viaMqtt) { _ in
			if !viaLora && !viaMqtt {
				viaLora = true
			}
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: boolFilters) { _ in
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: [deviceRoles]) { _ in
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: hopsAway) { _ in
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: maxDistance) { _ in
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: distanceFilter) { _ in
			Task {
				await searchNodeList()
			}
		}
		.onChange(of: router.navigationState) { _ in
			// Handle deep link routing
			if case .nodes(let selected) = router.navigationState {
				self.selectedNode = selected.flatMap {
					getNodeInfo(id: $0, context: context)
				}
			} else {
				self.selectedNode = nil
			}
		}
		.onAppear {
			Task {
				await searchNodeList()
			}
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
			let isOnlinePredicate = NSPredicate(format: "lastHeard >= %@", Calendar.current.date(byAdding: .minute, value: -15, to: Date())! as NSDate)
			predicates.append(isOnlinePredicate)
		}
		/// Favorites
		if isFavorite {
			let isFavoritePredicate = NSPredicate(format: "favorite == YES")
			predicates.append(isFavoritePredicate)
		}
		/// Environment
		if isEnvironment {
			let environmentPredicate = NSPredicate(format: "SUBQUERY(telemetries, $tel, $tel.metricsType == 1).@count > 0")
			predicates.append(environmentPredicate)
		}
		/// Distance
		if distanceFilter {
			let pointOfInterest = LocationHelper.currentLocation

			if pointOfInterest.latitude != LocationHelper.DefaultLocation.latitude && pointOfInterest.longitude != LocationHelper.DefaultLocation.longitude {
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
