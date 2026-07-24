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
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(String(localized: "Signal strength", comment: "VoiceOver label for the signal strength indicator"))
		.accessibilityValue(signalStrength.description)
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

enum LoRaSignalStrength: Int, Comparable {
	case none = 0
	case bad = 1
	case fair = 2
	case good = 3
	var description: String {
		switch self {
		case .none:
			return "None".localized
		case .bad:
			return "Bad".localized
		case .fair:
			return "Fair".localized
		case .good:
			return "Good".localized
		}
	}
	/// The color for this tier. Exposed so the bar indicator and any accompanying
	/// SNR text can be driven from the *same* rating and never disagree.
	var color: Color {
		getColor(signalStrength: self)
	}
	static func < (lhs: LoRaSignalStrength, rhs: LoRaSignalStrength) -> Bool {
		lhs.rawValue < rhs.rawValue
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

/// Single source of truth for the 4-tier signal rating: how far a signal-to-noise
/// margin sits above (or below) the preset's demodulation floor. `snrMargin` is
/// `snr - preset.snrLimit()` in dB. Both the bar indicator and the SNR text color
/// derive from this, so they can never disagree on the same reading.
func signalQuality(snrMargin: Float) -> LoRaSignalStrength {
	if snrMargin > 0 {
		return .good
	} else if snrMargin > -5.5 {
		return .fair
	} else if snrMargin >= -7.5 {
		return .bad
	} else {
		return .none
	}
}

/// Rates link quality for a directly-received packet.
///
/// Primary signal is the reported packet SNR relative to the preset's demodulation
/// floor. When the *receiving* node has a recent noise-floor reading (from Local
/// Stats telemetry, `DeviceMetrics.noise_floor`), we also derive a second SNR
/// estimate from the real link margin (`rssi - noiseFloor`) and take the more
/// conservative of the two tiers — this is more accurate than trusting a single
/// estimate. When no noise floor is available, fall back to the original guessed
/// fixed RSSI thresholds (-115/-120/-126) combined with SNR, rather than trusting
/// SNR alone: without a noise floor reading there's no way to tell whether a
/// decent SNR corresponds to a genuinely weak link, so RSSI stays part of the
/// check as an (imprecise but useful) sanity floor.
func getLoRaSignalStrength(snr: Float, rssi: Int32, preset: ModemPresets, noiseFloor: Int32? = nil) -> LoRaSignalStrength {
	let limit = preset.snrLimit()

	if let noiseFloor, noiseFloor != 0, rssi != 0 {
		let snrTier = signalQuality(snrMargin: snr - limit)
		let rssiTier = signalQuality(snrMargin: Float(rssi - noiseFloor) - limit)
		return min(snrTier, rssiTier)
	}
	return legacyRssiSnrRating(snr: snr, rssi: rssi, preset: preset)
}

/// The pre-noise-floor rating: guessed fixed RSSI thresholds combined with SNR relative to the
/// preset's demodulation floor. Kept as the fallback for nodes without a recent noise-floor
/// reading, since some RSSI-based sanity check is more accurate than none.
private func legacyRssiSnrRating(snr: Float, rssi: Int32, preset: ModemPresets) -> LoRaSignalStrength {
	// rssi is 0 when not available
	if rssi == 0 {
		return signalQuality(snrMargin: snr - preset.snrLimit())
	}
	if rssi > -115 && snr > (preset.snrLimit()) {
		return .good
	} else if rssi < -126 && snr < (preset.snrLimit() - 7.5) {
		return .none
	} else if rssi <= -120 || snr <= (preset.snrLimit() - 5.5) {
		return .bad
	} else {
		return .fair
	}
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
	// SNR-only rating, shared with the bar indicator via signalQuality() so the
	// two surfaces can never disagree.
	signalQuality(snrMargin: snr - preset.snrLimit()).color
}
