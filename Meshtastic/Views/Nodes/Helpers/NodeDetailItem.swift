/*
 Abstract:
 A view showing the details for a node.
 */

import SwiftUI
import WeatherKit
import MapKit
import CoreLocation

struct NodeDetailItem: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.colorScheme) var colorScheme: ColorScheme
	@State private var showingShutdownConfirm: Bool = false
	@State private var showingRebootConfirm: Bool = false

	@ObservedObject var node: NodeInfoEntity

	var body: some View {

		let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
		NavigationStack {
			GeometryReader { bounds in
				VStack {
					ScrollView {
						NodeInfoItem(node: node)
						VStack {
							NavigationLink {
								DeviceMetricsLog(node: node)
							} label: {
								Image(systemName: "flipphone")
									.symbolRenderingMode(.hierarchical)
									.font(.title)
								
								Text("Device Metrics Log")
									.font(.title3)
							}
							.disabled(!node.hasDeviceMetrics)
							Divider()
							NavigationLink {
								EnvironmentMetricsLog(node: node)
							} label: {
								Image(systemName: "chart.xyaxis.line")
									.symbolRenderingMode(.hierarchical)
									.font(.title)
								
								Text("Environment Metrics Log")
									.font(.title3)
							}
							.disabled(!node.hasEnvironmentMetrics)
							Divider()
							NavigationLink {
								NodeMapControl(node: node)
							} label: {
								Image(systemName: "map")
									.symbolRenderingMode(.hierarchical)
									.font(.title)
								
								Text("Node Map")
									.font(.title3)
							}
							.disabled(!node.hasPositions)
							Divider()
							NavigationLink {
								PositionLog(node: node)
							} label: {
								Image(systemName: "building.columns")
									.symbolRenderingMode(.hierarchical)
									.font(.title)
								
								Text("Position Log")
									.font(.title3)
							}
							.disabled(!node.hasPositions)
							Divider()
							NavigationLink {
								DetectionSensorLog(node: node)
							} label: {
								Image(systemName: "sensor")
									.symbolRenderingMode(.hierarchical)
									.font(.title)
								
								Text("Detection Sensor Log")
									.font(.title3)
							}
							Divider()
						}
						
						
						if self.bleManager.connectedPeripheral != nil && node.metadata != nil {
							HStack {
								if node.metadata?.canShutdown ?? false {

									Button(action: {
										showingShutdownConfirm = true
									}) {
										Label("Power Off", systemImage: "power")
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.capsule)
									.controlSize(.large)
									.padding()
									.confirmationDialog(
										"are.you.sure",
										isPresented: $showingShutdownConfirm
									) {
										Button("Shutdown Node?", role: .destructive) {
											if !bleManager.sendShutdown(fromUser: connectedNode!.user!, toUser: node.user!, adminIndex: connectedNode!.myInfo!.adminIndex) {
												print("Shutdown Failed")
											}
										}
									}
								}

								Button(action: {
									showingRebootConfirm = true
								}) {
									Label("reboot", systemImage: "arrow.triangle.2.circlepath")
								}
								.buttonStyle(.bordered)
								.buttonBorderShape(.capsule)
								.controlSize(.large)
								.padding()
								.confirmationDialog("are.you.sure",
													isPresented: $showingRebootConfirm
								) {
									Button("reboot.node", role: .destructive) {
										if !bleManager.sendReboot(fromUser: connectedNode!.user!, toUser: node.user!, adminIndex: connectedNode!.myInfo!.adminIndex) {
											print("Reboot Failed")
										}
									}
								}
							}
							.padding(5)
							Divider()
						}
					}
				}
				.onAppear {
					if self.bleManager.context == nil {
						self.bleManager.context = context
					}
				}
				.edgesIgnoringSafeArea([.leading, .trailing])
				.navigationBarTitle(String(node.user?.longName ?? "unknown".localized), displayMode: .inline)
				.navigationBarItems(trailing:
					ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
				})
			}
			.padding(.bottom, 2)
		}
	}
}
