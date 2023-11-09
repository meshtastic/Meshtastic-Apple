//
//  BatteryIcon.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 3/24/23.
//
import SwiftUI

struct BatteryLevelCompact: View {
	
	@ObservedObject var node: NodeInfoEntity

	var font: Font
	var iconFont: Font
	var color: Color

	var body: some View {
		let deviceMetrics = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0"))
		let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity
		let batteryLevel = mostRecent?.batteryLevel ?? 0
		if deviceMetrics?.count ?? 0 > 0 {
			HStack(alignment: .center, spacing: 0) {
				if batteryLevel == 100 {
					Image(systemName: "battery.100.bolt")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.hierarchical)
				} else if batteryLevel < 100 && batteryLevel > 74 {
					
					Image(systemName: "battery.75")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.hierarchical)
				} else if batteryLevel < 75 && batteryLevel > 49 {
					
					Image(systemName: "battery.50")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.hierarchical)
				} else if batteryLevel < 50 && batteryLevel > 14 {
					
					Image(systemName: "battery.25")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.hierarchical)
				} else if batteryLevel < 15 && batteryLevel > 0 {
					
					Image(systemName: "battery.0")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.hierarchical)
				} else if batteryLevel == 0 {
					Image(systemName: "battery.0")
						.font(iconFont)
						.foregroundColor(.red)
						.symbolRenderingMode(.hierarchical)
				} else if batteryLevel > 100 {
					Image(systemName: "powerplug")
						.font(iconFont)
						.foregroundColor(color)
						.symbolRenderingMode(.hierarchical)
				}
				if batteryLevel > 100 {
					Text("PWD")
						.font(font)
				} else if batteryLevel == 100 {
					Text("CHG")
						.font(font)
				} else {
					Text("\(batteryLevel)%")
						.font(font)
				}
			}
		}
	}
}
