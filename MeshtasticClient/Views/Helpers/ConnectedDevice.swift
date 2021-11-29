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

            if bluetoothOn {
                if deviceConnected {
                    Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                        .imageScale(.large)
                        .foregroundColor(.green)
                        .symbolRenderingMode(.hierarchical)
                    Text(name!).font(.subheadline).foregroundColor(.gray)
                } else {

                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .imageScale(.medium)
                        .foregroundColor(.red)
                        .symbolRenderingMode(.hierarchical)
                    Text("Disconnected").font(.subheadline).foregroundColor(.gray)

                }
            } else {
                Text("Bluetooth Off").font(.subheadline).foregroundColor(.red)
            }
        }
    }
}

struct ConnectedDevice_Previews: PreviewProvider {
    static var previews: some View {
        ConnectedDevice(bluetoothOn: true, deviceConnected: false, name: "Yellow Beam")
            .previewLayout(.fixed(width: 80, height: 70))

        ConnectedDevice(bluetoothOn: true, deviceConnected: false, name: "Yellow Beam")
            .previewLayout(.fixed(width: 80, height: 70))
    }

}
