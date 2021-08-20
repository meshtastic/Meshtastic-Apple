//
//  DeviceBLE.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/18/21.
//

import CoreBluetooth
import SwiftUI
import MapKit
import CoreLocation

struct DeviceBLE: View {
    
    @EnvironmentObject var modelData: ModelData
    
    var devices: [Device] {
        modelData.devices
    }
    
    var myPeripheal:CBPeripheral?
    var myCharacteristic:CBCharacteristic?
    var bleManager:CBCentralManager?
    
    let serviceUUID = CBUUID(string: "ab0828b1-198e-4351-b779-901fa0e0371e")
    
    
    var body: some View {
        NavigationView {
           
            ScrollView {
                

                
                
            }
            .navigationTitle("Bluetooth")
            

            
            
            
        }
    }
}
