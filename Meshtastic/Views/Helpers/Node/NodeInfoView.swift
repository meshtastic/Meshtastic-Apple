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
					CircleText(text: node.user?.shortName ?? "???", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 75, fontSize: (node.user?.shortName ?? "???").isEmoji() ? 48 : 24, textColor: UIColor(hex: UInt32(node.num)).isLight() ? .black : .white )
				}
				Divider()
				VStack {
					if node.user != nil {
						Image(hwModelString)
							.resizable()
							.aspectRatio(contentMode: .fill)
							.frame(width: 100, height: 100)
							.cornerRadius(5)

						Text(String(hwModelString))
							.foregroundColor(.gray)
							.font(.title).fixedSize()
					}
				}

				if node.snr > 0 {
					Divider()
					VStack(alignment: .center) {

						Image(systemName: "waveform.path")
							.font(.title)
							.foregroundColor(.accentColor)
							.symbolRenderingMode(.hierarchical)
							.padding(.bottom, 10)
						Text("SNR").font(.largeTitle).fixedSize()
						Text("\(String(format: "%.2f", node.snr)) dB")
							.font(.largeTitle)
							.foregroundColor(.gray)
							.fixedSize()
						
						if (node.rssi > -115) && (node.snr <= -13) {
							Image(systemName: "waveform.slash")
								.font(.title)
								.foregroundColor(.orange)
								.symbolRenderingMode(.hierarchical)
							Text("Noisy Environment")
								.font(.title3)
								.foregroundColor(.orange)
								.multilineTextAlignment(.center)
						}
					}
					
				}
				let deviceMetrics = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0"))
				if deviceMetrics?.count ?? 0 >= 1 {
					
					let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity
					Divider()
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
						Image(systemName: "globe")
							.font(.title)
							.foregroundColor(.accentColor)
							.symbolRenderingMode(.hierarchical)
						Text("MAC Address: ").font(.title)

					}
					Text(String(node.user?.macaddr?.macAddressString ?? "not a valid mac address"))
						.font(.title)
						.foregroundColor(.gray)
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
					CircleText(text: node.user?.shortName ?? "???", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 65, fontSize: (node.user?.shortName ?? "???").isEmoji() ? 40 : 24, textColor: UIColor(hex: UInt32(node.num)).isLight() ? .black : .white )
				}
				Divider()
				VStack {
					if node.user != nil {
						Image(node.user!.hwModel ?? "unset".localized)
							.resizable()
							.frame(width: 75, height: 75)
							.cornerRadius(5)
						Text(String(node.user!.hwModel ?? "unset".localized))
							.font(.caption).fixedSize()
					}
				}

				if node.snr > 0 {
					Divider()
					VStack(alignment: .center) {

						Image(systemName: "waveform.path")
							.font(.title)
							.foregroundColor(.accentColor)
							.symbolRenderingMode(.hierarchical)
						Text("SNR").font(.title2).fixedSize()
						Text("\(String(format: "%.2f", node.snr)) dB")
							.font(.title2)
							.foregroundColor(.gray)
							.fixedSize()
						
						if (node.rssi > -115) && (node.snr <= -13) {
							Image(systemName: "waveform.slash")
								.font(.callout)
								.foregroundColor(.orange)
								.symbolRenderingMode(.hierarchical)
							Text("Noisy Environment")
								.font(.caption2)
								.multilineTextAlignment(.center)
								.foregroundColor(.orange)
						}
					}
				}

				let deviceMetrics = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0"))
				if deviceMetrics?.count ?? 0 >= 1 {
					
					let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity
					Divider()
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
					Text(node.user?.userId ?? "??????").font(.title3).foregroundColor(.gray)
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
			HStack {
				Image(systemName: "globe")
					.font(.headline)
					.foregroundColor(.accentColor)
					.symbolRenderingMode(.hierarchical)
				Text("MAC Address: ")
				Text(String(node.user?.macaddr?.macAddressString ?? "not a valid mac address")).foregroundColor(.gray)
			}
			.padding([.bottom], 10)
			Divider()
		}

		VStack {

			if (node.positions?.count ?? 0) > 0 {

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

			if (node.telemetries?.count ?? 0) > 0 {

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
		}
	}
}
struct NodeInfoView_Previews: PreviewProvider {
	static var previews: some View {

		VStack {
			
		}
	}
}
