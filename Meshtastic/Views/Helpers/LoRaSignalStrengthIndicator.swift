//
//  LoRaSignalStrengthIndicator.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 5/9/23.
//

import Foundation

import Foundation
import SwiftUI

struct LoRaSignalStrengthIndicator: View {
	let signalStrength: LoRaSignalStrength

	var body: some View {
		HStack {
			ForEach(0..<3) { bar in
				RoundedRectangle(cornerRadius: 3)
					.divided(amount: (CGFloat(bar) + 1) / CGFloat(3))
					.fill(getColor().opacity(bar <= signalStrength.rawValue ? 1 : 0.3))
					.frame(width: 8, height: 40)
			}
		}
	}

	private func getColor() -> Color {
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

func getLoRaSignalStrength(snr: Float, rssi: Int32) -> LoRaSignalStrength {
	
	if rssi > -115 && snr > -7 {
		return .good
	} else if rssi < -126 && snr < -15 {
		return .none
	} else if rssi <= -120 || snr <= -13 {
		return .bad
	} else  {
		return .fair
	}
}

func getRssiColor(rssi: Int32) -> Color {
	if rssi > -115 {
		/// Good
		return .green
	} else if rssi > -115 && rssi < -120 {
		/// Fair
		return .yellow
	} else if rssi > -126 {
		/// Bad
		return .orange
	} else  {
		// None
		return .red
	}
}

func getSnrColor(snr: Float) -> Color {
	if snr > -7 {
		/// Good
		return .green
	} else if snr < -7 && snr > -13 {
		/// Fair
		return .yellow
	} else if snr >= -14 {
		/// Bad
		return .orange
	} else  {
		return .red
	}
}
