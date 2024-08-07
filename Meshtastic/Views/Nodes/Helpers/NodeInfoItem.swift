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

	var modemPreset: ModemPresets = ModemPresets(
		rawValue: UserDefaults.modemPreset
	) ?? ModemPresets.longFast

	var body: some View {
		ViewThatFits(in: .horizontal) {
			VStack {
				if let user = node.user {
					HStack(alignment: .center) {
						if user.hwModel != "UNSET" {
							Image(user.hardwareImage ?? "UNSET")
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(width: 65, height: 65)
								.cornerRadius(5)
							Text(String(node.user?.hwDisplayName ?? (node.user?.hwModel ?? "unset".localized)))
								.font(.callout)
						} else {
							Image(systemName: "person.crop.circle.badge.questionmark")
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(width: 65, height: 65)
								.cornerRadius(5)
							Text(String("incomplete".localized))
								.font(.callout)
						}
					}
				}
				HStack(alignment: .center) {
					Spacer()
					CircleText(
						text: node.user?.shortName ?? "?",
						color: Color(UIColor(hex: UInt32(node.num))),
						circleSize: 75
					)
					if node.snr != 0 && !node.viaMqtt {
						Spacer()
						VStack {
							let signalStrength = getLoRaSignalStrength(snr: node.snr, rssi: node.rssi, preset: modemPreset)
							LoRaSignalStrengthIndicator(signalStrength: signalStrength)
							Text("Signal \(signalStrength.description)").font(.footnote)
							Text("SNR \(String(format: "%.2f", node.snr))dB")
								.foregroundColor(getSnrColor(snr: node.snr, preset: modemPreset))
								.font(.caption)
							Text("RSSI \(node.rssi)dB")
								.foregroundColor(getRssiColor(rssi: node.rssi))
								.font(.caption)
						}
					}
					if node.telemetries?.count ?? 0 > 0 {
						Spacer()
						BatteryGauge(node: node)
					}
					Spacer()
				}
			}
		}
	}
}
