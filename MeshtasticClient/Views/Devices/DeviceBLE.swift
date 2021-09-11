//
//  DeviceBLE.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/18/21.
//

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
                    Section(header: Text("Connected Device")) {
                        if(bleManager.connectedPeripheral != nil){
                            HStack{
                                Image(systemName: "dot.radiowaves.left.and.right").imageScale(.medium).foregroundColor(.green)
                                Text(bleManager.connectedPeripheral.name!)
                                Spacer()
                               // print(bleManager.meshtasticPeripheral)
                            }
                        }
                        
                    }.textCase(nil)
                    Section(header: Text("Other Meshtastic Devices")) {
                        ForEach(bleManager.peripherals.sorted(by: { $0.rssi > $1.rssi })) { peripheral in
                            HStack {
                                
                                Image(systemName: "circle.fill").imageScale(.medium).foregroundColor(.gray)
                              
                                Button(action: {
                                    self.bleManager.stopScanning()
                                    self.bleManager.disconnectDevice()
                                    self.bleManager.connectToDevice(id: peripheral.id)
                                }) {
                                    Text(peripheral.name)
                                }
                                Spacer()
                                Text(String(peripheral.rssi) + " dB")
                            }
                        }
                    }.textCase(nil)
                }
                // Image(systemName: "dot.radiowaves.left.and.right").imageScale(.medium).foregroundColor(.green)//.rotationEffect(Angle(degrees: 90))
             
                Spacer()
                HStack {
                    VStack (spacing: 10) {
                        Button(action: {
                            self.bleManager.startScanning()
                        }) {
                            Text("Start Scanning")
                        }
                        Button(action: {
                            self.bleManager.stopScanning()
                        }) {
                            Text("Stop Scanning")
                        }
                    }.padding()
     
                    Spacer()
     
                }
                Spacer()
            }
            .navigationTitle("Nearby Devices")
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
