//
//  DeviceHome.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/7/21.
//

// Abstract:
//  A view showing a list of devices that have been seen on the mesh network

import SwiftUI

struct DeviceHome: View {
    @EnvironmentObject var modelData: ModelData
    @State private var showGPSOnly = false
    
    var filteredDevices: [Device] {
        modelData.devices.filter { device in
            (!showGPSOnly || device.hasGPS)
        }
    }
    var body: some View {
        NavigationView {
           
            List {
                Toggle(isOn: $showGPSOnly) {
                    Text("GPS only")
                }

                ForEach(filteredDevices) { device in
                    NavigationLink(destination: DeviceDetail(device: device)) {
                        DeviceRow(device: device)
                    }
                }
            }
            .navigationTitle("All Devices")

            
        }.navigationViewStyle(StackNavigationViewStyle()) // Force Full screen master details
    }
}

struct DeviceHome_Previews: PreviewProvider {
    static var previews: some View {
        DeviceHome()
            .environmentObject(ModelData())
    }
}
