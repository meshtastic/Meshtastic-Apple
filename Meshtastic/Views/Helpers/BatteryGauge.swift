//
//  BatteryGauge.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/28/22.
//

import SwiftUI
import Charts

struct BatteryGauge: View {
	@State var batteryLevel = 0.0
	private let minValue = 0.0
	private let maxValue = 100.00

	var body: some View {
		VStack {
			if batteryLevel > 100.0 {
				// Plugged in
				Image(systemName: "powerplug")
					.font(.largeTitle)
					.foregroundColor(.accentColor)
					.symbolRenderingMode(.hierarchical)
			} else {
				let gradient = Gradient(colors: [.red, .orange, .green])
				Gauge(value: batteryLevel, in: minValue...maxValue) {
					if batteryLevel >= 0.0 && batteryLevel < 10 {
						Label("Battery Level %", systemImage: "battery.0")
					} else if batteryLevel >= 10.0 && batteryLevel < 25.00 {
						Label("Battery Level %", systemImage: "battery.25")
					} else if batteryLevel >= 25.0 && batteryLevel < 50.00 {
						Label("Battery Level %", systemImage: "battery.50")
					} else if batteryLevel >= 50.0 && batteryLevel < 75.00 {
						Label("Battery Level %", systemImage: "battery.75")
					} else if batteryLevel >= 75.0 && batteryLevel <= 99.00 {
						Label("Battery Level %", systemImage: "battery.100")
					} else {
						Label("Battery Level %", systemImage: "battery.100.bolt")
					}
				} currentValueLabel: {
					if batteryLevel == 0.0 {
						Text("< 1%")
					} else {
						Text(Int(batteryLevel), format: .percent)
					}
				}
				.tint(gradient)
				.gaugeStyle(.accessoryCircular)
			}
		}
	}
}

struct BatteryGauge_Previews: PreviewProvider {
	static var previews: some View {
		VStack {
			BatteryGauge(batteryLevel: 0.0)
			BatteryGauge(batteryLevel: 9.0)
			BatteryGauge(batteryLevel: 24.0)
			BatteryGauge(batteryLevel: 49.0)
			BatteryGauge(batteryLevel: 74.0)
			BatteryGauge(batteryLevel: 99.0)
			BatteryGauge(batteryLevel: 100.0)
			BatteryGauge(batteryLevel: 111.0)
		}
	}
}
