import SwiftUI

struct ConnectedDevice: View {
	private var isOn: Bool
	private var connected: Bool
	private var nodeName: String
	private var mqttChannelInfo = false
	private var mqttProxyConnected = false
	private var mqttUplinkEnabled = false
	private var mqttDownlinkEnabled = false

	var body: some View {
		if isOn {
			if connected {
				HStack(spacing: 4) {
					if mqttChannelInfo {
						MQTTChannelIcon(
							connected: mqttProxyConnected,
							uplink: mqttUplinkEnabled,
							downlink: mqttDownlinkEnabled
						)
					}
					else {
						MQTTConnectionIcon(
							connected: mqttProxyConnected
						)
					}

					deviceIcon("antenna.radiowaves.left.and.right", color: .green)
				}
			} else {
				deviceIcon("antenna.radiowaves.left.and.right.slash", color: .orange)
			}
		} else {
			deviceIcon("exclamationmark.triangle.fill", color: .red)
		}
	}

	public init(
		ble: BLEManager
	) {
		self.isOn = ble.isSwitchedOn
		self.connected = ble.isNodeConnected
		self.nodeName = ble.connectedNodeName
		self.mqttProxyConnected = ble.mqttProxyConnected

		self.mqttChannelInfo = false
	}

	public init(
		ble: BLEManager,
		mqttUplinkEnabled: Bool = false,
		mqttDownlinkEnabled: Bool = false
	) {
		self.isOn = ble.isSwitchedOn
		self.connected = ble.isNodeConnected
		self.nodeName = ble.connectedNodeName
		self.mqttProxyConnected = ble.mqttProxyConnected

		self.mqttUplinkEnabled = mqttUplinkEnabled
		self.mqttDownlinkEnabled = mqttDownlinkEnabled

		self.mqttChannelInfo = true
	}

	@ViewBuilder
	private func deviceIcon(_ resource: String, color: Color) -> some View {
		Image(systemName: resource)
			.resizable()
			.scaledToFit()
			.frame(width: 16, height: 16)
			.foregroundColor(color)
			.padding(8)
			.background(color.opacity(0.3))
			.clipShape(Circle())
	}
}
