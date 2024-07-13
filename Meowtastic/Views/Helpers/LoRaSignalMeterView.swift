import Foundation
import SwiftUI

struct LoRaSignalMeterView: View {
	private var snr: Float
	private var rssi: Int32
	private var preset: ModemPresets
	private var compact: Bool

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme

	private var gradient: Gradient {
		if colorScheme == .dark {
			return Gradient(colors: [.black, .accentColor])
		}
		else {
			return Gradient(colors: [.white, .accentColor])
		}
	}

	var body: some View {
		if snr != 0.0 && rssi != 0 {
			let signalStrength = LoRaSignal.getStrength(snr: snr, rssi: rssi, preset: preset)

			if !compact {
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
			} else {
				VStack {
					Gauge(
						value: Double(signalStrength.rawValue),
						in: 0...3
					) {
						// no-op
					}
					.gaugeStyle(.accessoryLinear)
					.font(.caption)
					.tint(gradient)
				}
			}
		}
	}

	init(
		snr: Float,
		rssi: Int32,
		preset: ModemPresets,
		compact: Bool = true
	) {
		self.snr = snr
		self.rssi = rssi
		self.preset = preset
		self.compact = compact
	}
}
