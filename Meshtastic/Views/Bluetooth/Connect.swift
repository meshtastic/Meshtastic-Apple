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
import TipKit
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
	@State var presentingSwitchPreferredPeripheral = false
	@State var selectedPeripherialId = ""

	var body: some View {
		NavigationStack {
			VStack {
				List {
					if bleManager.isSwitchedOn {
						Section(header: Text("Connected Radio").font(.title)) {
							if let connectedPeripheral = bleManager.connectedPeripheral, connectedPeripheral.peripheral.state == .connected {
								TipView(BluetoothConnectionTip(), arrowEdge: .bottom)
								VStack(alignment: .leading) {
									HStack {
										VStack(alignment: .center) {
											CircleText(text: node?.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node?.num ?? 0))), circleSize: 90)
												.padding(.trailing, 5)
											if node?.latestDeviceMetrics != nil {
												BatteryCompact(batteryLevel: node?.latestDeviceMetrics?.batteryLevel ?? 0, font: .caption, iconFont: .callout, color: .accentColor)
													.padding(.trailing, 5)
											}
										}
										.padding(.trailing)
										VStack(alignment: .leading) {
											if node != nil {
												Text(connectedPeripheral.longName.addingVariationSelectors).font(.title2)
											}
											Text("BLE Name").font(.callout)+Text(": \(bleManager.connectedPeripheral?.peripheral.name?.addingVariationSelectors ?? "Unknown".localized)")
												.font(.callout).foregroundColor(Color.gray)
											if node != nil {
												Text("Firmware Version").font(.callout)+Text(": \(node?.metadata?.firmwareVersion ?? "Unknown".localized)")
													.font(.callout).foregroundColor(Color.gray)
											}
											if bleManager.isSubscribed {
												Text("Subscribed").font(.callout)
													.foregroundColor(.green)
											} else {
												HStack {
													Image(systemName: "square.stack.3d.down.forward")
														.symbolRenderingMode(.multicolor)
														.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
														.foregroundColor(.orange)
													Text("Communicating").font(.callout)
														.foregroundColor(.orange)
												}
											}
										}
									}
								}
								.font(.caption)
								.foregroundColor(Color.gray)
								.padding([.top])
								.swipeActions {
									Button(role: .destructive) {
										if let connectedPeripheral = bleManager.connectedPeripheral,
										   connectedPeripheral.peripheral.state == .connected {
											bleManager.disconnectPeripheral(reconnect: false)
										}
									} label: {
										Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
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
											Label("Mesh Live Activity", systemImage: liveActivityStarted ? "stop" : "play")
										}
										#endif
										Text("Num: \(String(node!.num))")
										Text("Short Name: \(node?.user?.shortName ?? "?")")
										Text("Long Name: \(node?.user?.longName?.addingVariationSelectors ?? "Unknown".localized)")
										Text("BLE RSSI: \(connectedPeripheral.rssi)")

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
											Label("Set LoRa Region", systemImage: "globe.americas.fill")
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
											Text("Connecting . .")
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
											Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
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
										Text("No device connected").font(.title3)
									}
									.padding()
								}
							}
						}
						.textCase(nil)

						if !self.bleManager.isConnected {
							Section(header: Text("Available Radios").font(.title)) {
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
												if let connectedPeripheral = bleManager.connectedPeripheral, connectedPeripheral.peripheral.state == CBPeripheralState.connected {
													bleManager.disconnectPeripheral()
												}
												presentingSwitchPreferredPeripheral = true
												selectedPeripherialId = peripheral.peripheral.identifier.uuidString
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
							.confirmationDialog("Connecting to a new radio will clear all app data on the phone.", isPresented: $presentingSwitchPreferredPeripheral, titleVisibility: .visible) {
								Button("Connect to new radio?", role: .destructive) {
									UserDefaults.preferredPeripheralId = selectedPeripherialId
									UserDefaults.preferredPeripheralNum = 0
									if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == CBPeripheralState.connected {
										bleManager.disconnectPeripheral()
									}
									clearCoreDataDatabase(context: context, includeRoutes: false)
									let radio = bleManager.peripherals.first(where: { $0.peripheral.identifier.uuidString == selectedPeripherialId })
									if radio != nil {
										bleManager.connectTo(peripheral: radio!.peripheral)
									}
								}
							}
							.textCase(nil)
						}

					} else {
						Text("Bluetooth is off")
							.foregroundColor(.red)
							.font(.title)
					}
				}

				HStack(alignment: .center) {
					Spacer()
					#if targetEnvironment(macCatalyst)
					if let connectedPeripheral = bleManager.connectedPeripheral {
						Button(role: .destructive, action: {
							if connectedPeripheral.peripheral.state == CBPeripheralState.connected {
								bleManager.disconnectPeripheral(reconnect: false)
							}
						}) {
							Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
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
							Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
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
			.navigationTitle("Bluetooth")
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: bleManager.connectedPeripheral?.shortName ?? "?",
						mqttProxyConnected: bleManager.mqttProxyConnected,
						mqttTopic: bleManager.mqttManager.topic
					)
				}
			)
		}
		.sheet(isPresented: $invalidFirmwareVersion, onDismiss: didDismissSheet) {
			InvalidVersion(minimumVersion: self.bleManager.minimumVersion, version: self.bleManager.connectedVersion)
				.presentationDetents([.large])
				.presentationDragIndicator(.automatic)
		}
    	.onChange(of: self.bleManager.invalidVersion) {
			invalidFirmwareVersion = self.bleManager.invalidVersion
		}
		.onChange(of: self.bleManager.isSubscribed) { _, sub in

			if UserDefaults.preferredPeripheralId.count > 0 && sub {

				let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
				fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(bleManager.connectedPeripheral?.num ?? -1))

				do {
					node = try context.fetch(fetchNodeInfoRequest).first
					if let loRaConfig = node?.loRaConfig, loRaConfig.regionCode == RegionCodes.unset.rawValue {
						isUnsetRegion = true
					} else {
						isUnsetRegion = false
					}
				} catch {
					Logger.data.error("💥 Error fetching node info: \(error.localizedDescription, privacy: .public)")
				}
			}
		}
	}
#if !targetEnvironment(macCatalyst)
#if canImport(ActivityKit)
	func startNodeActivity() {
		liveActivityStarted = true
		// 15 Minutes Local Stats Interval
		let timerSeconds = 900
		let localStats = node?.telemetries?.filtered(using: NSPredicate(format: "metricsType == 4"))
		let mostRecent = localStats?.lastObject as? TelemetryEntity

		let activityAttributes = MeshActivityAttributes(nodeNum: Int(node?.num ?? 0), name: node?.user?.longName?.addingVariationSelectors ?? "unknown")

		let future = Date(timeIntervalSinceNow: Double(timerSeconds))
		let initialContentState = MeshActivityAttributes.ContentState(uptimeSeconds: UInt32(mostRecent?.uptimeSeconds ?? 0),
																	  channelUtilization: mostRecent?.channelUtilization ?? 0.0,
																	  airtime: mostRecent?.airUtilTx ?? 0.0,
																	  sentPackets: UInt32(mostRecent?.numPacketsTx ?? 0),
																	  receivedPackets: UInt32(mostRecent?.numPacketsRx ?? 0),
																	  badReceivedPackets: UInt32(mostRecent?.numPacketsRxBad ?? 0),
																	  dupeReceivedPackets: UInt32(mostRecent?.numRxDupe ?? 0),
																	  packetsSentRelay: UInt32(mostRecent?.numTxRelay ?? 0),
																	  packetsCanceledRelay: UInt32(mostRecent?.numTxRelayCanceled ?? 0),
																	  nodesOnline: UInt32(mostRecent?.numOnlineNodes ?? 0),
																	  totalNodes: UInt32(mostRecent?.numTotalNodes ?? 0),
																	  timerRange: Date.now...future)

		let activityContent = ActivityContent(state: initialContentState, staleDate: Calendar.current.date(byAdding: .minute, value: 15, to: Date())!)

		do {
			let myActivity = try Activity<MeshActivityAttributes>.request(attributes: activityAttributes, content: activityContent,
																		  pushType: nil)
			Logger.services.info("Requested MyActivity live activity. ID: \(myActivity.id)")
		} catch {
			Logger.services.error("Error requesting live activity: \(error.localizedDescription, privacy: .public)")
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
#endif
	func didDismissSheet() {
		bleManager.disconnectPeripheral(reconnect: false)
	}
}
