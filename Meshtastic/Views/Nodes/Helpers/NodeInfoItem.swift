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

	@ObservedObject
	var node: NodeInfoEntity

	var modemPreset: ModemPresets = ModemPresets(
		rawValue: UserDefaults.modemPreset
	) ?? ModemPresets.longFast

	var body: some View {
		ViewThatFits(in: .horizontal) {
			HStack {
				Spacer()
				CircleText(
					text: node.user?.shortName ?? "?",
					color: Color(UIColor(hex: UInt32(node.num))),
					circleSize: 75
				)
				if let user = node.user {
					VStack(alignment: .center) {
						if user.hwModel != "UNSET" {
							Image(user.hardwareImage ?? "UNSET")
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(width: 65, height: 65)
								.cornerRadius(5)
							Text(String(node.user!.hwModel ?? "unset".localized))
								.font(.caption2)
								.frame(maxWidth: 80)
						} else {
							Image(systemName: "person.crop.circle.badge.questionmark")
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(width: 65, height: 65)
								.cornerRadius(5)
							Text(String("incomplete".localized))
								.font(.caption)
								.frame(maxWidth: 80)
						}
					}
				}
				if node.snr != 0 && !node.viaMqtt {
					VStack(alignment: .center) {
						let signalStrength = getLoRaSignalStrength(snr: node.snr, rssi: node.rssi, preset: modemPreset)
						LoRaSignalStrengthIndicator(signalStrength: signalStrength)
						Text("Signal \(signalStrength.description)").font(.footnote)
						Text("SNR \(String(format: "%.2f", node.snr))dB")
							.foregroundColor(getSnrColor(snr: node.snr, preset: modemPreset))
							.font(.caption2)
						Text("RSSI \(node.rssi)dB")
							.foregroundColor(getRssiColor(rssi: node.rssi))
							.font(.caption)
					}
					.frame(minWidth: 110, maxWidth: 175)
				}
				if node.telemetries?.count ?? 0 > 0 {
					BatteryGauge(node: node)
				}
				Spacer()
			}
		}
	}
}
