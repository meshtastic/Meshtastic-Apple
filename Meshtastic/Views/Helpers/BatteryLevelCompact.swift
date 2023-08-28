//
//  BatteryIcon.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 3/24/23.
//
import SwiftUI

struct BatteryLevelCompact: View {
	var batteryLevel: Int32?
	var font: Font
	var iconFont: Font
	var color: Color

	var body: some View {
		HStack(alignment: .center, spacing: 0) {
			if batteryLevel == 100 {
				Image(systemName: "battery.100.bolt")
					.font(iconFont)
					.foregroundColor(color)
					.symbolRenderingMode(.hierarchical)
			} else if batteryLevel! < 100 && batteryLevel! > 74 {

				Image(systemName: "battery.75")
					.font(iconFont)
					.foregroundColor(color)
					.symbolRenderingMode(.hierarchical)
			} else if batteryLevel! < 75 && batteryLevel! > 49 {

				Image(systemName: "battery.50")
					.font(iconFont)
					.foregroundColor(color)
					.symbolRenderingMode(.hierarchical)
			} else if batteryLevel! < 50 && batteryLevel! > 14 {

				Image(systemName: "battery.25")
					.font(iconFont)
					.foregroundColor(color)
					.symbolRenderingMode(.hierarchical)
			} else if batteryLevel! < 15 && batteryLevel! > 0 {

				Image(systemName: "battery.0")
					.font(iconFont)
					.foregroundColor(color)
					.symbolRenderingMode(.hierarchical)
			} else if batteryLevel! == 0 {
				Image(systemName: "battery.0")
					.font(iconFont)
					.foregroundColor(.red)
					.symbolRenderingMode(.hierarchical)
			} else if batteryLevel! > 100 {
				Image(systemName: "powerplug")
					.font(iconFont)
					.foregroundColor(color)
					.symbolRenderingMode(.hierarchical)
			}
			if batteryLevel ?? 0 > 100 {
				Text("PWD")
					.font(font)
			} else if batteryLevel == 100 {
				Text("CHG")
					.font(font)
			} else {
				Text("\(batteryLevel ?? 0)%")
					.font(font)
			}
		}
	}
}

struct BatteryLevelCompact_Previews: PreviewProvider {
	static var previews: some View {
		VStack {
			BatteryLevelCompact(batteryLevel: 111, font: .footnote, iconFont: .callout, color: Color.accentColor)
			BatteryLevelCompact(batteryLevel: 100, font: .footnote, iconFont: .callout, color: Color.accentColor)
			BatteryLevelCompact(batteryLevel: 99, font: .footnote, iconFont: .callout, color: Color.accentColor)
			BatteryLevelCompact(batteryLevel: 74, font: .footnote, iconFont: .callout, color: Color.accentColor)
			BatteryLevelCompact(batteryLevel: 49, font: .footnote, iconFont: .callout, color: Color.accentColor)
			BatteryLevelCompact(batteryLevel: 14, font: .footnote, iconFont: .callout, color: Color.accentColor)
		}
	}
}
