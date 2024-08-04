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
				if withLabels {
					Image(systemName: "cellularbars")
						.font(.footnote)
						.frame(width: 24)
				}

				Gauge(
					value: Double(signalStrength.rawValue),
					in: 0...3
				) { }
					.gaugeStyle(.accessoryLinearCapacity)
					.tint(
						colorScheme == .dark ? .white : .black
					)

				if withLabels {
					let snrFormatted = String(format: "%.0f", snr) + "dB"

					Text(snrFormatted)
						.font(.footnote)
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
