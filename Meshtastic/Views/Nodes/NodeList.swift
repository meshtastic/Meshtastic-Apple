//
//  NodeList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/7/21.
//

// Abstract:
//  A view showing a list of devices that have been seen on the mesh network from the perspective of the connected device.

import SwiftUI
import CoreLocation

struct NodeList: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "lastHeard", ascending: false)],
		animation: .default)

	private var nodes: FetchedResults<NodeInfoEntity>

	@State private var selection: NodeInfoEntity? = nil // Nothing selected by default.

    var body: some View {
		
		NavigationSplitView {
			List (nodes, id: \.self, selection: $selection) { node in
				if nodes.count == 0 {
					Text("no.nodes").font(.title)
				} else {
					NavigationLink(value: node) {
						let connected: Bool = (bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.num == node.num)
						VStack(alignment: .leading) {
							HStack {
								CircleText(text: node.user?.shortName ?? "???", color: .accentColor, circleSize: 52, fontSize: 16, brightness: 0.1)
									.padding(.trailing, 5)
								VStack(alignment: .leading) {
									Text(node.user?.longName ?? NSLocalizedString("unknown", comment: "Unknown")).font(.headline)
									if connected {
										HStack(alignment: .bottom) {
											Image(systemName: "repeat.circle.fill")
												.font(.title3)
												.symbolRenderingMode(.hierarchical)
											Text("connected").font(.subheadline)
												.foregroundColor(.green)
										}
									}
									if node.positions?.count ?? 0 > 0 && (bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.num != node.num) {
										HStack(alignment: .bottom) {
											let lastPostion = node.positions!.reversed()[0] as! PositionEntity
											let myCoord = CLLocation(latitude: LocationHelper.currentLocation.latitude, longitude: LocationHelper.currentLocation.longitude)
											if lastPostion.nodeCoordinate != nil && myCoord.coordinate.longitude != LocationHelper.DefaultLocation.longitude && myCoord.coordinate.latitude != LocationHelper.DefaultLocation.latitude   {
												let nodeCoord = CLLocation(latitude: lastPostion.nodeCoordinate!.latitude, longitude: lastPostion.nodeCoordinate!.longitude)
												let metersAway = nodeCoord.distance(from: myCoord)
												Image(systemName: "lines.measurement.horizontal")
													.font(.title3)
													.symbolRenderingMode(.hierarchical)
												
												DistanceText(meters: metersAway).font(.subheadline)
											}
										}
									}
									HStack(alignment: .bottom) {
										Image(systemName: "clock.badge.checkmark.fill")
											.font(.title3)
											.symbolRenderingMode(.hierarchical)
										LastHeardText(lastHeard: node.lastHeard)
											.font(.subheadline)
									}
								}
								.frame(maxWidth: .infinity, alignment: .leading)
							}
						}
					}
					.padding([.top, .bottom])
				}
			 }
			.navigationTitle("nodes")
			.navigationBarItems(leading:
				MeshtasticLogo()
			)
			.onAppear {
				self.bleManager.userSettings = userSettings
				self.bleManager.context = context
			}
	   } detail: {
		   if let node = selection {
			   NodeDetail(node:node)
		   } else {
			   Text("select.node")
		   }
	   }
	}
}
