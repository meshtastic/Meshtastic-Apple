/*
 Abstract:
 A view draws the indicator used in the upper right corner for views using BLE
 */

import SwiftUI

struct ConnectedDevice: View {

	let deviceConnected: Bool
	let name: String
	let mqttProxyConnected: Bool
	let mqttUplinkEnabled: Bool
	let mqttDownlinkEnabled: Bool
	let mqttTopic: String
	let phoneOnly: Bool
	let showActivityLights: Bool

	init(
		deviceConnected: Bool,
		name: String,
		mqttProxyConnected: Bool = false,
		mqttUplinkEnabled: Bool = false,
		mqttDownlinkEnabled: Bool = false,
		mqttTopic: String = "",
		phoneOnly: Bool = false,
		showActivityLights: Bool = true
	) {
		self.deviceConnected = deviceConnected
		self.name = name
		self.mqttProxyConnected = mqttProxyConnected
		self.mqttUplinkEnabled = mqttUplinkEnabled
		self.mqttDownlinkEnabled = mqttDownlinkEnabled
		self.mqttTopic = mqttTopic
		self.phoneOnly = phoneOnly
		self.showActivityLights = showActivityLights
	}

	var body: some View {
		HStack {
			if showActivityLights {
				RXTXIndicatorWidget()
			}
			if (phoneOnly && UIDevice.current.userInterfaceIdiom == .phone) || !phoneOnly {
				if deviceConnected {
					// Create an HStack for connected state with proper accessibility
					HStack {
						if mqttUplinkEnabled || mqttDownlinkEnabled {
							MQTTIcon(connected: mqttProxyConnected, uplink: mqttUplinkEnabled, downlink: mqttDownlinkEnabled, topic: mqttTopic)
								.accessibilityHidden(true)
						}
						Image(systemName: "link.circle.fill")
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
					.accessibilityLabel(String(localized: "Connected to Bluetooth device", comment: "VoiceOver label for a connected Bluetooth device") + ", " + name.formatNodeNameForVoiceOver())
				} else {
					// Create a container for disconnected state
					HStack {
						Image("custom.link.slash")
							.imageScale(.medium)
							.foregroundColor(.red)
							.symbolRenderingMode(.hierarchical)
							.accessibilityHidden(true)
					}
					.accessibilityElement(children: .ignore)
					.accessibilityLabel(String(localized: "No Bluetooth device connected", comment: "VoiceOver label when no Bluetooth device is connected"))
				}
			}
		}
		.if(.os26) { $0.padding(.leading, 5.0) }
	}
}

#Preview("Multiple variants") {
	VStack(alignment: .trailing) {
		ConnectedDevice(deviceConnected: true, name: "MEMO", mqttProxyConnected: true)
		ConnectedDevice(deviceConnected: true, name: "MEMO", mqttProxyConnected: false, mqttUplinkEnabled: true, mqttDownlinkEnabled: true)
		ConnectedDevice(deviceConnected: true, name: "MEMO", mqttProxyConnected: true, mqttUplinkEnabled: true, mqttDownlinkEnabled: true, mqttTopic: "msh/US/2/e/#")
		ConnectedDevice(deviceConnected: true, name: "MEMO", mqttProxyConnected: false, mqttUplinkEnabled: true, mqttDownlinkEnabled: false)
		ConnectedDevice(deviceConnected: true, name: "MEMO", mqttProxyConnected: true, mqttUplinkEnabled: true, mqttDownlinkEnabled: false)
		ConnectedDevice(deviceConnected: true, name: "MEMO", mqttProxyConnected: false, mqttUplinkEnabled: false, mqttDownlinkEnabled: true)
		ConnectedDevice(deviceConnected: true, name: "MEMO", mqttProxyConnected: true, mqttUplinkEnabled: false, mqttDownlinkEnabled: true)
		ConnectedDevice(deviceConnected: true, name: "MEMO", mqttProxyConnected: true)
		ConnectedDevice(deviceConnected: false, name: "MEMO", mqttProxyConnected: false)
	}
	.environmentObject(AccessoryManager.shared)
}

#Preview("Navigation header item") {
	NavigationView {
		Text("Connect screen")
			.navigationTitle("Connect")
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					MeshtasticLogo()
				}
				ToolbarItem(placement: .topBarTrailing) {
					ConnectedDevice(deviceConnected: true, name: "MEMO", mqttProxyConnected: false)
						.environmentObject(AccessoryManager.shared)
				}
			}
	}
}
