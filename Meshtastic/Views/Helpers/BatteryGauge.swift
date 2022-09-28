//
//  BatteryGauge.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/28/22.
//

import SwiftUI
import Charts

struct BatteryGauge: View {
	
	@State var batteryLevel = 64.0
	
	private let minValue = 1.0
	private let maxValue = 100.00

	let gradient = Gradient(colors: [.red, .yellow, .green])

	var body: some View {
		VStack {
			Gauge(value: batteryLevel, in: minValue...maxValue) {
				Label("Battery Level %", systemImage: "battery.0")
			} currentValueLabel: {
				Text(Int(batteryLevel), format: .percent)
			}
			.tint(gradient)
		}
		.gaugeStyle(.accessoryCircular)

		.padding()
	}
}
