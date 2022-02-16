//
//  Connect.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/18/21.
//

// Abstract:
//  A view allowing you to interact with nearby meshtastic nodes

import SwiftUI
import MapKit
import CoreLocation
import CoreBluetooth

struct Connect: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings

	@State var isPreferredRadio: Bool = false

    var body: some View {
		
		let firmwareVersion = bleManager.lastConnnectionVersion
		let minimumVersion = "1.2.52"
		let supportedVersion = firmwareVersion == "0.0.0" ||  minimumVersion.compare(firmwareVersion, options: .numeric) == .orderedAscending || minimumVersion.compare(firmwareVersion, options: .numeric) == .orderedSame
		
		NavigationView {

            VStack {
                if bleManager.isSwitchedOn {

                    List {
						
						if supportedVersion == false {

							Section(header: Text("Upgrade your Firmware").font(.title)) {

								Text("🚨 Your firmware version is unsupported, the minimum firmware version is \(minimumVersion).").font(.subheadline).foregroundColor(.red)
							}
							.textCase(nil)
						}
						
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

											Text(bleManager.connectedPeripheral.name).font(.title2)

										}
										Text("BLE Name: ").font(.caption)+Text(bleManager.connectedPeripheral.peripheral.name ?? "Unknown")
											.font(.caption).foregroundColor(Color.gray)
										if bleManager.connectedPeripheral != nil {
											Text("FW Version: ").font(.caption)+Text(bleManager.connectedPeripheral.firmwareVersion)
												.font(.caption).foregroundColor(Color.gray)
											Text("Channel Utilization: ").font(.caption)+Text(String(bleManager.connectedPeripheral.channelUtilization ?? 0.00))
												.font(.caption).foregroundColor(Color.gray)
											Text("Air Time: ").font(.caption)+Text(String(bleManager.connectedPeripheral.airTime ?? 0.00))
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
								ForEach(bleManager.peripherals.filter({ $0.peripheral.state == CBPeripheralState.disconnected }).sorted(by: { $0.name < $1.name })) { peripheral in
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
                    }

                    HStack(alignment: .center) {
                        Spacer()
                        Button(action: {
							
                            self.bleManager.startScanning()
							
                        }) {
							
                            Image(systemName: "play.circle")
								.symbolRenderingMode(.hierarchical)
								.imageScale(.large)
								.foregroundColor(self.bleManager.isScanning ? .gray : .accentColor)
                            Text("Start Scanning").font(.caption)
                            .font(.caption)

                        }
						.disabled(self.bleManager.isScanning)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                        Spacer()
                        Button(action: {
							
                            self.bleManager.stopScanning()
							
                        }) {
							
							Image(systemName: "stop.circle")
								.symbolRenderingMode(.hierarchical)
								.imageScale(.large)
								.foregroundColor(!self.bleManager.isScanning ? .gray : .accentColor)
                            Text("Stop Scanning")
                            .font(.caption)
							
                        }
						.disabled(!self.bleManager.isScanning)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                        Spacer()
                    }
					.padding(.bottom, 10)

                } else {
                    Text("Bluetooth: OFF")
                        .foregroundColor(.red)
                        .font(.title)
                }
            }
            .navigationTitle("Bluetooth Radios")
            .navigationBarItems(trailing:

               ZStack {

                    ConnectedDevice(
						bluetoothOn: self.bleManager.isSwitchedOn,
						deviceConnected: self.bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? self.bleManager.connectedPeripheral.shortName :
							"???")
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: {

			self.bleManager.context = context

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
