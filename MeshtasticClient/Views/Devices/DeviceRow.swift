//
//  DeviceMap.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/7/21.
//
//  Abstract:
//  A single row to be displayed in a list of landmarks.

import SwiftUI

struct DeviceRow: View {
    var device: Device

    var body: some View {
        HStack {
            
            device.image.resizable().frame(width: 150, height: 150)
            
            VStack(alignment: .leading) {
                
                Text(device.longName).font(.title2)
                HStack {
                    if device.hasGPS {
                        Image(systemName: "location.fill.viewfinder")
                            .foregroundColor(.blue).font(.title3)
                    }
                    if device.isRouter {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(.blue).font(.title3)
                    }
                    if device.hardwareModel == "TBEAM" || device.hardwareModel == "TLORA" {
                        Image(systemName: "wifi")
                            .foregroundColor(.blue).font(.title3)
                    }
                    if false {
                        Image(systemName: "rectangle.connected.to.line.below")
                            .foregroundColor(.green).font(.title2)
                    }
                }
            }
            Spacer()
        }
    }
}

struct DeviceRow_Previews: PreviewProvider {
    static var devices = ModelData().devices

    static var previews: some View {
        Group {
            DeviceRow(device: devices[0])
            DeviceRow(device: devices[1])
        }
        .previewLayout(.fixed(width: 300, height: 70))
    }
}
