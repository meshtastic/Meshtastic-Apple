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
#if canImport(ActivityKit)
import ActivityKit
#endif

struct Connect: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
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
						Section(header: Text("connected.radio").font(.title)) {
							if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == .connected {
								HStack {
									Image(systemName: "antenna.radiowaves.left.and.right")
										.resizable()
										.symbolRenderingMode(.hierarchical)
										.foregroundColor(.green)
										.frame(width: 60, height: 60)
										.padding(.trailing)
									VStack(alignment: .leading) {
										if node != nil {
											Text(bleManager.connectedPeripheral.longName).font(.title2)
										}
										Text("ble.name").font(.callout)+Text(": \(bleManager.connectedPeripheral.peripheral.name ?? NSLocalizedString("unknown", comment: "Unknown"))")
											.font(.callout).foregroundColor(Color.gray)
										if node != nil {
											Text("firmware.version").font(.callout)+Text(": \(node?.myInfo?.firmwareVersion ?? NSLocalizedString("unknown", comment: "Unknown"))")
												.font(.callout).foregroundColor(Color.gray)
										}
										if bleManager.isSubscribed {
											Text("subscribed").font(.callout)
												.foregroundColor(.green)
										} else {
											Text("communicating").font(.callout)
												.foregroundColor(.orange)
										}
									}
								}
								.font(.caption).foregroundColor(Color.gray)
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
										if #available(iOS 16.2, *) {
											Button {
												if !liveActivityStarted {
												#if canImport(ActivityKit)
													print("Start live activity.")
													startNodeActivity()
												#endif
												} else {
													#if canImport(ActivityKit)
													print("Stop live activity.")
													endActivity()
												#endif
												}
											} label: {
												Label("Mesh Live Activity", systemImage: liveActivityStarted ? "stop" : "play")
											}
										}
										#endif
										Text("Num: \(String(node!.num))")
										Text("Short Name: \(node?.user?.shortName ?? "????")")
										Text("Long Name: \(node?.user?.longName ?? NSLocalizedString("unknown", comment: "Unknown"))")
										Text("Max Channels: \(String(node?.myInfo?.maxChannels ?? 0))")
										Text("Bitrate: \(String(format: "%.2f", node?.myInfo?.bitrate ?? 0.00))")
										Text("BLE RSSI: \(bleManager.connectedPeripheral.rssi)")
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
								ForEach(bleManager.peripherals.filter({ $0.peripheral.state == CBPeripheralState.disconnected }).sorted(by: { $0.name > $1.name })) { peripheral in
									HStack {
										Image(systemName: "circle.fill")
											.imageScale(.large).foregroundColor(.gray)
											.padding(.trailing)
										Button(action: {
											if userSettings.preferredPeripheralId.count > 0 && peripheral.peripheral.identifier.uuidString != userSettings.preferredPeripheralId {
												presentingSwitchPreferredPeripheral = true
												selectedPeripherialId = peripheral.peripheral.identifier.uuidString
											} else {
												self.bleManager.connectTo(peripheral: peripheral.peripheral)
											}
										}) {
											Text(peripheral.name).font(.title3)
										}
										Spacer()
										VStack {
											SignalStrengthIndicator(signalStrength: peripheral.getSignalStrength())
										}
									}.padding([.bottom, .top])
								}
							}
							.confirmationDialog("Connecting to a new radio will clear all local app data on the phone.", isPresented: $presentingSwitchPreferredPeripheral, titleVisibility: .visible) {

								Button("Connect to new radio?", role: .destructive) {
									bleManager.stopScanning()
									bleManager.connectedPeripheral = nil
									userSettings.preferredPeripheralId = ""
									if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == CBPeripheralState.connected {
										bleManager.disconnectPeripheral()
									}

									clearCoreDataDatabase(context: context)
									let radio = bleManager.peripherals.first(where: { $0.peripheral.identifier.uuidString == selectedPeripherialId})
									bleManager.connectTo(peripheral: radio!.peripheral)
									presentingSwitchPreferredPeripheral = false
									selectedPeripherialId = ""
								}
							}
							.textCase(nil)
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
					#endif
					Spacer()
				}
				.padding(.bottom, 10)
			}
			.navigationTitle("bluetooth")
			.navigationBarItems(leading: MeshtasticLogo(), trailing:
									ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
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

			if userSettings.preferredPeripheralId.count > 0 && sub {

				let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
				fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(bleManager.connectedPeripheral?.num ?? -1))

				do {

					let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
					// Found a node, check it for a region
					if !fetchedNode.isEmpty {
						node = fetchedNode[0]
						if node!.loRaConfig != nil && node!.loRaConfig?.regionCode ?? 0 == RegionCodes.unset.rawValue {
							isUnsetRegion = true
						} else {
							isUnsetRegion = false
						}
					}
				} catch {

				}
			}
		}
		.onAppear(perform: {
			self.bleManager.context = context
			self.bleManager.userSettings = userSettings

			// Ask for notification permission
			UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
				if success {
					print("Notifications are all set!")
				} else if let error = error {
					print(error.localizedDescription)
				}
			}
		})
	}
#if canImport(ActivityKit)
	func startNodeActivity() {
		if #available(iOS 16.2, *) {
			liveActivityStarted = true
			let timerSeconds = 60

			let mostRecent = node?.telemetries?.lastObject as! TelemetryEntity

			let activityAttributes = MeshActivityAttributes(nodeNum: Int(node?.num ?? 0), name: node?.user?.longName ?? "unknown")

			let future = Date(timeIntervalSinceNow: Double(timerSeconds))

			let initialContentState = MeshActivityAttributes.ContentState(timerRange: Date.now...future, connected: true, channelUtilization: mostRecent.channelUtilization, airtime: mostRecent.airUtilTx, batteryLevel: UInt32(mostRecent.batteryLevel))

			let activityContent = ActivityContent(state: initialContentState, staleDate: Calendar.current.date(byAdding: .minute, value: 2, to: Date())!)

			do {
				let myActivity = try Activity<MeshActivityAttributes>.request(attributes: activityAttributes, content: activityContent,
																			  pushType: nil)
				print(" Requested MyActivity live activity. ID: \(myActivity.id)")
			} catch let error {
				print("Error requesting live activity: \(error.localizedDescription)")
			}
		}
	}

	func endActivity() {
		liveActivityStarted = false
		Task {
			if #available(iOS 16.2, *) {
				for activity in Activity<MeshActivityAttributes>.activities {
					// Check if this is the activity associated with this order.
					if activity.attributes.nodeNum == node?.num ?? 0 {
						await activity.end(nil, dismissalPolicy: .immediate)
					}
				}
			}
		}
	}
#endif

#if os(iOS)
	func postNotification() {
		let timerSeconds = 60
		let content = UNMutableNotificationContent()
		content.title = "Mesh Live Activity Over"
		content.body = "Your timed mesh live activity is over."
		let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(timerSeconds), repeats: false)
		let uuidString = UUID().uuidString
		let request = UNNotificationRequest(identifier: uuidString,
											content: content, trigger: trigger)
		let notificationCenter = UNUserNotificationCenter.current()
		notificationCenter.add(request) { (error) in
			if error != nil {
				// Handle any errors.
				print("Error posting local notification: \(error?.localizedDescription ?? "no description")")
			} else {
				print("Posted local notification.")
			}
		}
	}
#endif

	func didDismissSheet() {
		bleManager.disconnectPeripheral(reconnect: false)
	}
}
