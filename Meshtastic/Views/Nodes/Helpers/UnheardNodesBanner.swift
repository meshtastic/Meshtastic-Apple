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
	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager

	@State private var unheardNodes: [NodeInfoEntity] = []
	@State private var isConfirming = false
	@State private var isRemoving = false

	/// Resolved here rather than passed in. A parent that only builds this view once a radio is
	/// connected has to be re-evaluated when one arrives, and inside a `safeAreaInset` that
	/// evaluates during layout — before the connection is established — it simply stays empty.
	private var connectedNodeNum: Int64? { accessoryManager.activeDeviceNum }

	var body: some View {
		Group {
			if let connectedNodeNum, !unheardNodes.isEmpty,
			   LoRaConfigChange.shouldOfferCleanup(forNode: connectedNodeNum) {
				content(connectedNodeNum: connectedNodeNum)
			}
		}
		.onAppear(perform: refresh)
		.onChange(of: accessoryManager.activeDeviceNum) { _, _ in refresh() }
	}

	private func content(connectedNodeNum: Int64) -> some View {
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

				if isRemoving {
					// One admin message per node, so a large cleanup takes a while. The count in the
					// headline ticks down as nodes are removed.
					HStack(spacing: 8) {
						ProgressView()
						Text("Removing…")
							.font(.callout)
							.foregroundStyle(.secondary)
					}
					.frame(minHeight: 48)
				} else {
					HStack(spacing: 12) {
						Button(role: .destructive) {
							isConfirming = true
						} label: {
							Text("Remove Them")
								.frame(minWidth: 48, minHeight: 48)
						}
						.buttonStyle(.borderedProminent)

						Button {
							LoRaConfigChange.dismissOffer(forNode: connectedNodeNum)
							refresh()
						} label: {
							Text("Keep")
								.frame(minWidth: 48, minHeight: 48)
						}
						.buttonStyle(.bordered)
					}
				}
			}
			Spacer(minLength: 0)
		}
		.padding(12)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.padding(.horizontal)
		.padding(.bottom, 4)
		.confirmationDialog(
			// Resolved through String(localized:) first: the Text(_:comment:) initializer showed the
			// inflection markup literally in the dialog title on device — "^[117 node](inflect: true)".
			Text(verbatim: String(localized: "Remove ^[\(unheardNodes.count) node](inflect: true)?", comment: "Confirmation title for removing nodes not heard since the settings changed")),
			isPresented: $isConfirming,
			titleVisibility: .visible
		) {
			Button(role: .destructive) {
				Task { await removeUnheardNodes(connectedNodeNum: connectedNodeNum) }
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
		guard let connectedNodeNum else {
			unheardNodes = []
			return
		}
		guard let changedAt = LoRaConfigChange.changedAt(forNode: connectedNodeNum) else {
			unheardNodes = []
			return
		}
		// Bound to a local first: a #Predicate that reaches through self for the node number throws
		// at fetch time, and the failure is invisible — it just yields no nodes and no banner.
		let excludedNum = connectedNodeNum
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.favorite == false && $0.num != excludedNum }
		)
		let candidates: [NodeInfoEntity]
		do {
			candidates = try context.fetch(descriptor)
		} catch {
			Logger.data.error("Could not read nodes to flag after a channel change: \(error.localizedDescription, privacy: .public)")
			unheardNodes = []
			return
		}
		unheardNodes = candidates.filter {
			LoRaConfigChange.isUnheard(lastHeard: $0.lastHeard, viaMqtt: $0.viaMqtt, changedAt: changedAt)
		}
	}

	private func removeUnheardNodes(connectedNodeNum: Int64) async {
		isRemoving = true
		defer { isRemoving = false }

		// The list was built when the banner appeared. A node can be heard again between then and the
		// confirmation, and removing one that has just come back is the one outcome worth avoiding
		// here — so each is re-checked against the current lastHeard rather than trusted.
		let changedAt = LoRaConfigChange.changedAt(forNode: connectedNodeNum)
		var removed = 0
		var failed = 0
		var recovered = 0

		for node in unheardNodes {
			guard LoRaConfigChange.isUnheard(
				lastHeard: node.lastHeard, viaMqtt: node.viaMqtt, changedAt: changedAt
			) else {
				recovered += 1
				continue
			}
			do {
				try await accessoryManager.removeNode(node: node, connectedNodeNum: connectedNodeNum)
				removed += 1
			} catch {
				// Keep going: one node the radio refuses should not strand the rest.
				failed += 1
				Logger.data.error("Could not remove unheard node \(node.num.toHex(), privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
		Logger.data.info("Removed \(removed, privacy: .public) nodes not heard since the channel changed, \(failed, privacy: .public) failed, \(recovered, privacy: .public) heard again before removal")

		// Only stand the offer down once nothing is left to remove. Dismissing after a partial
		// failure would hide the banner and take the retry with it.
		if failed == 0 {
			LoRaConfigChange.dismissOffer(forNode: connectedNodeNum)
		}
		refresh()
	}
}
