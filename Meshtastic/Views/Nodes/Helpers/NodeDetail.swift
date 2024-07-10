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

	// The node the device is currently connected to
	var connectedNode: NodeInfoEntity?
	// The node information being displayed on the detail screen
	@ObservedObject
	var node: NodeInfoEntity
	var columnVisibility = NavigationSplitViewVisibility.all
	
	var favoriteNodeAction: some View {
		let connectedNodeNum = bleManager.connectedPeripheral?.num ?? 0
		return Button {
			let success = if node.favorite {
				bleManager.removeFavoriteNode(
					node: node,
					connectedNodeNum: Int64(connectedNodeNum)
				)
			} else {
				bleManager.setFavoriteNode(
					node: node,
					connectedNodeNum: Int64(connectedNodeNum)
				)
			}
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
		} label: {
			Label {
				Text(node.favorite ? "Remove from favorites" : "Add to favorites")
			} icon: {
				Image(systemName: node.favorite ? "star.fill" : "star")
					.symbolRenderingMode(.multicolor)
			}
		}
	}

	var body: some View {
		NavigationStack {
			List {
				let connectedNode = getNodeInfo(
					id: bleManager.connectedPeripheral?.num ?? -1,
					context: context
				)

				Section("Hardware") {
					NodeInfoItem(node: node)
				}
				Section("Node") {
					HStack {
						Label {
							Text("Node Number")
						} icon: {
							Image(systemName: "number")
								.symbolRenderingMode(.hierarchical)
						}
						Spacer()
						Text(String(node.num))
					}

					HStack {
						Label {
							Text("User Id")
						} icon: {
							Image(systemName: "person")
								.symbolRenderingMode(.multicolor)
						}
						Spacer()
						Text(node.user?.userId ?? "?")
					}

					if let dm = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0")).lastObject as? TelemetryEntity, dm.uptimeSeconds > 0 {
						HStack {
							Label {
								Text("\("uptime".localized)")
							} icon: {
								Image(systemName: "checkmark.circle.fill")
									.foregroundColor(.green)
									.symbolRenderingMode(.hierarchical)
							}
							Spacer()

							let now = Date.now
							let later = now + TimeInterval(dm.uptimeSeconds)
							let uptime = (now..<later).formatted(.components(style: .narrow))
							Text(uptime)
						}
					}

					if let metadata = node.metadata {
						HStack {
							Label {
								Text("firmware.version")
							} icon: {
								Image(systemName: "memorychip")
									.symbolRenderingMode(.multicolor)
							}
							Spacer()

							Text(metadata.firmwareVersion ?? "unknown".localized)
						}
					}
				}
				if UserDefaults.environmentEnableWeatherKit || (node.telemetryConfig?.environmentMeasurementEnabled ?? false) {
					Section("Environment") {
						LocalWeatherConditions(location: node.latestPosition?.nodeLocation)
					//	NodeWeatherForecastView(location: node.latestPosition?.nodeLocation)
						IndoorAirQuality(iaq: Int(node.latestEnvironmentMetrics?.iaq ?? 0), displayMode: .gauge)
					//	if node.latestEnvironmentMetrics == nil {
							
					//	}
					}
				}
				Section("Logs") {
					// Metrics
					NavigationLink {
						DeviceMetricsLog(node: node)
					} label: {
						Label {
							Text("Device Metrics Log")
						} icon: {
							Image(systemName: "flipphone")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasDeviceMetrics)

					NavigationLink {
						if #available (iOS 17, macOS 14, *) {
							NodeMapSwiftUI(node: node, showUserLocation: connectedNode?.num ?? 0 == node.num)
						} else {
							NodeMapMapkit(node: node)
						}
					} label: {
						Label {
							Text("Node Map")
						} icon: {
							Image(systemName: "map")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasPositions)

					NavigationLink {
						PositionLog(node: node)
					} label: {
						Label {
							Text("Position Log")
						} icon: {
							Image(systemName: "mappin.and.ellipse")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasPositions)

					NavigationLink {
						EnvironmentMetricsLog(node: node)
					} label: {
						Label {
							Text("Environment Metrics Log")
						} icon: {
							Image(systemName: "cloud.sun.rain")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasEnvironmentMetrics)

					if #available(iOS 17.0, macOS 14.0, *) {
						NavigationLink {
							TraceRouteLog(node: node)
						} label: {
							Label {
								Text("Trace Route Log")
							} icon: {
								Image(systemName: "signpost.right.and.left")
									.symbolRenderingMode(.multicolor)
							}
						}
						.disabled(node.traceRoutes?.count ?? 0 == 0)
					}

					NavigationLink {
						DetectionSensorLog(node: node)
					} label: {
						Label {
							Text("Detection Sensor Log")
						} icon: {
							Image(systemName: "sensor")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasDetectionSensorMetrics)

					if node.hasPax {
						NavigationLink {
							PaxCounterLog(node: node)
						} label: {
							Label {
								Text("paxcounter.log")
							} icon: {
								Image(systemName: "figure.walk.motion")
									.symbolRenderingMode(.multicolor)
							}
						}
						.disabled(!node.hasPax)
					}
				}

				Section("Actions") {
					FavoriteNodeButton(
						bleManager: bleManager,
						context: context,
						node: node
					)

					if let user = node.user {
						NodeAlertsButton(
							context: context,
							node: node,
							user: user
						)
					}

					if let connectedPeripheral = bleManager.connectedPeripheral,
					   node.num != connectedPeripheral.num {
						ExchangePositionsButton(
							bleManager: bleManager,
							node: node
						)

						TraceRouteButton(
							bleManager: bleManager,
							node: node
						)
						
						if let connectedNode {
							if node.isStoreForwardRouter {
								ClientHistoryButton(
									bleManager: bleManager,
									connectedNode: connectedNode,
									node: node
								)
							}

							DeleteNodeButton(
								bleManager: bleManager,
								context: context,
								connectedNode: connectedNode,
								node: node
							)
						}
					}
				}

				if let metadata = node.metadata,
				   let connectedNode,
				   self.bleManager.connectedPeripheral != nil {
					Section("Administration") {
						if connectedNode.myInfo?.hasAdmin ?? false {
							Button {
								let adminMessageId = bleManager.requestDeviceMetadata(
									fromUser: connectedNode.user!,
									toUser: node.user!,
									adminIndex: connectedNode.myInfo!.adminIndex,
									context: context
								)
								if adminMessageId > 0 {
									Logger.mesh.info("Sent node metadata request from node details")
								}
							} label: {
								Label {
									Text("Refresh device metadata")
								} icon: {
									Image(systemName: "arrow.clockwise")
								}
							}
						}

						if metadata.canShutdown {
							Button {
								showingShutdownConfirm = true
							} label: {
								Label("Power Off", systemImage: "power")
							}.confirmationDialog(
								"are.you.sure",
								isPresented: $showingShutdownConfirm
							) {
								Button("Shutdown Node?", role: .destructive) {
									if !bleManager.sendShutdown(
										fromUser: connectedNode.user!,
										toUser: node.user!,
										adminIndex: connectedNode.myInfo!.adminIndex
									) {
										Logger.mesh.warning("Shutdown Failed")
									}
								}
							}
						}

						Button {
							showingRebootConfirm = true
						} label: {
							Label(
								"reboot",
								systemImage: "arrow.triangle.2.circlepath"
							)
						}.confirmationDialog(
							"are.you.sure",
							isPresented: $showingRebootConfirm
						) {
							Button("reboot.node", role: .destructive) {
								if !bleManager.sendReboot(
									fromUser: connectedNode.user!,
									toUser: node.user!,
									adminIndex: connectedNode.myInfo!.adminIndex
								) {
									Logger.mesh.warning("Reboot Failed")
								}
							}
						}
					}
				}
			}
			.listStyle(.insetGrouped)
			.onAppear {
				if self.bleManager.context == nil {
					self.bleManager.context = context
				}
			}
		}
	}
}
