//
//  UnheardNodesBanner.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import SwiftUI
import SwiftData
import OSLog

/// Offered after the radio's LoRa settings move it to a different channel.
///
/// The node db does not move with the radio: every node in the list was heard on the old channel and
/// has no channel in common with this radio any more. Sends to them fail, and for channel broadcasts
/// they fail silently, because a broadcast carries no ack.
///
/// Only ever an offer. The client node db is deliberately a superset of the radio's, so nothing is
/// removed without the user asking — a node may simply be out of range rather than on another preset,
/// and it comes back on its own when it is next heard.
struct UnheardNodesBanner: View {
	let connectedNodeNum: Int64
	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager

	@State private var unheardNodes: [NodeInfoEntity] = []
	@State private var isConfirming = false
	@State private var isRemoving = false

	var body: some View {
		Group {
			if !unheardNodes.isEmpty, LoRaConfigChange.shouldOfferCleanup(forNode: connectedNodeNum) {
				content
			}
		}
		.onAppear(perform: refresh)
		.onChange(of: accessoryManager.activeDeviceNum) { _, _ in refresh() }
	}

	private var content: some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: "antenna.radiowaves.left.and.right.slash")
				.font(.title3)
				.foregroundStyle(.orange)

			VStack(alignment: .leading, spacing: 6) {
				// The honest claim: we know we have not heard them since the settings changed. We
				// cannot know they moved to another preset — a radio cannot observe a channel it is
				// not tuned to.
				Text("^[\(unheardNodes.count) node](inflect: true) not heard since you changed settings")
					.font(.callout.weight(.semibold))
				Text("They were heard on the old channel and cannot be reached from this one. Favorites and the connected node are kept.")
					.font(.caption)
					.foregroundStyle(.secondary)

				HStack {
					Button(role: .destructive) {
						isConfirming = true
					} label: {
						Text("Remove Them")
					}
					.buttonStyle(.borderedProminent)
					.disabled(isRemoving)

					Button {
						LoRaConfigChange.dismissOffer(forNode: connectedNodeNum)
						refresh()
					} label: {
						Text("Keep")
					}
					.buttonStyle(.bordered)
					.disabled(isRemoving)
				}
				.controlSize(.small)
			}
			Spacer(minLength: 0)
		}
		.padding(12)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.padding(.horizontal)
		.padding(.bottom, 4)
		.confirmationDialog(
			Text("Remove ^[\(unheardNodes.count) node](inflect: true)?", comment: "Confirmation title for removing nodes not heard since the settings changed"),
			isPresented: $isConfirming,
			titleVisibility: .visible
		) {
			Button(role: .destructive) {
				Task { await removeUnheardNodes() }
			} label: {
				Text("Remove", comment: "Confirms removing nodes not heard since the settings changed")
			}
			Button(role: .cancel) { } label: {
				Text("Cancel")
			}
		} message: {
			Text("They are removed from this app and from the radio. Any that are still out there come back when they are next heard.")
		}
	}

	/// Nodes heard before the change and not since, excluding favorites and the radio itself.
	private func refresh() {
		guard let changedAt = LoRaConfigChange.changedAt(forNode: connectedNodeNum) else {
			unheardNodes = []
			return
		}
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.favorite == false && $0.num != connectedNodeNum }
		)
		let candidates = (try? context.fetch(descriptor)) ?? []
		unheardNodes = candidates.filter {
			LoRaConfigChange.isUnheard(lastHeard: $0.lastHeard, viaMqtt: $0.viaMqtt, changedAt: changedAt)
		}
	}

	private func removeUnheardNodes() async {
		isRemoving = true
		defer { isRemoving = false }

		var removed = 0
		for node in unheardNodes {
			do {
				try await accessoryManager.removeNode(node: node, connectedNodeNum: connectedNodeNum)
				removed += 1
			} catch {
				// Keep going: one node the radio refuses should not strand the rest, and whatever
				// survives is still listed and offered again.
				Logger.data.error("Could not remove unheard node \(node.num.toHex(), privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
		Logger.data.info("Removed \(removed, privacy: .public) of \(unheardNodes.count, privacy: .public) nodes not heard since the channel changed")

		LoRaConfigChange.dismissOffer(forNode: connectedNodeNum)
		refresh()
	}
}
