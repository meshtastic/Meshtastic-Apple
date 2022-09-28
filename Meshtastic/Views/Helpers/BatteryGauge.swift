//
//  BatteryGauge.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/28/22.
//

import SwiftUI
import Charts

struct BatteryGauge: View {
	
	@State var batteryLevel = 0.0
	
	private let minValue = 1.0
	private let maxValue = 100.00

	var body: some View {
		VStack {
			
			if batteryLevel == 0.0 {
				// Plugged in
				Image(systemName: "powerplug")
					.font(.largeTitle)
					.foregroundColor(.accentColor)
					.symbolRenderingMode(.hierarchical)
			} else {
				
				Gauge(value: batteryLevel, in: minValue...maxValue) {
					if batteryLevel > 1.0 && batteryLevel <= 9 {
						Label("Battery Level %", systemImage: "battery.0")
					} else if batteryLevel > 10.0 && batteryLevel <= 25.00 {
						Label("Battery Level %", systemImage: "battery.25")
					} else if batteryLevel > 26.0 && batteryLevel <= 50.00 {
						Label("Battery Level %", systemImage: "battery.50")
					} else if batteryLevel > 51.0 && batteryLevel <= 75.00 {
						Label("Battery Level %", systemImage: "battery.50")
					} else {
						Label("Battery Level %", systemImage: "battery.100")
					}
				} currentValueLabel: {
					Text(Int(batteryLevel), format: .percent)
				}
				.tint(.green)
				.gaugeStyle(.accessoryCircular)
			}
		}
	}
}
