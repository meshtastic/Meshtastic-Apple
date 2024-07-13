import SwiftUI
import CoreLocation
import MapKit

struct NodeInfoView: View {
	var modemPreset: ModemPresets = ModemPresets(
		rawValue: UserDefaults.modemPreset
	) ?? ModemPresets.longFast

	@ObservedObject
	var node: NodeInfoEntity

	private var itemDimension: CGFloat = 64
	private var itemCornerRadius: CGFloat = 16

	var body: some View {
		HStack {
			Avatar(
				node.user?.shortName ?? "?",
				background: node.color,
				size: itemDimension
			)

			Spacer()

			if let user = node.user, let hwModel = user.hwModel, hwModel.lowercased() != "unset" {
				Image(hwModel)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.padding(4)
					.frame(width: itemDimension - 4, height: itemDimension - 4)
					.cornerRadius(itemCornerRadius)
					.overlay(
						RoundedRectangle(cornerRadius: itemCornerRadius)
							.stroke(.gray, lineWidth: 4)
					)

				Spacer()
			}

			if node.snr != 0 && !node.viaMqtt {
				VStack(alignment: .center) {
					let signalStrength = LoRaSignal.getStrength(snr: node.snr, rssi: node.rssi, preset: modemPreset)
					LoRaSignalView(signalStrength: signalStrength)

					Text("SNR \(String(format: "%.2f", node.snr))dB")
						.foregroundColor(LoRaSignal.getSnrColor(snr: node.snr, preset: modemPreset))
						.font(.caption2)
						.lineLimit(1)
						.minimumScaleFactor(0.5)
						.fixedSize(horizontal: true, vertical: true)

					Text("RSSI \(node.rssi)dB")
						.foregroundColor(LoRaSignal.getRssiColor(rssi: node.rssi))
						.font(.caption2)
						.lineLimit(1)
						.minimumScaleFactor(0.5)
						.fixedSize(horizontal: true, vertical: true)
				}
				.frame(width: itemDimension, height: itemDimension)

				Spacer()
			}

			BatteryGaugeView(node: node)
				.frame(width: itemDimension, height: itemDimension)
		}
	}

	init(node: NodeInfoEntity) {
		self.node = node
	}
}
