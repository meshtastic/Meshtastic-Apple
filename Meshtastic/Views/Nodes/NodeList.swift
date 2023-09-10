//
//  NodeListSplit.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/8/23.
//
import SwiftUI
import CoreLocation

enum SelectedDetail {
	case positionLog
	case nodeMap
	case deviceMetricsLog
	case environmentMetricsLog
	case detectionSensorLog
}



struct NodeList: View {
	
	@State private var columnVisibility = NavigationSplitViewVisibility.all
	@State private var selectedNode: NodeInfoEntity?
	@State private var selectedDetail: SelectedDetail?
	
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
		sortDescriptors: [NSSortDescriptor(key: "lastHeard", ascending: false)],
		animation: .default)

	private var nodes: FetchedResults<NodeInfoEntity>
	


	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			
			let connectedNodeNum = Int(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral?.num ?? 0 : 0)
			let connectedNode = nodes.first(where: { $0.num == connectedNodeNum })
			List(nodes, id: \.self, selection: $selectedNode) { node in
				
				NodeListItem(node: node, connected: bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral?.num ?? -1 == node.num, connectedNode: (bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral?.num ?? -1 : -1), modemPreset: Int(connectedNode?.loRaConfig?.modemPreset ?? 0))
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
				NodeDetail(node: node)
					
			 } else {
				 Text("select.node")
			 }
		
		} detail: {
			Text("Select something to view")
		}
		.navigationSplitViewStyle(.balanced)
		.onChange(of: selectedNode) { _ in
			selectedDetail = nil
		}
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
