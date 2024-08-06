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
	@State private var currentDevice: DeviceHardware?
	@State private var deviceHardware: [DeviceHardware] = []

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
							Text(String(currentDevice?.displayName ?? (node.user?.hwModel ?? "unset".localized)))
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
					.onAppear(perform: {
						if currentDevice == nil {
							Api().loadDeviceHardwareData { (hw) in
								for device in hw {
									let currentHardware = node.user?.hwModel ?? "UNSET"
									let deviceString = device.hwModelSlug.replacingOccurrences(of: "_", with: "")
									if deviceString == currentHardware {
										currentDevice = device
									}
								}
							}
						}
					})
					.onChange(of: node) { newNode in
						Api().loadDeviceHardwareData { (hw) in
							for device in hw {
								let currentHardware = newNode.user?.hwModel ?? "UNSET"
								let deviceString = device.hwModelSlug.replacingOccurrences(of: "_", with: "")
								if deviceString == currentHardware {
									currentDevice = device
								}
							}
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
