import SwiftUI
import CoreLocation
import MapKit

struct NodeInfoView: View {
	var modemPreset: ModemPresets = ModemPresets(
		rawValue: UserDefaults.modemPreset
	) ?? ModemPresets.longFast

	@ObservedObject
	var node: NodeInfoEntity

	var body: some View {
		HStack(alignment: .top, spacing: 16) {
			Avatar(
				node.user?.shortName,
				background: node.color,
				size: 72
			)

			VStack(alignment: .leading, spacing: 8) {
				if let longName = node.user?.longName {
					Text(longName)
						.lineLimit(1)
						.fixedSize(horizontal: true, vertical: false)
						.font(.title)
						.minimumScaleFactor(0.5)
				}

				if node.snr != 0 && !node.viaMqtt {
					LoRaSignalMeterView(
						snr: node.snr,
						rssi: node.rssi,
						preset: modemPreset,
						withLabels: true
					)
				}

				BatteryGaugeView(
					node: node,
					withLabels: true
				)
			}
		}
	}

	init(node: NodeInfoEntity) {
		self.node = node
	}
}
