//
//  Connect.swift
//  Meshtastic Apple
//
//  Copyright(c) Garth Vander Houwen 8/18/21.
//

import SwiftUI
import MapKit
import CoreLocation
import CoreBluetooth

struct Connect: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
	
	@State var initialLoad: Bool = true
	@State var isPreferredRadio: Bool = false
	
	@State var invalidFirmwareVersion = false

    var body: some View {
	
		NavigationView {

            VStack {

				List {
					
					if bleManager.isSwitchedOn {
					
					if bleManager.lastConnectionError.count > 0 {

						Section(header: Text("Connection Error").font(.title)) {

							Text(bleManager.lastConnectionError).font(.callout).foregroundColor(.red)
						}
						.textCase(nil)
					}
						
					Section(header: Text("Connected Radio").font(.title)) {
						
						if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == .connected {
							
							HStack {

								Image(systemName: "antenna.radiowaves.left.and.right")
									.symbolRenderingMode(.hierarchical)
									.imageScale(.large).foregroundColor(.green)
									.padding(.trailing)

								VStack(alignment: .leading) {

									if bleManager.connectedPeripheral != nil {

										Text(bleManager.connectedPeripheral.longName).font(.title2)

									}
									Text("BLE Name: ").font(.caption)+Text(bleManager.connectedPeripheral.peripheral.name ?? "Unknown")
										.font(.caption).foregroundColor(Color.gray)
									if bleManager.connectedPeripheral != nil {
										Text("FW Version: ").font(.caption)+Text(bleManager.connectedPeripheral.firmwareVersion)
											.font(.caption).foregroundColor(Color.gray)
									}
									if bleManager.connectedPeripheral.subscribed {
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
													bleManager.preferredPeripheral = true
													isPreferredRadio = true
													
												}

												
											} else {

											if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.identifier.uuidString == userSettings.preferredPeripheralId {

												userSettings.preferredPeripheralId = ""
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

								Text("Num: \(String(bleManager.connectedPeripheral.num))")
								Text("Short Name: \(bleManager.connectedPeripheral.shortName)")
								Text("Long Name: \(bleManager.connectedPeripheral.longName)")
								Text("Unique Code: \(bleManager.connectedPeripheral.lastFourCode)")
								Text("Max Channels: \(String(bleManager.connectedPeripheral.maxChannels))")
								Text("Bitrate: \(String(format: "%.2f", bleManager.connectedPeripheral.bitrate ?? 0.00))")
								Text("Ch. Utilization: \(String(format: "%.2f", bleManager.connectedPeripheral.channelUtilization ?? 0.00))")
								Text("Air Time: \(String(format: "%.2f", bleManager.connectedPeripheral.airTime ?? 0.00))")
								Text("BLE RSSI: \(bleManager.connectedPeripheral.rssi)")
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
			
			.navigationBarItems(leading:
		     MeshtasticLogo(),
			 trailing:

			 ZStack {
				
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
			 })
        }
        .navigationViewStyle(StackNavigationViewStyle())
		.sheet(isPresented: $invalidFirmwareVersion,  onDismiss: didDismissSheet) {
			
			InvalidVersion(minimumVersion: self.bleManager.minimumVersion, version: self.bleManager.connectedVersion)
				.presentationDetents([.large])
				.presentationDragIndicator(.automatic)
		}

	
		.onChange(of: (self.bleManager.invalidVersion)) { cv in
			
			invalidFirmwareVersion = self.bleManager.invalidVersion
			
		}
        .onAppear(perform: {
						
			if initialLoad {
				
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
		
				initialLoad = false
			}
			
			if self.bleManager.connectedPeripheral != nil && userSettings.preferredPeripheralId == self.bleManager.connectedPeripheral.peripheral.identifier.uuidString {
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

struct Connect_Previews: PreviewProvider {

    static var previews: some View {
        Connect()

            .environmentObject(BLEManager())
    }
}
