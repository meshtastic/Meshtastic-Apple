//
//  LoRaSignalStrengthIndicator.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 5/9/23.
//

import Foundation
import SwiftUI

struct LoRaSignalStrengthIndicator: View {
	let signalStrength: LoRaSignalStrength

	var body: some View {
		HStack {
			ForEach(0..<3) { bar in
				RoundedRectangle(cornerRadius: 3)
					.divided(amount: (CGFloat(bar) + 1) / CGFloat(3))
					.fill(getColor(signalStrength: signalStrength).opacity(bar <= signalStrength.rawValue ? 1 : 0.3))
					.frame(width: 8, height: 40)
			}
		}
	}
}

struct LoRaSignalStrengthIndicator_Previews: PreviewProvider {
	static var previews: some View {
		VStack {
			let signalStrength = getLoRaSignalStrength(snr: -12.75, rssi: -139, preset: ModemPresets.longFast)
			LoRaSignalStrengthIndicator(signalStrength: signalStrength)
			Text("Signal \(signalStrength.description)").font(.footnote)
			Text("SNR \(String(format: "%.2f", -12.75))dB")
				.foregroundColor(getSnrColor(snr: -12.75, preset: ModemPresets.longFast))
				.font(.caption2)
			Text("RSSI \(-139)dB")
				.foregroundColor(getRssiColor(rssi: -139))
				.font(.caption2)
		}
	}
}

enum LoRaSignalStrength: Int {
	case none = 0
	case bad = 1
	case fair = 2
	case good = 3
	var description: String {
		switch self {
		case .none:
			return "None"
		case .bad:
			return "Bad"
		case .fair:
			return "Fair"
		case .good:
			return "Good"
		}
	}
}

private func getColor(signalStrength: LoRaSignalStrength) -> Color {
	switch signalStrength {
	case .none:
		return Color.red
	case .bad:
		return Color.orange
	case .fair:
		return Color.yellow
	case .good:
		return Color.green
	}
}

func getLoRaSignalStrength(snr: Float, rssi: Int32, preset: ModemPresets) -> LoRaSignalStrength {
	// rssi is 0 when not available
	if rssi == 0 {
		if snr > (preset.snrLimit()) {
			return .good
		}
		if snr < (preset.snrLimit() - 7.5) {
			return .none
		}
		if snr <= (preset.snrLimit() - 5.5) {
			return .bad
		}
		return .fair
	}

	if rssi > -115 && snr > (preset.snrLimit()) {
		return .good
	} else if rssi < -126 && snr < (preset.snrLimit() - 7.5) {
		return .none
	} else if rssi <= -120 || snr <= (preset.snrLimit() - 5.5) {
		return .bad
	} else { return .fair }
}

func getRssiColor(rssi: Int32) -> Color {
	if rssi > -115 {
		/// Good
		return .green
	} else if rssi > -120 {
		/// Fair
		return .yellow
	} else if rssi > -126 {
		/// Bad
		return .orange
	} else { // None
		return .red
	}
}

func getSnrColor(snr: Float, preset: ModemPresets) -> Color {
	if snr > preset.snrLimit() {
		/// Good
		return .green
	} else if snr < preset.snrLimit() && snr > (preset.snrLimit() - 5.5) {
		/// Fair
		return .yellow
	} else if snr >= (preset.snrLimit() - 7.5) {
		/// Bad
		return .orange
	} else { return .red }
}
