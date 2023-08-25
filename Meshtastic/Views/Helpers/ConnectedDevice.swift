/*
Abstract:
A view draws the indicator used in the upper right corner for views using BLE
*/

import SwiftUI

struct ConnectedDevice: View {
    var bluetoothOn: Bool
    var deviceConnected: Bool
    var name: String
	var mqttProxyConnected: Bool = false

    var body: some View {

        HStack {
			if bluetoothOn {
				if deviceConnected && mqttProxyConnected {
					
					if mqttProxyConnected {
						Image(systemName: "iphone.gen3.radiowaves.left.and.right.circle.fill")
							.imageScale(.large)
							.foregroundColor(.green)
							.symbolRenderingMode(.hierarchical)
					}
				}
                if deviceConnected {
                    Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
						.imageScale(.large)
                        .foregroundColor(.green)
                        .symbolRenderingMode(.hierarchical)
					Text(name).font(name.isEmoji() ? .title : .callout).foregroundColor(.gray)
                } else {

                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .imageScale(.medium)
                        .foregroundColor(.red)
                        .symbolRenderingMode(.hierarchical)
                }
            } else {
                Text("bluetooth.off").font(.subheadline).foregroundColor(.red)
            }
        }
    }
}

struct ConnectedDevice_Previews: PreviewProvider {
    static var previews: some View {
        ConnectedDevice(bluetoothOn: true, deviceConnected: true, name: "MEMO", mqttProxyConnected: true)
            .previewLayout(.fixed(width: 80, height: 70))

        ConnectedDevice(bluetoothOn: true, deviceConnected: false, name: "86D4", mqttProxyConnected: false)
            .previewLayout(.fixed(width: 80, height: 70))
    }

}
