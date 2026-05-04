//
//  NodeListHelp.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2025.
//

import SwiftUI

struct NodeListHelp: View {
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			List {
				Section {
					HelpItem(
						symbol: AnyView(
							CircleText(text: "🏂", color: Color(hex: "#67EA94"))
						),
						title: String(localized: "Short Name & Long Name"),
						subtitle: String(localized: "Each node has a short name (up to 4 bytes) shown in the colored circle, and a long name displayed next to it. The circle color is based on the node number. The short name can be an emoji or initials.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "checkmark.circle.fill")
								.font(.title3)
								.foregroundColor(.green)
						),
						title: String(localized: "Online"),
						subtitle: String(localized: "The node has been heard recently and is considered online.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "moon.fill")
								.font(.title3)
								.foregroundColor(.orange)
						),
						title: String(localized: "Idle / Sleeping"),
						subtitle: String(localized: "The node has not been heard from recently and may be asleep or out of range.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "hare")
								.font(.title3)
								.foregroundColor(.secondary)
						),
						title: String(localized: "Hops Away"),
						subtitle: String(localized: "The number of intermediate nodes relaying messages between you and this node. No hops means direct communication.")
					)
				} header: {
					Text("Node Status")
				}
				LockLegend()
				Section {
					ForEach(DeviceRoles.allCases) { role in
						HelpItem(
							symbol: AnyView(
								Image(systemName: role.systemName)
									.font(.title3)
									.foregroundColor(.accentColor)
							),
							title: role.name,
							subtitle: role.description
						)
					}
					Link(destination: URL(string: "https://meshtastic.org/blog/choosing-the-right-device-role/")!) {
						Label("Choosing the Right Device Role", systemImage: "doc.text")
					}
				} header: {
					Text("Device Roles")
				}
				Section {
					HelpItem(
						symbol: AnyView(
							Image(systemName: "location.fill")
								.font(.title3)
								.foregroundColor(.accentColor)
						),
						title: String(localized: "Distance & Bearing"),
						subtitle: String(localized: "Shows direction and distance to a node based on GPS positions. Requires both your device and the remote node to share location.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "2.circle.fill")
								.font(.title3)
								.foregroundColor(.accentColor)
						),
						title: String(localized: "Channel"),
						subtitle: String(localized: "The numbered circle indicates which channel the node is using. Only shown when the node is on a secondary channel (not the primary channel 0).")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "dot.radiowaves.left.and.right")
								.font(.title3)
								.foregroundColor(.green)
						),
						title: String(localized: "Signal: Good"),
						subtitle: String(localized: "SNR is above the limit for the current modem preset. Strong, reliable signal.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "dot.radiowaves.left.and.right")
								.font(.title3)
								.foregroundColor(.yellow)
						),
						title: String(localized: "Signal: Fair"),
						subtitle: String(localized: "SNR is slightly below the modem preset limit. Connection may be intermittent.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "dot.radiowaves.left.and.right")
								.font(.title3)
								.foregroundColor(.orange)
						),
						title: String(localized: "Signal: Bad"),
						subtitle: String(localized: "SNR is well below the modem preset limit. Expect packet loss and unreliable delivery.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "dot.radiowaves.left.and.right")
								.font(.title3)
								.foregroundColor(.red)
						),
						title: String(localized: "Signal: Very Bad"),
						subtitle: String(localized: "SNR is far below the modem preset limit. Communication is unlikely at this signal level.")
					)
					HelpItem(
						symbol: AnyView(
							Gauge(value: 2.0, in: 0...3) {
							}
							.gaugeStyle(.accessoryLinear)
							.tint(Gradient(colors: [.red, .orange, .yellow, .green]))
							.frame(width: 32)
						),
						title: String(localized: "Signal Strength Meter"),
						subtitle: String(localized: "The gradient bar in the Complete layout shows overall signal quality from red (no signal) through orange, yellow, to green (good signal). It combines SNR and RSSI relative to your modem preset.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "flipphone")
								.font(.title3)
								.foregroundColor(.accentColor)
						),
						title: String(localized: "Device Metrics"),
						subtitle: String(localized: "Battery level, voltage, channel utilization, and airtime reported by the node.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "mappin.and.ellipse")
								.font(.title3)
								.foregroundColor(.accentColor)
						),
						title: String(localized: "Positions"),
						subtitle: String(localized: "GPS position data reported by the node including latitude, longitude, and altitude.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "cloud.sun.rain")
								.font(.title3)
								.foregroundColor(.accentColor)
						),
						title: String(localized: "Environment"),
						subtitle: String(localized: "Sensor data such as temperature, humidity, and barometric pressure reported by the node.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "sensor")
								.font(.title3)
								.foregroundColor(.accentColor)
						),
						title: String(localized: "Detection Sensor"),
						subtitle: String(localized: "Detection sensor events reported by the node, such as motion or door open/close alerts.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "signpost.right.and.left")
								.font(.title3)
								.foregroundColor(.accentColor)
						),
						title: String(localized: "Trace Routes"),
						subtitle: String(localized: "Recorded trace route paths showing the hops a message took through the mesh to reach this node.")
					)
					Link(destination: URL(string: "https://meshtastic.org/docs/configuration/radio/device/")!) {
						Label("Device Configuration Docs", systemImage: "doc.text")
					}
				} header: {
					Text("Logs")
				}
			}
			.navigationTitle("Node List Help")
			.navigationBarTitleDisplayMode(.inline)
#if targetEnvironment(macCatalyst)
			Spacer()
			Button {
				dismiss()
			} label: {
				Label("Close", systemImage: "xmark")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.bottom)
#endif
		}
		.presentationDetents([.large])
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .large))
	}
}

struct NodeListHelpPreviews: PreviewProvider {
	static var previews: some View {
		NodeListHelp()
	}
}
