//
//  LoRaSignalStrength.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 5/15/23.
//
import Foundation
import SwiftUI

struct LoRaSignalStrengthMeter: View {
	
	var snr: Float
	var rssi: Int32
	var preset: ModemPresets
	var compact: Bool
	
	var body: some View {
		
		let signalStrength = getLoRaSignalStrength(snr: snr, rssi: rssi, preset: preset)
		let gradient = Gradient(colors: [.red, .orange, .yellow, .green])
		
		if !compact {
			VStack {
				LoRaSignalStrengthIndicator(signalStrength: signalStrength)
				Text("Signal \(signalStrength.description)").font(.footnote)
				Text("SNR \(String(format: "%.2f", snr))dB")
					.foregroundColor(getSnrColor(snr: snr, preset: ModemPresets.longFast))
					.font(.caption2)
				Text("RSSI \(rssi)dB")
					.foregroundColor(getRssiColor(rssi: rssi))
					.font(.caption2)
			}
		} else {
			Gauge(value: Double(signalStrength.rawValue), in: 0...3) {
			} currentValueLabel: {
				Image(systemName: "dot.radiowaves.left.and.right")
					.font(.caption)
				Text("Signal \(signalStrength.description)")
					.font(.caption)
			}
			.gaugeStyle(.accessoryLinear)
			.tint(gradient)
			.font(.caption)
		}
	}
}

struct LoRaSignalStrengthMeter_Previews: PreviewProvider {
	static var previews: some View {
		VStack {
			LoRaSignalStrengthMeter(snr: -10, rssi: -100, preset: ModemPresets.longFast, compact: false)
			LoRaSignalStrengthMeter(snr: -17.5, rssi: -100, preset: ModemPresets.longFast, compact: false)
			LoRaSignalStrengthMeter(snr: -12.75, rssi: -139, preset: ModemPresets.longFast, compact: false)
			LoRaSignalStrengthMeter(snr: -20.25, rssi: -128, preset: ModemPresets.longFast, compact: false)
			LoRaSignalStrengthMeter(snr: -30, rssi: -128, preset: ModemPresets.longFast, compact: false)
		}
		VStack {
			LoRaSignalStrengthMeter(snr: -10, rssi: -100, preset: ModemPresets.longFast, compact: true)
				.padding(.bottom)
			LoRaSignalStrengthMeter(snr: -17.5, rssi: -100, preset: ModemPresets.longFast, compact: true)
				.padding(.bottom)
			LoRaSignalStrengthMeter(snr: -12.75, rssi: -139, preset: ModemPresets.longFast, compact: true)
				.padding(.bottom)
			LoRaSignalStrengthMeter(snr: -20.25, rssi: -128, preset: ModemPresets.longFast, compact: true)
				.padding(.bottom)
			LoRaSignalStrengthMeter(snr: -30, rssi: -128, preset: ModemPresets.longFast, compact: true)
		}
		.padding()
	}
}


