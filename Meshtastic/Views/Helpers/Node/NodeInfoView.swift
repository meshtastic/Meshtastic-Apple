//
//  NodeInfoView.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 4/2/23.
//

//
//  DistanceText.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/19/22.
//

import SwiftUI
import CoreLocation
import MapKit

struct NodeInfoView: View {

	var node: NodeInfoEntity

	var body: some View {
		let hwModelString = node.user?.hwModel ?? "UNSET"

		Divider()
		if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
			HStack {
				VStack(alignment: .center) {
					CircleText(text: node.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 150)
				}
				Divider()
				VStack {
					if node.user != nil {
						Image(hwModelString)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(width: 100, height: 100)
							.cornerRadius(5)

						Text(String(hwModelString))
							.foregroundColor(.gray)
							.font(.title).fixedSize()
					}
				}
				Divider()
				if node.snr != 0 {
					VStack(alignment: .center) {
						let signalStrength = getLoRaSignalStrength(snr: node.snr, rssi: node.rssi, preset: ModemPresets.longModerate)
						LoRaSignalStrengthIndicator(signalStrength: signalStrength)
						Text("Signal \(signalStrength.description)").font(.title)
						Text("SNR \(String(format: "%.2f", node.snr))dB")
							.foregroundColor(getSnrColor(snr: node.snr, preset: ModemPresets.longModerate))
							.font(.title3)
						Text("RSSI \(node.rssi)dB")
							.foregroundColor(getRssiColor(rssi: node.rssi))
							.font(.title3)
					}
					Divider()
				}
				
				if node.hasDeviceMetrics {
					let deviceMetrics = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0"))
					let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity
					VStack(alignment: .center) {
						BatteryGauge(batteryLevel: Double(mostRecent?.batteryLevel ?? 0))
						if mostRecent?.voltage ?? 0 > 0.0 {

							Text(String(format: "%.2f", mostRecent?.voltage ?? 0.0) + " V")
								.font(.title)
								.foregroundColor(.gray)
								.fixedSize()
						}
					}
					.padding()
				}
			}
			.padding()

			Divider()
			HStack(alignment: .center) {

				VStack {
					HStack {
						Image(systemName: "person")
							.font(.title)
							.foregroundColor(.accentColor)
							.symbolRenderingMode(.hierarchical)
						Text("user").font(.title)+Text(":").font(.title)
					}
					Text("!\(String(format: "%02x", node.num))")
						.font(.title).foregroundColor(.gray)
				}
				Divider()
				VStack {
					HStack {
						Image(systemName: "number")
							.font(.title2)
							.foregroundColor(.accentColor)
							.symbolRenderingMode(.hierarchical)
						Text("Node Number:").font(.title)
					}
					Text(String(node.num)).font(.title).foregroundColor(.gray)
				}
				Divider()
				VStack {
					HStack {
						Image(systemName: "clock.badge.checkmark.fill")
							.font(.title)
							.foregroundColor(.accentColor)
							.symbolRenderingMode(.hierarchical)
						Text("heard.last").font(.title)+Text(":").font(.title)

					}
					DateTimeText(dateTime: node.lastHeard)
						.font(.title3)
						.foregroundColor(.gray)
				}
			}
			Divider()

		} else {

			HStack {

				VStack(alignment: .center) {
					CircleText(text: node.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 65)
				}
				if node.user != nil {
					Divider()
					VStack {
						Image(node.user!.hwModel ?? "unset".localized)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(width: 75, height: 75)
							.cornerRadius(5)
						Text(String(node.user!.hwModel ?? "unset".localized))
							.font(.caption2).fixedSize()
					}
				}
				if node.snr != 0 {
					Divider()
					VStack(alignment: .center) {
						let signalStrength = getLoRaSignalStrength(snr: node.snr, rssi: node.rssi, preset: ModemPresets.longModerate)
						LoRaSignalStrengthIndicator(signalStrength: signalStrength)
						Text("Signal \(signalStrength.description)").font(.footnote)
						Text("SNR \(String(format: "%.2f", node.snr))dB")
							.foregroundColor(getSnrColor(snr: node.snr, preset: ModemPresets.longModerate))
							.font(.caption2)
						Text("RSSI \(node.rssi)dB")
							.foregroundColor(getRssiColor(rssi: node.rssi))
							.font(.caption2)
					}
				}
				let deviceMetrics = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0"))
				if deviceMetrics?.count ?? 0 >= 1 {
					Divider()
					let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity
					VStack(alignment: .center) {
						BatteryGauge(batteryLevel: Double(mostRecent?.batteryLevel ?? 0))
						if mostRecent?.voltage ?? 0 > 0 {

							Text(String(format: "%.2f", mostRecent?.voltage ?? 0) + " V")
								.font(.callout)
								.foregroundColor(.gray)
								.fixedSize()
						}
					}
				}
			}
			Divider()
			HStack(alignment: .center) {
				VStack {
					HStack {
						Image(systemName: "person")
							.font(.title2)
							.foregroundColor(.accentColor)
							.symbolRenderingMode(.hierarchical)
						Text("User Id:").font(.title2)
					}
					Text(node.user?.userId ?? "?").font(.title3).foregroundColor(.gray)
				}
				Divider()
				VStack {
					HStack {
						Image(systemName: "number")
							.font(.title2)
							.foregroundColor(.accentColor)
							.symbolRenderingMode(.hierarchical)
						Text("Node Number:").font(.title2)
					}
					Text(String(node.num)).font(.title3).foregroundColor(.gray)
				}
			}
			Divider()
		}

		VStack {

			if node.hasPositions{

				NavigationLink {
					PositionLog(node: node)
				} label: {

					Image(systemName: "building.columns")
						.symbolRenderingMode(.hierarchical)
						.font(.title)

					Text("Position Log")
						.font(.title3)
				}
				.fixedSize(horizontal: false, vertical: true)
				Divider()
			}

			if node.hasDeviceMetrics {
				
				NavigationLink {
					DeviceMetricsLog(node: node)
				} label: {
					
					Image(systemName: "flipphone")
						.symbolRenderingMode(.hierarchical)
						.font(.title)
					
					Text("Device Metrics Log")
						.font(.title3)
				}
				Divider()
			}
			if node.hasEnvironmentMetrics {
				NavigationLink {
					EnvironmentMetricsLog(node: node)
				} label: {

					Image(systemName: "chart.xyaxis.line")
						.symbolRenderingMode(.hierarchical)
						.font(.title)

					Text("Environment Metrics Log")
						.font(.title3)
				}
				Divider()
			}
			NavigationLink {
				DetectionSensorLog(node: node)
			} label: {

				Image(systemName: "sensor")
					.symbolRenderingMode(.hierarchical)
					.font(.title)

				Text("Detection Sensor Log")
					.font(.title3)
			}
			.fixedSize(horizontal: false, vertical: true)
				Divider()
		}
	}
}
