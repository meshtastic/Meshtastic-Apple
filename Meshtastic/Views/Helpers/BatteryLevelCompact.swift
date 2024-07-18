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
			BatteryCompact(batteryLevel: batteryLevel, font: font, iconFont: iconFont, color: color)
		}
	}
}
