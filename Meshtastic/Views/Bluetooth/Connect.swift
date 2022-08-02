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
	
	@State private var showingVersionSheet = false
	
	@State var initialLoad: Bool = true
	@State var isPreferredRadio: Bool = false
	
	@State var firmwareVersion = "0.0.0"
	@State var minimumVersion = "1.3.28"
	@State var invalidVersion = false
	

    var body: some View {
	
		NavigationView {

            VStack {

				List {
					
					if bleManager.isSwitchedOn {
					
					if bleManager.lastConnectionError.count > 0 {

						Section(header: Text("Connection Error").font(.title)) {

							Text(bleManager.lastConnectionError).font(.title3).foregroundColor(.red)
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
										Text("Bitrate: ").font(.caption)+Text(String(format: "%.2f", bleManager.connectedPeripheral.bitrate ?? 0.00))
											.font(.caption).foregroundColor(Color.gray)
										
										
										Text("Channel Utilization: ").font(.caption)+Text(String(format: "%.2f", bleManager.connectedPeripheral.channelUtilization ?? 0.00))
											.font(.caption).foregroundColor(Color.gray)
										Text("Air Time: ").font(.caption)+Text(String(format: "%.2f", bleManager.connectedPeripheral.airTime ?? 0.00))
											.font(.caption).foregroundColor(Color.gray)
									}
									if bleManager.connectedPeripheral.subscribed {
										Text("Properly Subscribed").font(.caption)
									}
								}
								Spacer()

								VStack(alignment: .center) {

									Text("Preferred").font(.caption2)
									Text("Radio").font(.caption2)
									Toggle("Preferred Radio", isOn: $isPreferredRadio)
										.toggleStyle(SwitchToggleStyle(tint: .accentColor))
										.labelsHidden()
										.onChange(of: isPreferredRadio) { value in
											if value {

												if bleManager.connectedPeripheral != nil {

													let deviceName = (bleManager.connectedPeripheral.peripheral.name ?? "")
													userSettings.preferredPeripheralName = deviceName

												} else {

													userSettings.preferredPeripheralName = bleManager.connectedPeripheral.longName
												}

												userSettings.preferredPeripheralId = bleManager.connectedPeripheral!.peripheral.identifier.uuidString

											} else {

											if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.identifier.uuidString == userSettings.preferredPeripheralId {

												userSettings.preferredPeripheralId = ""
												userSettings.preferredPeripheralName = ""
											}
										}
									}
								}
								
							}
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
							.padding([.top, .bottom])
							
							
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
					.textCase(nil)

					if bleManager.peripherals.count > 0 {
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
            .navigationTitle("Bluetooth Radios")
            .navigationBarItems(trailing:

               ZStack {

                    ConnectedDevice(
						bluetoothOn: self.bleManager.isSwitchedOn,
						deviceConnected: self.bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? self.bleManager.connectedPeripheral.shortName :
							"????")
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
		.sheet(isPresented: $invalidVersion) {
			
			InvalidVersion(errorText: "1.3 ALPHA PREVIEW this version of the app supports only version \(minimumVersion) and above. Your device has been disconnected.")
		}
		
		
		.onChange(of: firmwareVersion) { iv in
			
			bleManager.disconnectPeripheral()
		}
		.onChange(of: self.bleManager.isConnected) { ic in
			
			firmwareVersion = bleManager.lastConnnectionVersion
			let supportedVersion = firmwareVersion == "0.0.0" ||  minimumVersion.compare(firmwareVersion, options: .numeric) == .orderedAscending || minimumVersion.compare(firmwareVersion, options: .numeric) == .orderedSame
			
			invalidVersion = !supportedVersion
			
			if invalidVersion {
				bleManager.disconnectPeripheral()
			}
			
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
}

struct Connect_Previews: PreviewProvider {

    static var previews: some View {
        Connect()

            .environmentObject(BLEManager())
    }
}
