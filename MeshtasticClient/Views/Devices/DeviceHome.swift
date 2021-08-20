//
//  DeviceHome.swift
//  Landmarks
//
//  Created by Garth Vander Houwen on 8/7/21.
//  See LICENSE folder for app licensing information.
//

// Abstract:
//  A view showing devices above a list of devices
//  grouped by device.

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
