//
//  BatteryLevel.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 3/24/23.
//
import SwiftUI

struct BatteryIcon: View {
	var batteryLevel: Int32?
	var font: Font
	var color: Color

	var body: some View {
		// A nil level renders nothing; the old force-unwrap chain crashed on it.
		if let batteryLevel {
			Image(systemName: symbolName(for: batteryLevel))
				.font(font)
				.foregroundColor(batteryLevel == 0 ? .red : color)
				.symbolRenderingMode(.hierarchical)
		}
	}

	private func symbolName(for level: Int32) -> String {
		switch level {
		case 101...:
			return "powerplug"
		case 100:
			return "battery.100.bolt"
		case 75...99:
			return "battery.75"
		case 50...74:
			return "battery.50"
		case 15...49:
			return "battery.25"
		default:
			return "battery.0"
		}
	}
}

struct BatteryIcon_Previews: PreviewProvider {
	static var previews: some View {
		BatteryIcon(batteryLevel: 111, font: .title2, color: Color.accentColor)
			.previewLayout(.fixed(width: 75, height: 75))
		BatteryIcon(batteryLevel: 100, font: .title2, color: Color.accentColor)
			.previewLayout(.fixed(width: 75, height: 75))
		BatteryIcon(batteryLevel: 99, font: .title2, color: Color.accentColor)
			.previewLayout(.fixed(width: 75, height: 75))
		BatteryIcon(batteryLevel: 74, font: .title2, color: Color.accentColor)
			.previewLayout(.fixed(width: 75, height: 75))
		BatteryIcon(batteryLevel: 49, font: .title2, color: Color.accentColor)
			.previewLayout(.fixed(width: 75, height: 75))
		BatteryIcon(batteryLevel: 14, font: .title2, color: Color.accentColor)
			.previewLayout(.fixed(width: 75, height: 75))
	}
}
