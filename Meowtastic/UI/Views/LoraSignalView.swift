import Foundation
import SwiftUI

struct LoraSignalView: View {
	private var snr: Float
	private var rssi: Int32
	private var preset: ModemPresets
	private var withLabels: Bool

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme

	var body: some View {
		if snr != 0.0 && rssi != 0 {
			let signalStrength = LoRaSignal.getStrength(snr: snr, rssi: rssi, preset: preset)

			HStack {
				Image(systemName: "cellularbars")
					.font(.system(size: 14, weight: .regular, design: .rounded))
					.foregroundColor(.gray)
					.frame(width: 16)

				Gauge(
					value: Double(signalStrength.rawValue),
					in: 0...3
				) { }
					.gaugeStyle(.accessoryLinearCapacity)
					.tint(.gray)

				if withLabels {
					let snrFormatted = String(format: "%.0f", snr) + "dB"

					Text(snrFormatted)
						.font(.system(size: 14, weight: .regular, design: .rounded))
						.foregroundColor(.gray)
						.lineLimit(1)
						.fixedSize(horizontal: true, vertical: true)
				}
			}
		}
	}

	init(
		snr: Float,
		rssi: Int32,
		preset: ModemPresets,
		withLabels: Bool = false
	) {
		self.snr = snr
		self.rssi = rssi
		self.preset = preset
		self.withLabels = withLabels
	}
}
