//
//  DeviceBLE.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/18/21.
//

// Abstract:
//  A view allowing you to interact with nearby meshtastic nodes

import SwiftUI
import MapKit
import CoreLocation

struct DeviceBLE: View {
    
    @EnvironmentObject var modelData: ModelData
    
    @ObservedObject var bleManager = BLEManager()
    
    var devices: [Device] {
        modelData.devices
    }
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("Connected Device").font(.title)) {
                        if(bleManager.connectedPeripheral != nil){
                            HStack{
                                Image(systemName: "dot.radiowaves.left.and.right").imageScale(.large).foregroundColor(.green)
                                Text(bleManager.connectedPeripheral.name!).font(.title2)
                            }
                        }
                        else {
                            Text("No device connected").font(.title2)
                        }
                        
                    }.textCase(nil)
                    Section(header: Text("Other Meshtastic Devices").font(.title)) {
                        ForEach(bleManager.peripherals.sorted(by: { $0.rssi > $1.rssi })) { peripheral in
                            HStack {
                                Image(systemName: "circle.fill").imageScale(.large).foregroundColor(.gray)
                                Button(action: {
                                    self.bleManager.stopScanning()
                                    self.bleManager.disconnectDevice()
                                    self.bleManager.connectToDevice(id: peripheral.id)
                                }) {
                                    Text(peripheral.name).font(.title2)
                                }
                                Spacer()
                                Text(String(peripheral.rssi) + " dB").font(.title3)
                            }
                        }
                    }.textCase(nil)
                }
                Spacer()
                HStack (spacing: 15) {
                    Button(action: {
                        self.bleManager.startScanning()
                    }) {
                        Image(systemName: "play.fill").imageScale(.large).foregroundColor(.gray)
                        Text("Start Scanning").font(.caption)
                        .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                    Spacer(minLength: 10)
                    Button(action: {
                        self.bleManager.stopScanning()
                    }) {
                        Image(systemName: "stop.fill").imageScale(.large).foregroundColor(.gray)
                        Text("Stop Scanning")
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }.padding()
                Spacer()
            }
            .navigationTitle("Nearby BLE Devices")
            .navigationBarItems(leading:
                HStack {
                    Button(action: {
                        self.bleManager.startScanning()
                    }) {
                        Image(systemName: "arrow.clockwise.circle").imageScale(.large)
                    }}, trailing:
                HStack {
                    if bleManager.isSwitchedOn {
                        Text("Bluetooth: ON")
                            .foregroundColor(.green)
                            .font(.caption2)
                    }
                    else {
                        Text("Bluetooth: OFF")
                            .foregroundColor(.red)
                            .font(.caption2)
                    }
                }
            )
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
