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
		HStack(alignment: .center, spacing: 0) {
			if let batteryLevel {
				if batteryLevel == 100 {
					Image(systemName: "battery.100.bolt")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
				} else if batteryLevel < 100 && batteryLevel > 74 {
					Image(systemName: "battery.75")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
				} else if batteryLevel < 75 && batteryLevel > 49 {
					Image(systemName: "battery.50")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
				} else if batteryLevel < 50 && batteryLevel > 14 {
					Image(systemName: "battery.25")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
				} else if batteryLevel < 15 && batteryLevel > 0 {
					Image(systemName: "battery.0")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
				} else if batteryLevel == 0 {
					Image(systemName: "battery.0")
						.font(iconFont)
						.foregroundColor(.red)
						.symbolRenderingMode(.multicolor)
				} else if batteryLevel > 100 {
					Image(systemName: "powerplug")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.multicolor)
				}
			} else {
				Image(systemName: "battery.0")
					.font(iconFont)
					.foregroundColor(color)
					.symbolRenderingMode(.multicolor)
			}
			if let batteryLevel {
				if batteryLevel > 100 {
					Text("PWD")
						.foregroundStyle(.secondary)
						.font(font)
				} else if batteryLevel == 100 {
					Text("CHG")
						.foregroundStyle(.secondary)
						.font(font)
				} else {
					Text("\(batteryLevel)%")
						.foregroundStyle(.secondary)
						.font(font)
				}
			} else {
				Text("?")
					.foregroundStyle(.secondary)
					.font(font)
			}
		}
	}
}
