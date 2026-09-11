//
//  UnheardNodesBanner.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import SwiftUI
import SwiftData
import OSLog

enum UnheardNodesPromptCopy {
	static let reviewTitle = String(localized: "Nodes Needing Review", comment: "Title for the review sheet for nodes not heard since a radio settings change")
	static let reviewMessage = String(localized: "These nodes haven’t been heard since the radio settings changed. Favorite nodes and this radio are kept.", comment: "Explains why nodes are listed for review after a radio settings change")
	static let removeAction = String(localized: "Remove Nodes", comment: "Confirms removing nodes not heard since a radio settings change")
	static let confirmationMessage = String(localized: "Remove these nodes from this app and the connected radio? Nodes heard again later will reappear.", comment: "Explains the effect of removing nodes not heard since a radio settings change")

	static func headline(nodeCount: Int) -> String {
		let noun = nodeCount == 1 ? String(localized: "node", comment: "Singular noun in the unheard-nodes notice") : String(localized: "nodes", comment: "Plural noun in the unheard-nodes notice")
		let verb = nodeCount == 1 ? String(localized: "needs", comment: "Singular verb in the unheard-nodes notice") : String(localized: "need", comment: "Plural verb in the unheard-nodes notice")
		return String(localized: "\(nodeCount) \(noun) \(verb) review", comment: "Compact notice shown when nodes have not been heard since a radio settings change")
	}

	static func confirmationTitle(nodeCount: Int) -> String {
		let noun = nodeCount == 1 ? String(localized: "Node", comment: "Singular noun in the remove-nodes confirmation title") : String(localized: "Nodes", comment: "Plural noun in the remove-nodes confirmation title")
		return String(localized: "Remove \(nodeCount) \(noun)?", comment: "Confirmation title for removing nodes not heard since a radio settings change")
	}
}

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
	private struct NodeState: Equatable {
		let num: Int64
		let lastHeard: Date?
		let favorite: Bool
		let viaMqtt: Bool
	}

	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Query private var nodes: [NodeInfoEntity]

	@State private var unheardNodes: [NodeInfoEntity] = []
	@State private var isReviewing = false
	@State private var isConfirming = false
	@State private var isRemoving = false

	/// Resolved here rather than passed in. A parent that only builds this view once a radio is
	/// connected has to be re-evaluated when one arrives, and inside a `safeAreaInset` that
	/// evaluates during layout — before the connection is established — it simply stays empty.
	private var connectedNodeNum: Int64? { accessoryManager.activeDeviceNum }
	private var nodeState: [NodeState] {
		nodes.map { NodeState(num: $0.num, lastHeard: $0.lastHeard, favorite: $0.favorite, viaMqtt: $0.viaMqtt) }
	}

	var body: some View {
		Group {
			if let connectedNodeNum, !unheardNodes.isEmpty,
			   LoRaConfigChange.shouldOfferCleanup(forNode: connectedNodeNum) {
				content(connectedNodeNum: connectedNodeNum)
			}
		}
		.onAppear(perform: refresh)
		.onChange(of: accessoryManager.activeDeviceNum) { _, _ in refresh() }
		.onChange(of: nodeState) { _, _ in refresh() }
	}

	private func content(connectedNodeNum: Int64) -> some View {
		Button {
			isReviewing = true
		} label: {
			HStack(spacing: 12) {
				Image(systemName: "antenna.radiowaves.left.and.right.slash")
					.foregroundStyle(.orange)
					.frame(width: 24)
				VStack(alignment: .leading, spacing: 2) {
					Text(UnheardNodesPromptCopy.reviewTitle)
						.font(.callout.weight(.semibold))
					Text(UnheardNodesPromptCopy.headline(nodeCount: unheardNodes.count))
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
				Spacer()
				if isRemoving {
					ProgressView()
				} else {
					Image(systemName: "chevron.right")
						.font(.footnote.weight(.semibold))
						.foregroundStyle(.tertiary)
				}
			}
			.frame(minHeight: 44)
			.padding(.horizontal)
			.padding(.vertical, 8)
		}
		.buttonStyle(.plain)
		.disabled(isRemoving)
		.background(.bar)
		.overlay(alignment: .bottom) { Divider() }
		.sheet(isPresented: $isReviewing) {
			reviewSheet(connectedNodeNum: connectedNodeNum)
		}
	}

	private func reviewSheet(connectedNodeNum: Int64) -> some View {
		NavigationStack {
			List {
				Section {
					Text(UnheardNodesPromptCopy.reviewMessage)
				}

				Section("Nodes") {
					ForEach(unheardNodes, id: \.num) { node in
						VStack(alignment: .leading, spacing: 2) {
							Text(node.user?.longName ?? "Unknown Node")
							Text(node.num.toHex())
								.font(.footnote)
								.foregroundStyle(.secondary)
						}
					}
				}

				Section {
					Button(role: .destructive) {
						isConfirming = true
					} label: {
						Text(UnheardNodesPromptCopy.removeAction)
					}
					.disabled(isRemoving)

					Button("Keep Nodes") {
						LoRaConfigChange.dismissOffer(forNode: connectedNodeNum)
						isReviewing = false
						refresh()
					}
					.disabled(isRemoving)
				}
			}
			.navigationTitle(UnheardNodesPromptCopy.reviewTitle)
			.navigationBarTitleDisplayMode(.inline)
			.alert(
				UnheardNodesPromptCopy.confirmationTitle(nodeCount: unheardNodes.count),
				isPresented: $isConfirming
			) {
				Button(role: .destructive) {
					Task { await removeUnheardNodes(connectedNodeNum: connectedNodeNum) }
				} label: {
					Text(UnheardNodesPromptCopy.removeAction)
				}
				Button(role: .cancel) { } label: {
					Text("Cancel")
				}
			} message: {
				Text(UnheardNodesPromptCopy.confirmationMessage)
			}
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
		unheardNodes = nodes.filter {
			$0.favorite == false && $0.num != connectedNodeNum
		}.filter {
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
				unheardNodes.removeAll { $0.num == node.num }
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
