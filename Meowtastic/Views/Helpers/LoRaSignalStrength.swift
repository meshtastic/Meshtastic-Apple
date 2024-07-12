import Foundation
import SwiftUI

struct LoRaSignalStrengthMeter: View {
	private var snr: Float
	private var rssi: Int32
	private var preset: ModemPresets
	private var compact: Bool

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme

	private var gradient: Gradient {
		if colorScheme == .dark {
			return Gradient(colors: [.black, .white])
		}
		else {
			return Gradient(colors: [.white, .black])
		}
	}

	var body: some View {
		if snr != 0.0 && rssi != 0 {
			let signalStrength = getLoRaSignalStrength(snr: snr, rssi: rssi, preset: preset)

			if !compact {
				VStack {
					LoRaSignalStrengthIndicator(signalStrength: signalStrength)

					Text("Signal \(signalStrength.description)")
						.font(.footnote)

					Text("SNR \(String(format: "%.2f", snr))dB")
						.foregroundColor(getSnrColor(snr: snr, preset: ModemPresets.longFast))
						.font(.caption2)

					Text("RSSI \(rssi)dB")
						.foregroundColor(getRssiColor(rssi: rssi))
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

	init(snr: Float, rssi: Int32, preset: ModemPresets, compact: Bool = true) {
		self.snr = snr
		self.rssi = rssi
		self.preset = preset
		self.compact = compact
	}
}

struct LoRaSignalStrengthMeter_Previews: PreviewProvider {
	static var previews: some View {
		ScrollView {
			VStack {
				HStack {
					// Good
					LoRaSignalStrengthMeter(snr: -1, rssi: -114, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -5, rssi: -100, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -10, rssi: -100, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -17, rssi: -114, preset: ModemPresets.longFast, compact: false)
				}
				HStack {
					// Fair
					LoRaSignalStrengthMeter(snr: -9.5, rssi: -119, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -15.0, rssi: -115, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -17.5, rssi: -100, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -22.5, rssi: -100, preset: ModemPresets.longFast, compact: false)
				}
				HStack {
					// Bad
					LoRaSignalStrengthMeter(snr: -11.25, rssi: -120, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -12.75, rssi: -139, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -20.25, rssi: -128, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -30, rssi: -120, preset: ModemPresets.longFast, compact: false)
				}
				HStack {
					LoRaSignalStrengthMeter(snr: -15, rssi: -124, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -17.25, rssi: -126, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -19.5, rssi: -128, preset: ModemPresets.longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -20, rssi: -150, preset: ModemPresets.longFast, compact: false)
				}
				HStack {
					// None
					LoRaSignalStrengthMeter(snr: -26.0, rssi: -129, preset: ModemPresets.longFast, compact: false)
				}
			}
			.padding(.top)
		}

		VStack {
			// Good
			LoRaSignalStrengthMeter(snr: -10, rssi: -100, preset: ModemPresets.longFast, compact: true)
			// Fair
			LoRaSignalStrengthMeter(snr: -9.5, rssi: -119, preset: ModemPresets.longFast, compact: true)
			// Bad
			LoRaSignalStrengthMeter(snr: -12.75, rssi: -139, preset: ModemPresets.longFast, compact: true)
			// None
			LoRaSignalStrengthMeter(snr: -26.0, rssi: -128, preset: ModemPresets.longFast, compact: true)
		}
	}
}
