/*
 Abstract:
 A view showing the details for a node.
 */

import SwiftUI
import WeatherKit
import MapKit
import CoreLocation
import OSLog

struct NodeDetail: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var showingShutdownConfirm: Bool = false
	@State private var showingRebootConfirm: Bool = false

	@ObservedObject var node: NodeInfoEntity
	var columnVisibility = NavigationSplitViewVisibility.all

	var body: some View {

		let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
		NavigationStack {
			GeometryReader { _ in
				VStack {
					ScrollView {
						NodeInfoItem(node: node)
						let dm = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0")).lastObject as? TelemetryEntity
						if dm?.uptimeSeconds ?? 0 > 0 {
							HStack(alignment: .center) {
								let now = Date.now
								let later = now + TimeInterval(dm!.uptimeSeconds)
								let components = (now..<later).formatted(.components(style: .narrow))
								Label(
									title: {
										Text("\(NSLocalizedString("uptime", comment: "No comment provided"))")
											.font(.title3)+Text(": \(components)")
											.font(.title3)
											.foregroundColor(Color.gray)
									},
									icon: {
										Image(systemName: "checkmark.circle.fill")
											.foregroundColor(.green)
											.symbolRenderingMode(.hierarchical)
											.font(.title)
									}
								)
							}
							Divider()
						}
						if node.metadata != nil {
							HStack(alignment: .center) {
								Text("firmware.version").font(.title2)+Text(": \(node.metadata?.firmwareVersion ?? NSLocalizedString("unknown", comment: "No comment provided"))")
									.font(.title3)
									.foregroundColor(Color.gray)
								if connectedNode != nil && connectedNode?.myInfo?.hasAdmin ?? false && node.metadata?.time != nil && !Calendar.current.isDateInToday(node.metadata!.time!) {
									Button {
										let adminMessageId =  bleManager.requestDeviceMetadata(fromUser: connectedNode!.user!, toUser: node.user!, adminIndex: connectedNode!.myInfo!.adminIndex, context: context)
										if adminMessageId > 0 {
											Logger.mesh.info("Sent node metadata request from node details")
										}
									} label: {
										Image(systemName: "arrow.clockwise")
											.font(.title3)
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.capsule)
									.controlSize(.small)
								}
							}
							Divider()
						}
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
								if #available (iOS 17, macOS 14, *) {
									NodeMapSwiftUI(node: node, showUserLocation: connectedNode?.num ?? 0 == node.num)
								} else {
									NodeMapMapkit(node: node)
								}

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
								Image(systemName: "mappin.and.ellipse")
									.symbolRenderingMode(.hierarchical)
									.font(.title)

								Text("Position Log")
									.font(.title3)
							}
							.disabled(!node.hasPositions)
							Divider()
							NavigationLink {
								EnvironmentMetricsLog(node: node)
							} label: {
								Image(systemName: "cloud.sun.rain")
									.symbolRenderingMode(.hierarchical)
									.font(.title)

								Text("Environment Metrics Log")
									.font(.title3)
							}
							.disabled(!node.hasEnvironmentMetrics)
							Divider()
							if #available(iOS 17.0, macOS 14.0, *) {
								NavigationLink {
									TraceRouteLog(node: node)
								} label: {
									Image(systemName: "signpost.right.and.left")
										.symbolRenderingMode(.hierarchical)
										.font(.title)

									Text("Trace Route Log")
										.font(.title3)
								}
								.disabled(node.traceRoutes?.count ?? 0 == 0)
								Divider()
							}
							NavigationLink {
								DetectionSensorLog(node: node)
							} label: {
								Image(systemName: "sensor")
									.symbolRenderingMode(.hierarchical)
									.font(.title)

								Text("Detection Sensor Log")
									.font(.title3)
							}
							.disabled(!node.hasDetectionSensorMetrics)
							Divider()
							if node.hasPax {
								NavigationLink {
									PaxCounterLog(node: node)
								} label: {
									Image(systemName: "figure.walk.motion")
										.symbolRenderingMode(.hierarchical)
										.font(.title)

									Text("paxcounter.log")
										.font(.title3)
								}
								.disabled(!node.hasPax)
								Divider()
							}
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
												Logger.mesh.warning("Shutdown Failed")
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
											Logger.mesh.warning("Reboot Failed")
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
			}
			.padding(.bottom, 2)
		}
	}
}
