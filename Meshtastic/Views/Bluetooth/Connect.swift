//
//  Connect.swift
//  Meshtastic Apple
//
//  Copyright(c) Garth Vander Houwen 8/18/21.
//

import SwiftUI
import MapKit
import CoreData
import CoreLocation
import CoreBluetooth
import OSLog
#if canImport(TipKit)
import TipKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

struct Connect: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State var node: NodeInfoEntity?
	@State var isUnsetRegion = false
	@State var invalidFirmwareVersion = false
	@State var liveActivityStarted = false
	@State var selectedPeripherialId = ""

	init () {
		let notificationCenter = UNUserNotificationCenter.current()
		notificationCenter.getNotificationSettings(completionHandler: { (settings) in
		   if settings.authorizationStatus == .notDetermined {
			   UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
				   if success {
					   Logger.services.info("Notifications are all set!")
				   } else if let error = error {
					   Logger.services.error("\(error.localizedDescription)")
				   }
			   }
		   }
		})
	}
	var body: some View {
		NavigationStack {
			VStack {
				List {
					if bleManager.isSwitchedOn {
						Section(header: Text("connected.radio").font(.title)) {
							if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == .connected {
								if #available(iOS 17.0, macOS 14.0, *) {
									TipView(BluetoothConnectionTip(), arrowEdge: .bottom)
								}
								HStack {
									VStack(alignment: .center) {
										CircleText(text: node?.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node?.num ?? 0))), circleSize: 90)
									}
									.padding(.trailing)
									VStack(alignment: .leading) {
										if let name = node?.user?.longName {
											Text(name)
												.font(.title2)
										}
										Text("ble.name").font(.callout)+Text(": \(bleManager.connectedPeripheral.peripheral.name ?? "unknown".localized)")
											.font(.callout).foregroundColor(Color.gray)
										if node != nil {
											Text("firmware.version").font(.callout)+Text(": \(node?.metadata?.firmwareVersion ?? "unknown".localized)")
												.font(.callout).foregroundColor(Color.gray)
										}
										if bleManager.isSubscribed {
											Text("subscribed").font(.callout)
												.foregroundColor(.green)
										} else {

											HStack {
												if #available(iOS 17.0, macOS 14.0, *) {
													Image(systemName: "square.stack.3d.down.forward")
														.symbolRenderingMode(.multicolor)
														.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
														.foregroundColor(.orange)
												}
												Text("communicating").font(.callout)
													.foregroundColor(.orange)
											}
										}
									}
								}
								.font(.caption)
								.foregroundColor(Color.gray)
								.padding([.top, .bottom])
								.swipeActions {
									Button(role: .destructive) {
										if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == CBPeripheralState.connected {
											bleManager.disconnectPeripheral(reconnect: false)
										}
									} label: {
										Label("disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
									}
								}
								.contextMenu {

									if node != nil {
										#if !targetEnvironment(macCatalyst)
										Button {
											if !liveActivityStarted {
											#if canImport(ActivityKit)
												Logger.services.info("Start live activity.")
												startNodeActivity()
											#endif
											} else {
												#if canImport(ActivityKit)
												Logger.services.info("Stop live activity.")
												endActivity()
											#endif
											}
										} label: {
											Label("mesh.live.activity", systemImage: liveActivityStarted ? "stop" : "play")
										}
										#endif
										Text("Num: \(String(node!.num))")
										Text("Short Name: \(node?.user?.shortName ?? "?")")
										Text("Long Name: \(node?.user?.longName ?? "unknown".localized)")
										Text("BLE RSSI: \(bleManager.connectedPeripheral.rssi)")
										Button {
											if !bleManager.sendShutdown(fromUser: node!.user!, toUser: node!.user!, adminIndex: node!.myInfo!.adminIndex) {
												Logger.mesh.error("Shutdown Failed")
											}

										} label: {
											Label("Power Off", systemImage: "power")
										}
									}
								}
								if isUnsetRegion {
									HStack {
										NavigationLink {
											LoRaConfig(node: node)
										} label: {
											Label("set.region", systemImage: "globe.americas.fill")
												.foregroundColor(.red)
												.font(.title)
										}
									}
								}
							} else {

								if bleManager.isConnecting {
									HStack {
										Image(systemName: "antenna.radiowaves.left.and.right")
											.resizable()
											.symbolRenderingMode(.hierarchical)
											.foregroundColor(.orange)
											.frame(width: 60, height: 60)
											.padding(.trailing)
										if bleManager.timeoutTimerCount == 0 {
											Text("connecting")
												.font(.title2)
												.foregroundColor(.orange)
										} else {
											VStack {

												Text("Connection Attempt \(bleManager.timeoutTimerCount) of 10")
													.font(.callout)
													.foregroundColor(.orange)
											}
										}
									}
									.padding()
									.swipeActions {
										Button(role: .destructive) {
											bleManager.cancelPeripheralConnection()
										} label: {
											Label("disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
										}
									}

								} else {

									if bleManager.lastConnectionError.count > 0 {
										Text(bleManager.lastConnectionError).font(.callout).foregroundColor(.red)
									}
									HStack {
										Image(systemName: "antenna.radiowaves.left.and.right.slash")
											.resizable()
											.symbolRenderingMode(.hierarchical)
											.foregroundColor(.red)
											.frame(width: 60, height: 60)
											.padding(.trailing)
										Text("not.connected").font(.title3)
									}
									.padding()
								}
							}
						}
						.textCase(nil)

						if !self.bleManager.isConnected {
							Section(header: Text("available.radios").font(.title)) {
								ForEach(bleManager.peripherals.filter({ $0.peripheral.state == CBPeripheralState.disconnected }).sorted(by: { $0.name < $1.name })) { peripheral in
									HStack {
										if UserDefaults.preferredPeripheralId == peripheral.peripheral.identifier.uuidString {
											Image(systemName: "star.fill")
												.imageScale(.large).foregroundColor(.yellow)
												.padding(.trailing)
										} else {
											Image(systemName: "circle.fill")
												.imageScale(.large).foregroundColor(.gray)
												.padding(.trailing)
										}
										Button(action: {
											if UserDefaults.preferredPeripheralId.count > 0 && peripheral.peripheral.identifier.uuidString != UserDefaults.preferredPeripheralId {
												if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == CBPeripheralState.connected {
													bleManager.disconnectPeripheral()
												}
												//clearCoreDataDatabase(context: context, includeRoutes: false)
												let container = NSPersistentContainer(name : "Meshtastic")
												guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
													Logger.data.error("nil File path for back")
													return
												}
												do {
													try container.copyPersistentStores(to: url.appendingPathComponent("backups").appendingPathComponent("\(UserDefaults.preferredPeripheralNum)"), overwriting: true)
				
													Logger.data.notice("🗂️ Made a core data backup to backup/\(UserDefaults.preferredPeripheralNum)")
												} catch {
													print("Copy error: \(error)")
												}
												UserDefaults.preferredPeripheralId = selectedPeripherialId
												UserDefaults.preferredPeripheralNum = 0
												let radio = bleManager.peripherals.first(where: { $0.peripheral.identifier.uuidString == selectedPeripherialId })
												if radio != nil {
													bleManager.connectTo(peripheral: radio!.peripheral)
												}
											} else {
												self.bleManager.connectTo(peripheral: peripheral.peripheral)
											}
										}) {
											Text(peripheral.name).font(.callout)
										}
										Spacer()
										VStack {
											SignalStrengthIndicator(signalStrength: peripheral.getSignalStrength())
										}
									}.padding([.bottom, .top])
								}
							}
						}

					} else {
						Text("bluetooth.off")
							.foregroundColor(.red)
							.font(.title)
					}
				}

				HStack(alignment: .center) {
					Spacer()
					#if targetEnvironment(macCatalyst)
					if bleManager.connectedPeripheral != nil {
						Button(role: .destructive, action: {
							if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == CBPeripheralState.connected {
								bleManager.disconnectPeripheral(reconnect: false)
							}
						}) {
							Label("disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
						.padding()
					}
					if bleManager.isConnecting {
						Button(role: .destructive, action: {
							bleManager.cancelPeripheralConnection()

						}) {
							Label("disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
						.padding()
					}
					#endif
					Spacer()
				}
				.padding(.bottom, 10)
			}
			.navigationTitle("bluetooth")
			.navigationBarItems(leading: MeshtasticLogo(), trailing:
									ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?", mqttProxyConnected: bleManager.mqttProxyConnected, mqttTopic: bleManager.mqttManager.topic)
			})
		}
		.sheet(isPresented: $invalidFirmwareVersion, onDismiss: didDismissSheet) {
			InvalidVersion(minimumVersion: self.bleManager.minimumVersion, version: self.bleManager.connectedVersion)
				.presentationDetents([.large])
				.presentationDragIndicator(.automatic)
		}
		.onChange(of: (self.bleManager.invalidVersion)) { _ in
			invalidFirmwareVersion = self.bleManager.invalidVersion
		}
		.onChange(of: (self.bleManager.isSubscribed)) { sub in

			if UserDefaults.preferredPeripheralId.count > 0 && sub {

				let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
				fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(bleManager.connectedPeripheral?.num ?? -1))

				do {
					guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
						return
					}
					// Found a node, check it for a region
					if let fetched = fetchedNode.first {
						node = fetched
						if fetched.loRaConfig != nil && fetched.loRaConfig?.regionCode ?? 0 == RegionCodes.unset.rawValue {
							isUnsetRegion = true
						} else {
							isUnsetRegion = false
						}
					}
				} catch {
					Logger.data.warning("Failed to fetch node for \(bleManager.connectedPeripheral?.num ?? -1)")
				}
			}
		}
		.onAppear(perform: {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
		})
	}
	#if canImport(ActivityKit)
	func startNodeActivity() {
		liveActivityStarted = true
		let timerSeconds = 60
		let deviceMetrics = node?.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0"))
		let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity

		let activityAttributes = MeshActivityAttributes(nodeNum: Int(node?.num ?? 0), name: node?.user?.longName ?? "unknown")

		let future = Date(timeIntervalSinceNow: Double(timerSeconds))

		let initialContentState = MeshActivityAttributes.ContentState(timerRange: Date.now...future, connected: true, channelUtilization: mostRecent?.channelUtilization ?? 0.0, airtime: mostRecent?.airUtilTx ?? 0.0, batteryLevel: UInt32(mostRecent?.batteryLevel ?? 0), nodes: 17, nodesOnline: 9)

		let activityContent = ActivityContent(state: initialContentState, staleDate: Calendar.current.date(byAdding: .minute, value: 2, to: Date())!)

		do {
			let myActivity = try Activity<MeshActivityAttributes>.request(attributes: activityAttributes, content: activityContent,
																		  pushType: nil)
			Logger.services.info("Requested MyActivity live activity. ID: \(myActivity.id)")
		} catch {
			Logger.services.error("Error requesting live activity: \(error.localizedDescription)")
		}
	}

	func endActivity() {
		liveActivityStarted = false
		Task {
			for activity in Activity<MeshActivityAttributes>.activities where activity.attributes.nodeNum == node?.num ?? 0 {
				await activity.end(nil, dismissalPolicy: .immediate)
			}
		}
	}
	#endif

	func didDismissSheet() {
		bleManager.disconnectPeripheral(reconnect: false)
	}
}
