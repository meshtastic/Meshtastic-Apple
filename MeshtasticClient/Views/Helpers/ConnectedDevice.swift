/*
Abstract:
A view draws the indicator used in the upper right corner for views using BLE
*/

import SwiftUI

struct ConnectedDevice: View {
    var bluetoothOn: Bool
    var deviceConnected: Bool
    var name: String?

    var body: some View {
        
        HStack {
            VStack {
                
                if bluetoothOn {
                    if deviceConnected {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .imageScale(.large)
                            .foregroundColor(.green)
                            .symbolRenderingMode(.hierarchical)
                        Text(name!).font(.caption2).foregroundColor(.gray)
                    }
                    else {
                
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .imageScale(.large)
                            .foregroundColor(.red)
                            .symbolRenderingMode(.hierarchical)
                        Text("Disconnected").font(.caption2).foregroundColor(.gray)
                        
                    }
                }
                else {
                    Text("Bluetooth Off").font(.caption).foregroundColor(.red)
                }
            }
        }.offset(x: 10, y: -10)
    }
}

struct ConnectedDevice_Previews: PreviewProvider {
    static var previews: some View {
        ConnectedDevice(bluetoothOn: true, deviceConnected: false, name: "Yellow Beam")
            .previewLayout(.fixed(width: 80, height: 70))
    
        ConnectedDevice(bluetoothOn: true, deviceConnected: false,  name: "Yellow Beam")
            .previewLayout(.fixed(width: 80, height: 70))
    }
    
}
