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
    var mqttUplinkEnabled: Bool = false
    var mqttDownlinkEnabled: Bool = false
        var mqttTopic: String = ""
    var phoneOnly: Bool = false

    var body: some View {
        HStack {
            if (phoneOnly && UIDevice.current.userInterfaceIdiom == .phone) || !phoneOnly {
                if bluetoothOn {
                    if deviceConnected {
						if (mqttUplinkEnabled || mqttDownlinkEnabled) {
							MQTTIcon(connected: mqttProxyConnected, uplink: mqttUplinkEnabled, downlink: mqttDownlinkEnabled, topic: mqttTopic)
						}
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
}




struct ConnectedDevice_Previews: PreviewProvider {
    static var previews: some View {
            VStack (alignment: .trailing) {
                ConnectedDevice(bluetoothOn: true, deviceConnected: true, name: "MEMO", mqttProxyConnected: true)
                ConnectedDevice(bluetoothOn: true, deviceConnected: true, name: "MEMO", mqttProxyConnected: false, mqttUplinkEnabled: true, mqttDownlinkEnabled: true)
                ConnectedDevice(bluetoothOn: true, deviceConnected: true, name: "MEMO", mqttProxyConnected: true, mqttUplinkEnabled: true, mqttDownlinkEnabled: true, mqttTopic: "msh/US/2/e/#")
                ConnectedDevice(bluetoothOn: true, deviceConnected: true, name: "MEMO", mqttProxyConnected: false, mqttUplinkEnabled: true, mqttDownlinkEnabled: false)
                ConnectedDevice(bluetoothOn: true, deviceConnected: true, name: "MEMO", mqttProxyConnected: true, mqttUplinkEnabled: true, mqttDownlinkEnabled: false)
                ConnectedDevice(bluetoothOn: true, deviceConnected: true, name: "MEMO", mqttProxyConnected: false, mqttUplinkEnabled: false, mqttDownlinkEnabled: true)
                ConnectedDevice(bluetoothOn: true, deviceConnected: true, name: "MEMO", mqttProxyConnected: true, mqttUplinkEnabled: false, mqttDownlinkEnabled: true)
                ConnectedDevice(bluetoothOn: true, deviceConnected: true, name: "MEMO", mqttProxyConnected: true)
                ConnectedDevice(bluetoothOn: true, deviceConnected: false, name: "MEMO", mqttProxyConnected: false)
            }.previewLayout(.fixed(width: 150, height: 275))
        }
}
