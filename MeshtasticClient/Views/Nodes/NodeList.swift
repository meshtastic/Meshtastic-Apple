//
//  NodeList.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/7/21.
//

// Abstract:
//  A view showing a list of devices that have been seen on the mesh network from the perspective of the connected device.

import SwiftUI

struct NodeList: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "lastHeard", ascending: false)],
		animation: .default)

		private var nodes: FetchedResults<NodeInfoEntity>

	@State private var selection: String?

    var body: some View {

        NavigationView {

            List {

				if nodes.count == 0 {

                    Text("Scan for Radios").font(.largeTitle)
                    Text("No LoRa Mesh Nodes Found").font(.title2)
                    Text("Go to the bluetooth section in the bottom right menu and click the Start Scanning button to scan for nearby radios and find your Meshtastic device. Make sure your device is powered on and near your phone or tablet.")
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
										Text(node.user?.longName ?? "Unknown").font(.title).offset(x: -15)
									}
								}
								.padding(.bottom, 10)

								if connected {
									HStack(alignment: .bottom) {

										Image(systemName: "repeat.circle.fill").font(.title3)
											.foregroundColor(.accentColor).symbolRenderingMode(.hierarchical)
										Text("Currently Connected").font(.title3).foregroundColor(Color.accentColor)
									}
									Spacer()
								}

								HStack(alignment: .bottom) {

									Image(systemName: "clock.badge.checkmark.fill").font(.title3).foregroundColor(.accentColor).symbolRenderingMode(.hierarchical)

									if node.lastHeard != nil {
										Text("Last Heard: \(node.lastHeard!, style: .relative) ago").font(.subheadline).foregroundColor(.gray)
									} else {
										Text("Last Heard: Unknown").font(.subheadline).foregroundColor(.gray)
									}
								}
							}
							.padding([.leading, .top, .bottom])
						}
						.swipeActions {

						   Button {

							   context.delete(node)

							   do {

								   try context.save()
								   print("Successfully Deleted NodeInfoEntiy: \(node.num)")

							   } catch {

								   print("Failed to save context after deleting NodeInfoEntity Num: \(node.num)")
							   }

						   } label: {

							   Label("Delete from app", systemImage: "trash")
						   }
						   .tint(.red)
					   }
					}
                }
             }
            .navigationTitle("All Nodes")
			.onAppear {
				// self.nodes.returnsObjectsAsFaults = false
				self.bleManager.context = context

				if UIDevice.current.userInterfaceIdiom == .pad {
					if nodes.count > 0 {
						selection = "0"
					}
				}
			}
        }
        .ignoresSafeArea(.all, edges: [.leading, .trailing])
		.navigationViewStyle(DoubleColumnNavigationViewStyle())
    }
}
