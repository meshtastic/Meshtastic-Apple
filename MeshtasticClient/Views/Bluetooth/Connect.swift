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
import CoreBluetooth

struct Connect: View {
    
    @EnvironmentObject var meshData: MeshData
    
    @EnvironmentObject var bleManager: BLEManager
        
    var body: some View {
        NavigationView {
            
            VStack {
                if bleManager.isSwitchedOn {
                    
                    List {
                        Section(header: Text("Connected Device").font(.title)) {
                            if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == .connected {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .symbolRenderingMode(.hierarchical)
                                        .imageScale(.large).foregroundColor(.green)
                                        .padding(.trailing)
                                    
                                    if bleManager.connectedPeripheral.myInfo != nil {
                                        VStack  (alignment: .leading)  {
                                            if bleManager.connectedNode != nil {
                                                
                                                Text(bleManager.connectedNode.user.longName).font(.title2)
                                            }
                                            else {
                                                Text(String(bleManager.connectedPeripheral.myInfo?.myNodeNum ?? 0)).font(.title2)
                                                
                                            }
                                            Text("FW Version: ").font(.caption)+Text(bleManager.connectedPeripheral.myInfo?.firmwareVersion ?? "(null)").font(.caption).foregroundColor(Color.gray)
                                        }
                                    }
                                    else {
                                        Text((bleManager.connectedPeripheral!.peripheral.name != nil) ? bleManager.connectedPeripheral!.peripheral.name! : "Unknown").font(.title2)
                                    }
                                }
                                .padding()
                                .swipeActions {
                                    Button {
                                        if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == CBPeripheralState.connected
                                        {
                                            
                                            bleManager.disconnectDevice() 
                                        }
                                    } label: {
                                        Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
                                    }
                                    .tint(.red)
                                }
                            }
                            else {
                                HStack{
                                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                        .symbolRenderingMode(.hierarchical)
                                        .imageScale(.large).foregroundColor(.red)
                                        .padding(.trailing)
                                    Text("No device connected").font(.title3)
                                }
                                .padding()
                            }
                            
                        }.textCase(nil)
                        
                        Section(header: Text("Available Devices").font(.title)) {
                            ForEach(bleManager.peripherals.filter({ $0.peripheral.state == CBPeripheralState.disconnected }).sorted(by: { $0.rssi > $1.rssi })) { peripheral in
                                HStack {
                                    Image(systemName: "circle.fill")
                                        .imageScale(.large).foregroundColor(.gray)
                                        .padding(.trailing)
                                    Button(action: {
                                        self.bleManager.stopScanning()
                                        if bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.peripheral.state == CBPeripheralState.connected
                                        {
                                            self.bleManager.disconnectDevice()
                                        }
                                        self.bleManager.connectToDevice(id: peripheral.id)
                                    }) {
                                        Text(peripheral.name).font(.title3)
                                    }
                                    Spacer()
                                    Text(String(peripheral.rssi) + " dB").font(.title3)
                                }.padding([.bottom,.top])
                            }
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
                    }.padding(.bottom, 10)
                    
                }
                else {
                    Text("Bluetooth: OFF")
                        .foregroundColor(.red)
                        .font(.title)
                }
            }
            .navigationTitle("Bluetooth Radios")
            .navigationBarItems(trailing:
                                  
               VStack(alignment: .trailing) {

                ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedNode != nil) ? bleManager.connectedNode.user.shortName : ((bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.name : "Unknown") )
                
                }
            )
        }.navigationViewStyle(StackNavigationViewStyle())
        .onAppear{
            bleManager.startScanning()
        }
    }
}

struct Connect_Previews: PreviewProvider {
   // static let meshData = MeshData()
  //  static let bleManager = BLEManager()

    static var previews: some View {
        Connect()
            .environmentObject(MeshData())
            .environmentObject(BLEManager())
            
    }
}
