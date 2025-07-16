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
                        // Create an HStack for connected state with proper accessibility
                        HStack {
                            if mqttUplinkEnabled || mqttDownlinkEnabled {
                                MQTTIcon(connected: mqttProxyConnected, uplink: mqttUplinkEnabled, downlink: mqttDownlinkEnabled, topic: mqttTopic)
                                    .accessibilityHidden(true)
                            }
                            Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                                .imageScale(.large)
                                .foregroundColor(.green)
                                .symbolRenderingMode(.hierarchical)
                                .accessibilityHidden(true)
                            Text(name.addingVariationSelectors)
                                .font(name.isEmoji() ? .title : .callout)
                                .foregroundColor(.gray)
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Connected to Bluetooth device".localized + ", " + name.formatNodeNameForVoiceOver())
                    } else {
                        // Create a container for disconnected state
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .imageScale(.medium)
                                .foregroundColor(.red)
                                .symbolRenderingMode(.hierarchical)
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("No Bluetooth device connected".localized)
                    }
                } else {
                    // Create a container for Bluetooth off state
                    HStack {
                        Text("Bluetooth is off".localized)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Bluetooth is off".localized)
                }
            }
        }
    }
}

struct ConnectedDevice_Previews: PreviewProvider {
    static var previews: some View {
            VStack(alignment: .trailing) {
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
