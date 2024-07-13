import Foundation
import SwiftUI

struct LoRaSignalMeterView: View {
	private var snr: Float
	private var rssi: Int32
	private var preset: ModemPresets
	private var compact: Bool
	private var withLabels: Bool

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme

	var body: some View {
		if snr != 0.0 && rssi != 0 {
			let signalStrength = LoRaSignal.getStrength(snr: snr, rssi: rssi, preset: preset)

			if compact {
				HStack {
					if withLabels {
						Image(systemName: "cellularbars")
							.font(.body)
							.frame(width: 32)
					}

					Gauge(
						value: Double(signalStrength.rawValue),
						in: 0...3
					) { }
						.gaugeStyle(.accessoryLinear)
						.tint(
							Gradient(colors: [.clear, .accentColor])
						)

					if withLabels {
						let snrFormatted = String(format: "%.0f", snr) + "dB"
						Text(snrFormatted)
							.font(.footnote)
							.lineLimit(1)
							.fixedSize(horizontal: true, vertical: false)
							.minimumScaleFactor(0.5)
							.padding(4)
					}
				}
			} else {
				VStack {
					LoRaSignalView(signalStrength: signalStrength)

					Text("Signal \(signalStrength.description)")
						.font(.footnote)

					Text("SNR \(String(format: "%.2f", snr))dB")
						.foregroundColor(LoRaSignal.getSnrColor(snr: snr, preset: ModemPresets.longFast))
						.font(.caption2)

					Text("RSSI \(rssi)dB")
						.foregroundColor(LoRaSignal.getRssiColor(rssi: rssi))
						.font(.caption2)
				}
			}
		}
	}

	init(
		snr: Float,
		rssi: Int32,
		preset: ModemPresets,
		compact: Bool = true,
		withLabels: Bool = false
	) {
		self.snr = snr
		self.rssi = rssi
		self.preset = preset
		self.compact = compact
		self.withLabels = withLabels
	}
}
