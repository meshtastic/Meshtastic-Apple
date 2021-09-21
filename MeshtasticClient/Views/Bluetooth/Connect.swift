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

struct Connect: View {
    
    @EnvironmentObject var modelData: ModelData
    
    @ObservedObject var bleManager = BLEManager()
        
    var body: some View {
        NavigationView {
            
            VStack {
                if bleManager.isSwitchedOn {
                    
                    List {
                        Section(header: Text("Connected Device").font(.title)) {
                            if(bleManager.connectedPeripheral != nil){
                                HStack{
                                    Image(systemName: "antenna.radiowaves.left.and.right").imageScale(.large).foregroundColor(.green)
                                    Text((bleManager.connectedPeripheral.name != nil) ? bleManager.connectedPeripheral.name! : "Unknown").font(.title2)
                                }
                            }
                            else {
                                Text("No device connected").font(.title2)
                            }
                            
                        }.textCase(nil)
                        
                        Section(header: Text("New Devices").font(.title)) {
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
                        
                        Section(header: Text("Known Devices").font(.title)) {
                            
                        }.textCase(nil)
                        
                    }
                    
                    HStack (alignment: .center) {
                        Spacer()
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
                        Spacer()
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
                        Spacer()
                    }.padding(.bottom, 25)
                    
                }
                else {
                    Text("Bluetooth: OFF")
                        .foregroundColor(.red)
                        .font(.title)
                }
            }
            .navigationTitle("Bluetooth Radios")
            .navigationBarItems(trailing:
                HStack {
                    VStack {
                        if bleManager.isSwitchedOn && bleManager.connectedPeripheral != nil {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .imageScale(.large)
                                .foregroundColor(.green)
                            Text("Connected").font(.caption2).foregroundColor(.gray)
                        }
                        else {
                    
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .imageScale(.large)
                                .foregroundColor(.red)
                            Text("Disconnected").font(.caption2).foregroundColor(.gray)
                            
                        }
                    }
                }.offset(x: 10, y: -10)
            )
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct Connect_Previews: PreviewProvider {
    static let modelData = ModelData()
    static let bleManager = BLEManager()

    static var previews: some View {
        Connect(bleManager: bleManager)
            .environmentObject(ModelData())
            
    }
}
