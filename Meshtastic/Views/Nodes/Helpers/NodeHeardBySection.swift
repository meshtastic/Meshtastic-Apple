//
//  NodeHeardBySection.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftData
import SwiftUI

/// How each of the user's radios hears a node (feature 021, T088): hops, signal and when it
/// last heard it. Only shown when more than one radio has heard the node; with one, the node's
/// own fields already say it all.
struct NodeHeardBySection: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	let nodeNum: Int64
	/// Changes when the node is heard again, so the table refreshes with it.
	let lastHeard: Date?
	@State private var observations: [NodeObservationEntity] = []

	var body: some View {
		Group {
			if observations.count > 1 {
				Section("Heard By") {
					ForEach(observations, id: \.radioNum) { observation in
						row(observation)
					}
				}
			}
		}
		.task(id: lastHeard) { refresh() }
	}

	private func refresh() {
		let nodeNum = nodeNum
		let descriptor = FetchDescriptor<NodeObservationEntity>(
			predicate: #Predicate { $0.nodeNum == nodeNum },
			sortBy: [SortDescriptor(\.lastHeard, order: .reverse)]
		)
		observations = ((try? context.fetch(descriptor)) ?? []).filter { $0.radioNum != nodeNum }
	}

	private func radioName(_ radioNum: Int64) -> String {
		if let device = accessoryManager.connectedSession(forRadio: radioNum)?.device {
			return device.shortName ?? device.longName ?? device.name
		}
		let user = getNodeInfo(id: radioNum, context: context)?.user
		return user?.shortName ?? user?.longName ?? radioNum.toHex()
	}

	@ViewBuilder
	private func row(_ observation: NodeObservationEntity) -> some View {
		HStack {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(radioName(observation.radioNum))
						.font(.headline)
					if !accessoryManager.isRadioConnected(nodeNum: observation.radioNum) {
						Text("Offline")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				if let lastHeard = observation.lastHeard {
					Text(lastHeard, style: .relative)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			Spacer()
			VStack(alignment: .trailing, spacing: 2) {
				Text(observation.viaMqtt ? "MQTT".localized : hopsText(observation.hopsAway))
					.font(.callout)
				if !observation.viaMqtt, observation.hopsAway == 0, observation.snr != 0 || observation.rssi != 0 {
					Text("SNR \(String(format: "%.1f", observation.snr)) dB · RSSI \(observation.rssi) dBm")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}
		}
		.accessibilityElement(children: .combine)
	}

	private func hopsText(_ hops: Int32) -> String {
		hops == 0 ? "Direct".localized : String.localizedStringWithFormat("%d hops".localized, Int(hops))
	}
}
