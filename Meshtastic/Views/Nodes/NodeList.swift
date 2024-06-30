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

	@StateObject var appState = AppState.shared
	@State private var columnVisibility = NavigationSplitViewVisibility.all
	@State private var selectedNode: NodeInfoEntity?
	@State private var isPresentingTraceRouteSentAlert = false
	@State private var isPresentingClientHistorySentAlert = false
	@State private var isPresentingDeleteNodeAlert = false
	@State private var isPresentingPositionSentAlert = false
	@State private var deleteNodeId: Int64 = 0
	@State private var searchText = ""
	@State private var viaLora = true
	@State private var viaMqtt = true
	@State private var isOnline = false
	@State private var isFavorite = false
	@State private var distanceFilter = false
	@State private var maxDistance: Double = 800000
	@State private var hopsAway: Double = -1.0
	@State private var roleFilter = false
	@State private var deviceRoles: Set<Int> = []

	@State var isEditingFilters = false

	@SceneStorage("selectedDetailView") var selectedDetailView: String?

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "favorite", ascending: false),
						  NSSortDescriptor(key: "lastHeard", ascending: false),
						  NSSortDescriptor(key: "user.longName", ascending: true)],
		animation: .default)

	var nodes: FetchedResults<NodeInfoEntity>

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {

//			HStack {
//				Button("Open Node") {
//					UIApplication
//						.shared
//						.open(URL(string: "meshtastic://nodes?nodeNum=530606484")!)
//				}
//			}

			let connectedNodeNum = Int(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral?.num ?? 0 : 0)
			let connectedNode = nodes.first(where: { $0.num == connectedNodeNum })
			List(nodes, id: \.self, selection: $selectedNode) { node in

				NodeListItem(node: node,
							 connected: bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral?.num ?? -1 == node.num,
							 connectedNode: (bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral?.num ?? -1 : -1))
				.contextMenu {

					Button {
						if !node.favorite {

							let success = bleManager.setFavoriteNode(node: node, connectedNodeNum: Int64(connectedNodeNum))
							if success {
								node.favorite = !node.favorite
								do {
									try context.save()
								} catch {
									context.rollback()
									Logger.data.error("Save Node Favorite Error")
								}
								Logger.data.debug("Favorited a node")
							}
						} else {
							let success = bleManager.removeFavoriteNode(node: node, connectedNodeNum: Int64(connectedNodeNum))
							if success {
								node.favorite = !node.favorite
								do {
									try context.save()
								} catch {
									context.rollback()
									Logger.data.error("Save Node Favorite Error")
								}
								Logger.data.debug("Favorited a node")
							}
						}

					} label: {
						Label(node.favorite ? "Un-Favorite" : "Favorite", systemImage: node.favorite ? "star.slash.fill" : "star.fill")
					}
					if node.user != nil {
						Button {
							node.user!.mute = !node.user!.mute
							context.refresh(node, mergeChanges: true)
							do {
								try context.save()
							} catch {
								context.rollback()
								Logger.data.error("Save User Mute Error")
							}
						} label: {
							Label(node.user!.mute ? "Show Alerts" : "Hide Alerts", systemImage: node.user!.mute ? "bell" : "bell.slash")
						}
						if bleManager.connectedPeripheral != nil && node.num != connectedNodeNum {
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
								}
							} label: {
								Label("Exchange Positions", systemImage: "arrow.triangle.2.circlepath")
							}
						}
						if bleManager.connectedPeripheral != nil && connectedNodeNum != node.num {
							Button {
								let success = bleManager.sendTraceRouteRequest(destNum: node.user?.num ?? 0, wantResponse: true)
								if success {
									isPresentingTraceRouteSentAlert = true
									DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
										isPresentingTraceRouteSentAlert = false
									}
								}

							} label: {
								Label("Trace Route", systemImage: "signpost.right.and.left")
							}
							if node.isStoreForwardRouter {

								Button {
									let success = bleManager.requestStoreAndForwardClientHistory(fromUser: connectedNode!.user!, toUser: node.user!)
									if success {
										isPresentingClientHistorySentAlert = true
										DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
											isPresentingClientHistorySentAlert = false
										}
									}
								} label: {
									Label("Client History", systemImage: "envelope.arrow.triangle.branch")
								}
							}
						}
						if bleManager.connectedPeripheral != nil {
							Button(role: .destructive) {
								deleteNodeId = node.num
								isPresentingDeleteNodeAlert = true
							} label: {
								Label("Delete Node", systemImage: "trash")
							}
						}
					}
				}
				.alert(
					"Position Sent",
					isPresented: $isPresentingPositionSentAlert
				) {
					Button("OK") {	}.keyboardShortcut(.defaultAction)
				} message: {
					Text("Your position has been sent with a request for a response with their position.")
				}
				.alert(
					"Trace Route Sent",
					isPresented: $isPresentingTraceRouteSentAlert
				) {
					Button("OK") {	}.keyboardShortcut(.defaultAction)
				} message: {
					Text("This could take a while, response will appear in the trace route log for the node it was sent to.")
				}
				.alert(
					"Client History Request Sent",
					isPresented: $isPresentingClientHistorySentAlert
				) {
					Button("OK") {	}.keyboardShortcut(.defaultAction)
				} message: {
					Text("Any missed messages will be delivered again.")
				}
			}
			.sheet(isPresented: $isEditingFilters) {
				NodeListFilter(viaLora: $viaLora, viaMqtt: $viaMqtt, isOnline: $isOnline, isFavorite: $isFavorite, distanceFilter: $distanceFilter, maximumDistance: $maxDistance, hopsAway: $hopsAway, roleFilter: $roleFilter, deviceRoles: $deviceRoles)
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
			.confirmationDialog(

				"are.you.sure",
				isPresented: $isPresentingDeleteNodeAlert,
				titleVisibility: .visible
			) {
				Button("Delete Node") {
					let deleteNode = getNodeInfo(id: deleteNodeId, context: context)
					if connectedNode != nil {
						if deleteNode != nil {
							let success = bleManager.removeNode(node: deleteNode!, connectedNodeNum: Int64(connectedNodeNum))
							if !success {
								Logger.data.error("Failed to delete node \(deleteNode?.user?.longName ?? "unknown".localized)")
							}
						}
					}
				}
			}
			.navigationSplitViewColumnWidth(min: 100, ideal: 250, max: 500)
			.navigationBarItems(leading:
				MeshtasticLogo(),
				trailing:
					ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?", phoneOnly: true)
				})
		} content: {
			if let node = selectedNode {
				NavigationStack {
					NodeDetail(node: node, columnVisibility: columnVisibility)
						.edgesIgnoringSafeArea([.leading, .trailing])
						.navigationBarTitle(String(node.user?.longName ?? "unknown".localized), displayMode: .inline)
						.navigationBarItems(
							trailing:
							ZStack {
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
									name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?", phoneOnly: true)
						})
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
			searchNodeList()
		}
		.onChange(of: viaLora) { _ in
			if !viaLora && !viaMqtt {
				viaMqtt = true
			}
			searchNodeList()
		}
		.onChange(of: viaMqtt) { _ in
			if !viaLora && !viaMqtt {
				viaLora = true
			}
			searchNodeList()
		}
		.onChange(of: [deviceRoles]) { _ in
			searchNodeList()
		}
		.onChange(of: hopsAway) { _ in
			searchNodeList()
		}
		.onChange(of: isOnline) { _ in
			searchNodeList()
		}
		.onChange(of: isFavorite) { _ in
			searchNodeList()
		}
		.onChange(of: maxDistance) { _ in
			searchNodeList()
		}
		.onChange(of: distanceFilter) { _ in
			searchNodeList()
		}
		.onChange(of: (appState.navigationPath)) { newPath in

			guard let deepLink = newPath else {
				return
			}
			if deepLink.hasPrefix("meshtastic://nodes") {

				if let urlComponent = URLComponents(string: deepLink) {
					let queryItems = urlComponent.queryItems
					let nodeNum = queryItems?.first(where: { $0.name == "nodenum" })?.value
					if nodeNum == nil {
						Logger.data.debug("nodeNum not found")
					} else {
						selectedNode = nodes.first(where: { $0.num == Int64(nodeNum ?? "-1") })
						AppState.shared.navigationPath = nil
					}
				}
			}
		}
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
			searchNodeList()
		}
	}

	private func searchNodeList() {
		/// Case Insensitive Search Text Predicates
		let searchPredicates = ["user.userId", "user.numString", "user.hwModel", "user.longName", "user.shortName"].map { property in
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
		if hopsAway > -1.0 {
			if hopsAway == 0.0 {
				let hopsAwayPredicate = NSPredicate(format: "hopsAway == %i", Int32(hopsAway))
				predicates.append(hopsAwayPredicate)
			} else {
				let hopsAwayPredicate = NSPredicate(format: "hopsAway > 0 AND hopsAway <= %i", Int32(hopsAway))
				predicates.append(hopsAwayPredicate)
			}
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
