//
//  NodeListSplit.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/8/23.
//
import SwiftUI
import CoreLocation
import OSLog
import CoreData

struct NodeList: View {
	@Environment(\.managedObjectContext)
	var context
	
	@EnvironmentObject var accessoryManager: AccessoryManager
	
	@StateObject var router: Router
	
	@State private var columnVisibility = NavigationSplitViewVisibility.all
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
	
	private func fetchNodes(withFilters: NodeFilterParameters) -> [NodeInfoEntity] {
		let request: NSFetchRequest<NodeInfoEntity> = NodeInfoEntity.fetchRequest()
		request.sortDescriptors = [
			NSSortDescriptor(key: "ignored", ascending: true),
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		]
		request.predicate = withFilters.buildPredicate()
		return (try? context.fetch(request)) ?? []
	}
	
	@ViewBuilder
	func contextMenuActions(
		node: NodeInfoEntity,
		connectedNode: NodeInfoEntity?
	) -> some View {
		/// Allow users to mute notifications for a node even if they are not connected
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
			/// Favoriting a node requires being connected
			FavoriteNodeButton(node: node)
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
				Button {
					Task {
						do {
							try await accessoryManager.sendPosition(
								channel: node.channel,
								destNum: node.num,
								wantResponse: true
							)
							Task { @MainActor in
								isPresentingPositionSentAlert = true
								DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
									isPresentingPositionSentAlert = false
								}
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
	
	var body: some View {
		let nodes = fetchNodes(withFilters: filters)
		NavigationSplitView(columnVisibility: $columnVisibility) {
			List(nodes, id: \.self, selection: $selectedNode) { node in
				NodeListItem(
					node: node,
					isDirectlyConnected: node.num == accessoryManager.activeDeviceNum,
					connectedNode: accessoryManager.activeConnection?.device.num ?? -1
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
			.searchable(text: $filters.searchText, placement: .automatic, prompt: "Find a node")
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
										Task {
											do {
												try await accessoryManager.removeNode(node: deleteNode!, connectedNodeNum: Int64(accessoryManager.activeDeviceNum ?? -1))
											} catch {
												Logger.data.error("Failed to delete node \(deleteNode?.user?.longName ?? "Unknown".localized, privacy: .public)")
											}
										}
									}
								}
							}
						}
						.sheet(item: $shareContactNode) { selectedNode in
							ShareContactQRDialog(node: selectedNode.toProto())
						}
						.navigationSplitViewColumnWidth(min: 100, ideal: 250, max: 500)
						.navigationBarItems(
							leading: MeshtasticLogo(),
							trailing: ZStack {
								ConnectedDevice(
									deviceConnected: accessoryManager.isConnected,
									name: accessoryManager.activeConnection?.device.shortName ?? "?",
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
							ConnectedDevice(
								deviceConnected: accessoryManager.isConnected,
								name: accessoryManager.activeConnection?.device.shortName ?? "?",
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
		.onChange(of: selectedNode) {
			if selectedNode != nil {
				columnVisibility = .doubleColumn
			} else {
				columnVisibility = .all
				router.navigationState.nodeListSelectedNodeNum = nil
			}
		}
		.onChange(of: router.navigationState) {
			if let selected = router.navigationState.nodeListSelectedNodeNum {
				// First clear selection
				self.selectedNode = nil
				// Then after a short delay, set the new selection. Makes it obvious to use page is refreshing too.
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
					self.selectedNode = getNodeInfo(id: selected, context: context)
					Logger.services.info("👷‍♂️ [App] Complete view refresh with node: \(selected, privacy: .public)")
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
					self.selectedNode = getNodeInfo(id: nodeNum, context: self.context)
					Logger.services.info("NodeList directly updated from notification for node: \(nodeNum, privacy: .public)")
				}
			}
		}
		.onDisappear {
			// Remove observer when view disappears
			NotificationCenter.default.removeObserver(self, name: NSNotification.Name("ForceNavigationRefresh"), object: nil)
		}
	}
}

fileprivate extension NodeFilterParameters {
	func buildPredicate() -> NSPredicate? {
		var predicates: [NSPredicate] = []
		
		// (same predicate logic you have, but organized in functions)
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
		
		if isFavorite {
			predicates.append(NSPredicate(format: "favorite == YES"))
		}
		
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
		
		return predicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
	}
}

