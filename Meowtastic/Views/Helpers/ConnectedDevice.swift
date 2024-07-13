import SwiftUI

struct ConnectedDevice: View {
	private var isOn: Bool
	private var connected: Bool
	private var nodeName: String
	private var mqttProxyConnected = false
	private var mqttUplinkEnabled = false
	private var mqttDownlinkEnabled = false
	private var mqttTopic = ""

	var body: some View {
		if isOn {
			if connected {
				HStack(spacing: 4) {
					if mqttProxyConnected {
						MQTTIcon(
							connected: mqttProxyConnected,
							uplink: mqttUplinkEnabled,
							downlink: mqttDownlinkEnabled,
							topic: mqttTopic
						)
					}

					Image(systemName: "antenna.radiowaves.left.and.right")
						.foregroundColor(.green)
						.padding(6)
						.background(Color.green.opacity(0.3))
						.clipShape(Circle())
				}
			} else {
				Image(systemName: "antenna.radiowaves.left.and.right.slash")
					.foregroundColor(.orange)
					.padding(6)
					.background(Color.orange.opacity(0.3))
					.clipShape(Circle())
			}
		} else {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundColor(.red)
				.padding(6)
				.background(Color.red.opacity(0.3))
				.clipShape(Circle())
		}
	}

	public init(
		ble: BLEManager,
		mqttProxyConnected: Bool = false,
		mqttUplinkEnabled: Bool = false,
		mqttDownlinkEnabled: Bool = false,
		mqttTopic: String = ""
	) {
		isOn = ble.isSwitchedOn
		connected = ble.isNodeConnected
		nodeName = ble.connectedNodeName

		self.mqttProxyConnected = mqttProxyConnected
		self.mqttUplinkEnabled = mqttUplinkEnabled
		self.mqttDownlinkEnabled = mqttDownlinkEnabled
		self.mqttTopic = mqttTopic
	}
}
