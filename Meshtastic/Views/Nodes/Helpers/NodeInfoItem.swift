//
//  NodeInfoItem.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/9/23.
//

import SwiftUI
import CoreLocation
import MapKit

struct NodeInfoItem: View {

	var node: NodeInfoEntity
	
	enum SelectedDetail {
		case positionLog
		case nodeMap
		case deviceMetricsLog
		case environmentMetricsLog
		case detectionSensorLog
	}

	var body: some View {
		
		Divider()
		if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
			
		} else {
			
		}
		
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
		VStack(alignment: .center) {
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
			Divider()
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
		}

		VStack {
		//	List {
				if node.hasPositions {
					
					NavigationLink {
						PositionLog(node: node)
							.onAppear {
								
							 }
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
		//	}
		//	.listStyle(.plain)
		}
	}
}
