import SwiftUI

struct ConnectedDevice: View {
	private var mqttChannelInfo = false
	private var mqttUplinkEnabled = false
	private var mqttDownlinkEnabled = false

	@EnvironmentObject
	private var bleManager: BLEManager
	@State
	private var rssi: Int?

	@ViewBuilder
	var body: some View {
		if bleManager.isSwitchedOn {
			if bleManager.isConnected {
				HStack(spacing: 4) {
					if mqttChannelInfo {
						MQTTChannelIcon(
							connected: bleManager.mqttProxyConnected,
							uplink: mqttUplinkEnabled,
							downlink: mqttDownlinkEnabled
						)
					}
					else {
						MQTTConnectionIcon(
							connected: bleManager.mqttProxyConnected
						)
					}

					SignalStrengthIndicator(
						signalStrength: bleManager.connectedPeripheral.getSignalStrength(),
						size: 14,
						color: .green
					)
					.padding(8)
					.background(.green.opacity(0.3))
					.clipShape(Circle())
					.onAppear {
						Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
							if let peripheral = bleManager.connectedPeripheral {
								peripheral.peripheral.readRSSI()
							}
						}
					}
				}
			}
			else {
				deviceIcon("antenna.radiowaves.left.and.right.slash", color: .orange)
			}
		}
		else {
			deviceIcon("exclamationmark.triangle.fill", color: .red)
		}
	}

	init() {
		self.mqttChannelInfo = false
	}

	init(
		mqttUplinkEnabled: Bool = false,
		mqttDownlinkEnabled: Bool = false
	) {
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
