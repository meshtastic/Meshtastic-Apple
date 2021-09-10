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
            
                List(bleManager.peripherals) { peripheral in
                    HStack {
                        Text(peripheral.name)
                        Spacer()
                        Text(String(peripheral.rssi) + " dB")
                    }
                }.frame(height: 300)
     
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
                        Image(systemName: "arrow.clockwise.circle.fill").imageScale(.large)
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
