//
//  NodeList.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 8/7/21.
//

// Abstract:
//  A view showing a list of devices that have been seen on the mesh network from the perspective of the connected device.

import SwiftUI
import CoreLocation

struct NodeList: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
	
	@State var initialLoad: Bool = true

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "user.shortName", ascending: true)],
		animation: .default)

	private var nodes: FetchedResults<NodeInfoEntity>

	@State private var selection: String? = ""

    var body: some View {

        NavigationView {

            List {

				if nodes.count == 0 {

                    Text("Scan for Radios").font(.largeTitle)
                    Text("No Meshtastic Nodes Found").font(.title2)
                    Text("Go to the bluetooth section in the bottom right menu and click the Start Scanning button to scan for nearby radios and find your Meshtastic device. Make sure your device is powered on and near your iPhone, iPad or Mac.")
                        .font(.body)
                    Text("Once the device shows under Available Devices touch the device you want to connect to and it will pull node information over BLE and populate the node list and mesh map in the Meshtastic app.")
                    Text("Views with bluetooth functionality will show an indicator in the upper right hand corner show if bluetooth is on, and if a device is connected.")
						.listRowSeparator(.visible)

                } else {
					ForEach( nodes ) { node in

						let index = nodes.firstIndex(where: { $0.id == node.id })

						NavigationLink(destination: NodeDetail(node: node), tag: String(index!), selection: $selection) {

							let connected: Bool = (bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.num == node.num)

							VStack(alignment: .leading) {

								HStack {

									CircleText(text: node.user?.shortName ?? "???", color: Color.accentColor).offset(y: 1).padding(.trailing, 5)
										.offset(x: -15)

									if UIDevice.current.userInterfaceIdiom == .pad { Text(node.user?.longName ?? "Unknown").font(.headline)
											.offset(x: -15)
									} else {
										Text(node.user?.longName ?? "Unknown").font(.title2).offset(x: -15)
									}
								}
								.padding(.bottom, 5)

								if connected {
									
									HStack(alignment: .bottom) {

										Image(systemName: "repeat.circle.fill").font(.title2)
											.foregroundColor(.accentColor).symbolRenderingMode(.hierarchical)
										if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
											
											Text("Currently Connected").font(.callout).foregroundColor(Color.accentColor)
										} else {
											
											Text("Currently Connected").font(.title3).foregroundColor(Color.accentColor)
										}
									}
									.padding(.bottom, 2)
								}
								if node.positions?.count ?? 0 > 0 && (bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.num != node.num) {
								
									HStack(alignment: .bottom) {
									
										let lastPostion = node.positions!.reversed()[0] as! PositionEntity
										
										let myCoord = CLLocation(latitude: LocationHelper.currentLocation.latitude, longitude: LocationHelper.currentLocation.longitude)
										
										if lastPostion.coordinate != nil {
									
											let nodeCoord = CLLocation(latitude: lastPostion.coordinate!.latitude, longitude: lastPostion.coordinate!.longitude)
											
											let metersAway = nodeCoord.distance(from: myCoord)
											
											Image(systemName: "lines.measurement.horizontal").font(.title3)
												.foregroundColor(.accentColor).symbolRenderingMode(.hierarchical)
											
											if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
												
												DistanceText(meters: metersAway).font(.subheadline).foregroundColor(.gray)
												
											} else {
												
												DistanceText(meters: metersAway).font(.title3).foregroundColor(.gray)
											}
										}
									}
									.padding(.bottom, 2)
									
								}
								HStack(alignment: .bottom) {

									Image(systemName: "clock.badge.checkmark.fill").font(.headline)
										.foregroundColor(.accentColor).symbolRenderingMode(.hierarchical)
				
									LastHeardText(lastHeard: node.lastHeard).font(.subheadline).foregroundColor(.gray)
								}
							}
							.padding([.leading, .top, .bottom])
						}
					}
                }
             }
            .navigationTitle("All Nodes")
			.onAppear {

				if initialLoad {
					
					self.bleManager.userSettings = userSettings
					self.bleManager.context = context
					self.initialLoad = false
				}
			}
        }
        .ignoresSafeArea(.all, edges: [.leading, .trailing])
		.navigationViewStyle(DoubleColumnNavigationViewStyle())
    }
}
