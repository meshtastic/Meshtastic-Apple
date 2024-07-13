import SwiftUI

struct ConnectedDevice: View {
	private var isOn: Bool
	private var connected: Bool
	private var nodeName: String
	private var mqttProxyConnected = false
	private var mqttUplinkEnabled = false
	private var mqttDownlinkEnabled = false
	private var mqttTopic = ""
	private var phoneOnly = false

	var body: some View {
		HStack {
			if (phoneOnly && UIDevice.current.userInterfaceIdiom == .phone) || !phoneOnly {
				if isOn {
					if connected {
						if mqttUplinkEnabled || mqttDownlinkEnabled {
							MQTTIcon(connected: mqttProxyConnected, uplink: mqttUplinkEnabled, downlink: mqttDownlinkEnabled, topic: mqttTopic)
						}

						Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
							.imageScale(.large)
							.foregroundColor(.green)
							.symbolRenderingMode(.hierarchical)

						Text(nodeName)
							.font(nodeName.isEmoji() ? .title : .callout)
							.foregroundColor(.gray)
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

	public init(
		ble: BLEManager,
		mqttProxyConnected: Bool = false,
		mqttUplinkEnabled: Bool = false,
		mqttDownlinkEnabled: Bool = false,
		mqttTopic: String = "",
		phoneOnly: Bool = false
	) {
		isOn = ble.isSwitchedOn
		connected = ble.isNodeConnected
		nodeName = ble.connectedNodeName


		self.mqttProxyConnected = mqttProxyConnected
		self.mqttUplinkEnabled = mqttUplinkEnabled
		self.mqttDownlinkEnabled = mqttDownlinkEnabled
		self.mqttTopic = mqttTopic
		self.phoneOnly = phoneOnly
	}
}
