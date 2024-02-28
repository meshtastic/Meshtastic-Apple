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

	@ObservedObject var node: NodeInfoEntity

	var body: some View {
		
		Divider()
		
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
			if node.snr != 0 && !node.viaMqtt {
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
			if node.telemetries?.count ?? 0 > 0 {
				Divider()
				BatteryGauge(node: node)
			}
		}
		Divider()
		HStack(alignment: .center) {
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
		}
		Divider()
	}
}
