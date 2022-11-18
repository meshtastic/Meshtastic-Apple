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

struct Connect: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
	@State var node: NodeInfoEntity? = nil
	
	@State var isPreferredRadio: Bool = false
	@State var isUnsetRegion = false
	@State var invalidFirmwareVersion = false

    var body: some View {
	
		NavigationStack {
            VStack {
				List {
					if bleManager.isSwitchedOn {
					Section(header: Text("Connected Radio").font(.title)) {
						if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == .connected {
							HStack {
								Image(systemName: "antenna.radiowaves.left.and.right")
									.symbolRenderingMode(.hierarchical)
									.imageScale(.large).foregroundColor(.green)
									.padding(.trailing)
								VStack(alignment: .leading) {
									if node != nil {
										Text(bleManager.connectedPeripheral.longName).font(.title2)
									}
									Text("BLE Name: ").font(.caption)+Text(bleManager.connectedPeripheral.peripheral.name ?? "Unknown")
										.font(.caption).foregroundColor(Color.gray)
									if node != nil {
										Text("FW Version: ").font(.caption)+Text(node?.myInfo?.firmwareVersion ?? "Unknown")
											.font(.caption).foregroundColor(Color.gray)
									}
									if bleManager.isSubscribed {
										Text("Subscribed to mesh").font(.caption)
											.foregroundColor(.green)
									} else {
										Text("Communicating with device. . . ").font(.caption)
											.foregroundColor(.orange)
									}
								}
								Spacer()
								VStack(alignment: .center) {
									Text("Preferred").font(.caption2)
									Text("Radio").font(.caption2)
									Toggle("Preferred Radio", isOn: $bleManager.preferredPeripheral)
										.toggleStyle(SwitchToggleStyle(tint: .accentColor))
										.labelsHidden()
										.onChange(of: bleManager.preferredPeripheral) { value in
											if value {
												if bleManager.connectedPeripheral != nil {
													userSettings.preferredPeripheralId = bleManager.connectedPeripheral!.peripheral.identifier.uuidString
													userSettings.preferredNodeNum = bleManager.connectedPeripheral!.num
													bleManager.preferredPeripheral = true
													isPreferredRadio = true
												}
											} else {

											if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.identifier.uuidString == userSettings.preferredPeripheralId {

												userSettings.preferredPeripheralId = ""
												userSettings.preferredNodeNum = 0
												bleManager.preferredPeripheral = false
												isPreferredRadio = false
											}
										}
									}
								}
							}
							.font(.caption).foregroundColor(Color.gray)
							.padding([.top, .bottom])
							.swipeActions {

								Button(role: .destructive) {
									if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == CBPeripheralState.connected {
										bleManager.disconnectPeripheral()
										isPreferredRadio = false
									}
								} label: {
									Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
								}
							}
							.contextMenu{
								
								if node != nil {
									
									Text("Num: \(String(node!.num))")
									Text("Short Name: \(node?.user?.shortName ?? "????")")
									Text("Long Name: \(node?.user?.longName ?? "Unknown")")
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
										.symbolRenderingMode(.hierarchical)
										.imageScale(.large).foregroundColor(.orange)
										.padding(.trailing)
									if bleManager.timeoutTimerCount == 0 {
										Text("Connecting . . .")
											.font(.title3)
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
										.symbolRenderingMode(.hierarchical)
										.imageScale(.large).foregroundColor(.red)
										.padding(.trailing)
									Text("No device connected").font(.title3)
								}
								.padding()
							}
						}
					}
					.textCase(nil)

					if self.bleManager.isScanning {
						Section(header: Text("Available Radios").font(.title)) {
							ForEach(bleManager.peripherals.filter({ $0.peripheral.state == CBPeripheralState.disconnected }).sorted(by: { $0.rssi > $1.rssi })) { peripheral in
								HStack {
									Image(systemName: "circle.fill")
										.imageScale(.large).foregroundColor(.gray)
										.padding(.trailing)
									Button(action: {
										self.bleManager.stopScanning()
										if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == CBPeripheralState.connected {

											self.bleManager.disconnectPeripheral()
										}
										self.bleManager.connectTo(peripheral: peripheral.peripheral)
										if userSettings.preferredPeripheralId == peripheral.peripheral.identifier.uuidString {

											isPreferredRadio = true
										} else {

											isPreferredRadio = false
										}
									}) {
										Text(peripheral.name).font(.title3)
									}
									Spacer()
									Text(String(peripheral.rssi) + " dB").font(.title3)
								}.padding([.bottom, .top])
							}
						}.textCase(nil)
					}
						
					} else {
						Text("Bluetooth: OFF")
							.foregroundColor(.red)
							.font(.title)
					}
				}

				HStack(alignment: .center) {
						
					Spacer()
						
					if !bleManager.isScanning {
						
						Button(action: {
							
							self.bleManager.startScanning()
							
						}) {
							
							Label("Start Scanning", systemImage: "play.fill")

						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
						.padding()
						
					} else {

						Button(action: {
							
							self.bleManager.stopScanning()
							
						}) {
							
							Label("Stop Scanning", systemImage: "stop.fill")
							
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.large)
						.padding()
					}
                      
					#if targetEnvironment(macCatalyst)
						
					if bleManager.connectedPeripheral != nil {
						
						Button(role: .destructive, action: {
							
							if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == CBPeripheralState.connected {
								bleManager.disconnectPeripheral()
								isPreferredRadio = false
							}
							
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
			.navigationBarItems(leading: MeshtasticLogo(), trailing:
				 ZStack {
					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
			 })
        }
		.sheet(isPresented: $invalidFirmwareVersion,  onDismiss: didDismissSheet) {
			InvalidVersion(minimumVersion: self.bleManager.minimumVersion, version: self.bleManager.connectedVersion)
				.presentationDetents([.large])
				.presentationDragIndicator(.automatic)
		}
		.onChange(of: (self.bleManager.invalidVersion)) { cv in
			invalidFirmwareVersion = self.bleManager.invalidVersion
		}
		.onChange(of: (self.bleManager.isSubscribed)) { sub in
			
			if userSettings.preferredNodeNum > 0 && sub {
				
				let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
				fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(userSettings.preferredNodeNum))
				
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
			if self.bleManager.connectedPeripheral != nil && userSettings.preferredPeripheralId == self.bleManager.connectedPeripheral.id {
				isPreferredRadio = true
			} else {
				isPreferredRadio = false
			}
		})
    }
	func didDismissSheet() {
		bleManager.disconnectPeripheral()
	}
}
