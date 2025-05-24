//
//  BatteryCompact.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 7/18/24.
//
import SwiftUI

struct BatteryCompact: View {
	var batteryLevel: Int32?
	var font: Font
	var iconFont: Font
	var color: Color

	var body: some View {
		// Group the battery icon and label in a single accessible container
		HStack(alignment: .center, spacing: 0) {
			if let batteryLevel {
				// Check for plugged in state
				let isPluggedIn = batteryLevel > 100
				let isCharging = batteryLevel == 100
				// Battery icon selection based on level
				if isPluggedIn {
					Image(systemName: "powerplug")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
						.accessibilityHidden(true) // Hide from VoiceOver since container will handle it
				} else if isCharging {
					Image(systemName: "battery.100.bolt")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
						.accessibilityHidden(true)
				} else if batteryLevel > 74 {
					Image(systemName: "battery.75")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
						.accessibilityHidden(true)
				} else if batteryLevel > 49 {
					Image(systemName: "battery.50")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
						.accessibilityHidden(true)
				} else if batteryLevel > 14 {
					Image(systemName: "battery.25")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
						.accessibilityHidden(true)
				} else if batteryLevel > 0 {
					Image(systemName: "battery.0")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
						.accessibilityHidden(true)
				} else {
					Image(systemName: "battery.0")
						.font(iconFont)
						.foregroundColor(.red)
						.symbolRenderingMode(.multicolor)
						.accessibilityHidden(true)
				}
				// Battery text label
				if isPluggedIn {
					Text("PWD")
						.foregroundStyle(.secondary)
						.font(font)
						.accessibilityHidden(true)
				} else if isCharging {
					Text("CHG")
						.foregroundStyle(.secondary)
						.font(font)
						.accessibilityHidden(true)
				} else {
					Text(verbatim: "\(batteryLevel.formatted(.number.precision(.fractionLength(0))))%")
						.foregroundStyle(.secondary)
						.font(font)
						.accessibilityHidden(true)
				}
			} else {
				// Unknown battery state
				Image(systemName: "battery.0")
					.font(iconFont)
					.foregroundColor(color)
					.symbolRenderingMode(.multicolor)
					.accessibilityHidden(true)
				Text(verbatim: "?")
					.foregroundStyle(.secondary)
					.font(font)
					.accessibilityHidden(true)
			}
		}
		// Setup container-level accessibility for VoiceOver
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(NSLocalizedString("Battery Level", comment: "VoiceOver label for battery gauge"))
		// Set appropriate value based on the battery state using a computed property
		.accessibilityValue(batteryLevel.map { level in
		if level > 100 {
				// Plugged in - same as PWD visual indicator
			return "Plugged in".localized
			} else if level == 100 {
				// Charging - same as CHG visual indicator
				return "Charging".localized
			} else {
				// Normal battery level
				return String(format: NSLocalizedString("Battery Level %", comment: "VoiceOver value for battery level"), Int(level))
			}
		} ?? "Unknown")
	}
}
