//
//  NodeListSplit.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/8/23.
//
import SwiftUI
import CoreLocation

struct NodeList: View {
	
	@State private var columnVisibility = NavigationSplitViewVisibility.all
	@State private var selectedNode: NodeInfoEntity?
	
	@SceneStorage("selectedDetailView") var selectedDetailView: String?
	
	@State private var searchText = ""
	var nodesQuery: Binding<String> {
		 Binding {
			 searchText
		 } set: { newValue in
			 searchText = newValue
			 nodes.nsPredicate = newValue.isEmpty ? nil : NSPredicate(format: "user.longName CONTAINS[c] %@ OR user.shortName CONTAINS[c] %@", newValue, newValue)
		 }
	 }

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "user.vip", ascending: false), NSSortDescriptor(key: "lastHeard", ascending: false)],
		animation: .default)

	var nodes: FetchedResults<NodeInfoEntity>
	


	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			
			let connectedNodeNum = Int(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral?.num ?? 0 : 0)
			let connectedNode = nodes.first(where: { $0.num == connectedNodeNum })
			List(nodes, id: \.self, selection: $selectedNode) { node in
				
				NodeListItem(node: node, 
							 connected: bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral?.num ?? -1 == node.num,
							 connectedNode: (bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral?.num ?? -1 : -1),
							 modemPreset: Int(connectedNode?.loRaConfig?.modemPreset ?? 0))
				.contextMenu {
					if node.user != nil {
						Button {
							node.user!.vip = !node.user!.vip
							context.refresh(node, mergeChanges: true)
							do {
								try context.save()
							} catch {
								context.rollback()
								print("💥 Save User VIP Error")
							}
						} label: {
							Label(node.user?.vip ?? false ? "Un-Favorite" : "Favorite", systemImage: node.user?.vip ?? false ? "star.slash.fill" : "star.fill")
						}
						Button {
							node.user!.mute = !node.user!.mute
							context.refresh(node, mergeChanges: true)
							do {
								try context.save()
							} catch {
								context.rollback()
								print("💥 Save User Mute Error")
							}
						} label: {
							Label(node.user!.mute ? "Show Alerts" : "Hide Alerts", systemImage: node.user!.mute ? "bell" : "bell.slash")
						}
					}
					
				}
			}
			.searchable(text: nodesQuery, prompt: "Find a node")
			.navigationTitle(String.localizedStringWithFormat("nodes %@".localized, String(nodes.count)))
			.listStyle(.plain)
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
								if (UIDevice.current.userInterfaceIdiom != .phone) {
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
				.padding(.bottom, 5)
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
//		.onChange(of: selectedNode) { _ in
//			if selectedNode == nil {
//				columnVisibility = .all
//			} else {
//				columnVisibility = .doubleColumn
//			}
//		}
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
		}

//		} detail: {
//			VStack {
//				Button("Detail Only") {
//					columnVisibility = .detailOnly
//				}
//
//				Button("Content and Detail") {
//					columnVisibility = .doubleColumn
//				}
//
//				Button("Show All") {
//					columnVisibility = .all
//				}
//			}
//		}
	}
}
