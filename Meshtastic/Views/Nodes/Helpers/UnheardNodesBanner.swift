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
/// The banner's two counted strings.
///
/// They live here rather than inline so a test can resolve exactly what the view renders.
/// Both once carried automatic grammar agreement markup, which only inflects when the
/// string catalog has a value to compile — theirs had none, so the markup reached the
/// screen. A test that restates the literal would not have noticed.
enum UnheardNodesStrings {
	static func headline(count: Int) -> String {
		String(localized: "\(count) nodes not heard since you changed settings")
	}

	/// The headline when the radio reports the answer itself (firmware 2.8.1+). It says only what the
	/// radio knows, per meshtastic/design#146: it does not know a setting changed or why.
	static func headlineOnCurrentLora(count: Int) -> String {
		String(localized: "\(count) nodes not heard on your current LoRa settings")
	}

	static func removeConfirmation(count: Int) -> String {
		String(localized: "Remove \(count) nodes?", comment: "Confirmation title for removing nodes not heard since the settings changed")
	}
}

struct UnheardNodesBanner: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager

	@State private var unheardNodes: [NodeInfoEntity] = []
	/// Nodes the radio could hear directly (not MQTT), the denominator for "most of the list".
	@State private var radioNodeCount = 0
	@State private var isConfirming = false
	@State private var isRemoving = false

	/// Resolved here rather than passed in. A parent that only builds this view once a radio is
	/// connected has to be re-evaluated when one arrives, and inside a `safeAreaInset` that
	/// evaluates during layout — before the connection is established — it simply stays empty.
	private var connectedNodeNum: Int64? { accessoryManager.activeDeviceNum }

	var body: some View {
		Group {
			if let connectedNodeNum, !unheardNodes.isEmpty, shouldOffer(connectedNodeNum: connectedNodeNum) {
				content(connectedNodeNum: connectedNodeNum)
			}
		}
		.onAppear(perform: refresh)
		.onChange(of: accessoryManager.activeDeviceNum) { _, _ in refresh() }
		// The radio's answers arrive with its node db, after the device number is known.
		.onChange(of: accessoryManager.state == .subscribed) { _, _ in refresh() }
	}

	/// On 2.8.1+ the radio answers per node, so this follows its flag instead of the app's own
	/// record of a settings change. Older firmware keeps the app-derived offer.
	private var usesRadioReport: Bool { accessoryManager.reportsHeardOnCurrentLora }

	private func shouldOffer(connectedNodeNum: Int64) -> Bool {
		if usesRadioReport {
			// One aggregate when most of the list is unheard; the rows carry the marker otherwise.
			return unheardNodes.count * 2 >= radioNodeCount
				&& UnheardOnCurrentLoraOffer.shouldOffer(count: unheardNodes.count, forNode: connectedNodeNum)
		}
		return LoRaConfigChange.shouldOfferCleanup(forNode: connectedNodeNum)
	}

	private func isStillUnheard(_ node: NodeInfoEntity, changedAt: Date?) -> Bool {
		usesRadioReport
			? node.isUnheardOnCurrentLora
			: LoRaConfigChange.isUnheard(lastHeard: node.lastHeard, viaMqtt: node.viaMqtt, changedAt: changedAt)
	}

	private func dismiss(connectedNodeNum: Int64) {
		if usesRadioReport {
			UnheardOnCurrentLoraOffer.dismiss(count: unheardNodes.count, forNode: connectedNodeNum)
		} else {
			LoRaConfigChange.dismissOffer(forNode: connectedNodeNum)
		}
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
				Text(usesRadioReport
					 ? UnheardNodesStrings.headlineOnCurrentLora(count: unheardNodes.count)
					 : UnheardNodesStrings.headline(count: unheardNodes.count))
					.font(.callout.weight(.semibold))
				Text(usesRadioReport
					 ? "Your radio has not heard them on the settings it is using now. Favorites and the connected node are kept."
					 : "They were heard on the old channel and cannot be reached from this one. Favorites and the connected node are kept.")
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
						.tint(.accentFill)

						Button {
							dismiss(connectedNodeNum: connectedNodeNum)
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
			Text(UnheardNodesStrings.removeConfirmation(count: unheardNodes.count)),
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

	/// Unheard nodes, excluding favorites and the radio itself: from the radio's own report on
	/// 2.8.1+, otherwise those heard before the recorded settings change and not since.
	private func refresh() {
		guard let connectedNodeNum else {
			unheardNodes = []
			return
		}
		let changedAt = LoRaConfigChange.changedAt(forNode: connectedNodeNum)
		guard usesRadioReport || changedAt != nil else {
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
		radioNodeCount = candidates.filter { !$0.viaMqtt }.count
		unheardNodes = candidates.filter { isStillUnheard($0, changedAt: changedAt) }
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
			guard isStillUnheard(node, changedAt: changedAt) else {
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
			dismiss(connectedNodeNum: connectedNodeNum)
		}
		refresh()
	}
}
