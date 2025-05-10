//
//  BatteryGauge.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/28/22.
//

import SwiftUI
import Charts

struct BatteryGauge: View {

	@ObservedObject var node: NodeInfoEntity
	private let minValue = 0.0
	private let maxValue = 100.00

	var body: some View {

		let deviceMetrics = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0"))
		let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity
		// For VoiceOver purposes, detect when device is plugged in (battery > 100%)
		let isPluggedIn = (mostRecent?.batteryLevel ?? 0) > 100
		// Use a capped battery level for UI display
		let batteryLevel = Double(min(100, mostRecent?.batteryLevel ?? 0))

		VStack {
			if isPluggedIn {
				// Use a completely standalone view for the plugged in state
				// to avoid any VoiceOver confusion
				PluggedInIndicator()
			} else {
				let gradient = Gradient(colors: [.red, .orange, .green])
				Gauge(value: batteryLevel, in: minValue...maxValue) {
					// Accessibility for battery gauge
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
				.accessibilityLabel(NSLocalizedString("Battery Level", comment: "VoiceOver label for battery gauge"))
				.accessibilityValue(String(format: NSLocalizedString("Battery Level %", comment: "VoiceOver value for battery level"), Int(batteryLevel)))
				.tint(gradient)
				.gaugeStyle(.accessoryCircular)
			}
			if mostRecent?.voltage ?? 0 > 0 {
				Text(String(format: "%.2f", mostRecent?.voltage ?? 0) + " V")
					.font(.callout)
					.foregroundColor(.gray)
					.fixedSize()
			}
		}
	}
}

/// A dedicated view for showing a device is plugged in
/// With proper VoiceOver support that matches the visual indication
struct PluggedInIndicator: View {
    var body: some View {
        // This view is isolated from any battery measurement
        // to ensure VoiceOver doesn't pick up any percentages
        Image(systemName: "powerplug")
            .font(.largeTitle)
            .foregroundColor(.accentColor)
            .symbolRenderingMode(.hierarchical)
            // Override the accessibility to ensure correct VoiceOver announcement
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NSLocalizedString("Battery Level", comment: "VoiceOver label for battery gauge"))
            .accessibilityValue(NSLocalizedString("device_plugged_in", comment: "VoiceOver value for plugged in device"))
    }
}

struct BatteryGauge_Previews: PreviewProvider {
	static var previews: some View {
		VStack {
		//	BatteryGauge(batteryLevel: 0.0)
		//	BatteryGauge(batteryLevel: 9.0)
		//	BatteryGauge(batteryLevel: 24.0)
		//	BatteryGauge(batteryLevel: 49.0)
		//	BatteryGauge(batteryLevel: 74.0)
		//	BatteryGauge(batteryLevel: 99.0)
		//	BatteryGauge(batteryLevel: 100.0)
		//	BatteryGauge(batteryLevel: 111.0)
		}
	}
}
