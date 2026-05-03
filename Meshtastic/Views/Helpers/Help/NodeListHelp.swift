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
							Image(systemName: "cellularbars")
								.font(.title3)
								.foregroundColor(.accentColor)
						),
						title: String(localized: "Signal Metrics"),
						subtitle: String(localized: "SNR and RSSI values indicating the radio signal quality between nodes.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "cloud.sun.rain")
								.font(.title3)
								.foregroundColor(.accentColor)
						),
						title: String(localized: "Telemetry"),
						subtitle: String(localized: "Sensor data such as battery level, voltage, temperature, and humidity reported by the node.")
					)
					Link(destination: URL(string: "https://meshtastic.org/docs/configuration/radio/device/")!) {
						Label("Device Configuration Docs", systemImage: "doc.text")
					}
				} header: {
					Text("Node Details")
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
