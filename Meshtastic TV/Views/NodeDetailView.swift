//
//  NodeDetailView.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Minimal node detail. No distance-to-me / bearing (no device GPS on tvOS).
//

import SwiftUI

struct NodeDetailView: View {
	let node: MeshNode

	var body: some View {
		Form {
			Section("Identity") {
				LabeledContent("Name", value: node.displayName)
				if !node.shortName.isEmpty {
					LabeledContent("Short", value: node.shortName)
				}
				LabeledContent("Node", value: String(format: "!%08x", node.num))
				if let role = node.role {
					LabeledContent("Role", value: role)
				}
				if let hwModel = node.hwModel {
					LabeledContent("Hardware", value: hwModel)
				}
			}

			Section("Status") {
				if let battery = node.batteryLevel {
					LabeledContent("Battery", value: "\(battery)%")
				}
				if let snr = node.snr {
					LabeledContent("SNR", value: String(format: "%.1f dB", snr))
				}
				if let lastHeard = node.lastHeard {
					LabeledContent("Last heard", value: lastHeard.formatted(.relative(presentation: .named)))
				}
			}

			if let latitude = node.latitude, let longitude = node.longitude {
				Section("Position") {
					LabeledContent("Latitude", value: String(format: "%.5f", latitude))
					LabeledContent("Longitude", value: String(format: "%.5f", longitude))
				}
			}
		}
		.navigationTitle(node.displayName)
	}
}
