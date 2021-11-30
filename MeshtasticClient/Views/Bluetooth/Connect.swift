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

    @EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings

	@State var isPreferredRadio: Bool = false

    var body: some View {

		NavigationView {

            VStack {
                if bleManager.isSwitchedOn {

                    List {
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

										if bleManager.connectedNode != nil {

											Text(bleManager.connectedNode.user.longName).font(.title2)
										} else {

											Text(String(bleManager.connectedPeripheral.peripheral.name ?? "Unknown")).font(.title2)
										}
										if bleManager.connectedNode != nil {
											Text("Model: ").font(.caption)+Text(bleManager.connectedNode?.user.hwModel ?? "(null)").font(.caption).foregroundColor(Color.gray)
										}
										Text("BLE Name: ").font(.caption)+Text(bleManager.connectedPeripheral.name).font(.caption).foregroundColor(Color.gray)
										if bleManager.connectedPeripheral.myInfo != nil {
											Text("FW Version: ").font(.caption)+Text(bleManager.connectedPeripheral.myInfo?.firmwareVersion ?? "(null)").font(.caption).foregroundColor(Color.gray)
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

													if bleManager.connectedNode != nil {
														let deviceName = "\(bleManager.connectedNode.user.longName) / \(bleManager.connectedPeripheral.peripheral.name ?? "")"

														userSettings.preferredPeripheralName = deviceName
													} else {
														userSettings.preferredPeripheralName = bleManager.connectedPeripheral.peripheral.name ?? "Unknown Device"
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
                            Image(systemName: "play.fill").imageScale(.large).foregroundColor(.gray)
                            Text("Start Scanning").font(.caption)
                            .font(.caption)
                                .foregroundColor(.gray)
                        }
						.disabled(self.bleManager.isScanning)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                        Spacer()
                        Button(action: {
                            self.bleManager.stopScanning()
                        }) {
                            Image(systemName: "stop.fill").imageScale(.large).foregroundColor(.gray)
                            Text("Stop Scanning")
                            .font(.caption)
                            .foregroundColor(.gray)
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

                    ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedNode != nil) ? bleManager.connectedNode.user.shortName : ((bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.name : "Unknown") )
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: {

			if bleManager.connectedPeripheral != nil && userSettings.preferredPeripheralId == bleManager.connectedPeripheral.peripheral.identifier.uuidString {
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
