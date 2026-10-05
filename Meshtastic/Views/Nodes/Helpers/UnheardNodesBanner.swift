//
//  UnheardNodesBanner.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import SwiftUI
import SwiftData
import OSLog

/// Offered when most of the node list is nodes the radio has not heard on its current LoRa settings
/// (NodeInfo.heard_on_current_lora, firmware 2.8.1+, meshtastic/design#146).
///
/// After a preset, region or frequency slot change the node db does not move with the radio, and
/// sends to those nodes fail, silently for channel broadcasts. The radio decides what counts as
/// heard; the app never works it out itself, so older firmware gets no offer.
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
	/// Says only what the radio knows, per meshtastic/design#146: it does not know a setting changed
	/// or why.
	static func headline(count: Int) -> String {
		String(localized: "\(count) nodes not heard on your current LoRa settings")
	}

	static func removeConfirmation(count: Int) -> String {
		String(localized: "Remove \(count) nodes?", comment: "Confirmation title for removing nodes not heard on the current LoRa settings")
	}
}

struct UnheardNodesBanner: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager

	@State private var unheardNodes: [NodeInfoEntity] = []
	/// Nodes the radio has given an answer for, the denominator for "most of the list". The app keeps
	/// more nodes than the radio does; the ones it never reported on are unknown, not heard, and
	/// counting them hid the notice even when nearly every reported node was unheard.
	@State private var radioNodeCount = 0
	/// Of `unheardNodes`, the ones the radio reported unheard. Only these decide whether to offer:
	/// most apps keep more nodes than the radio, so counting the rest would offer all the time.
	@State private var reportedUnheardCount = 0
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
		// The radio's answers arrive with its node db. The connect reports subscribed before that
		// db is saved, so refresh once the save lands rather than on the state change.
		.onChange(of: accessoryManager.nodeDatabaseSavedAt) { _, _ in refresh() }
	}

	/// One aggregate when most of the list is unheard; the rows carry the marker otherwise.
	private func shouldOffer(connectedNodeNum: Int64) -> Bool {
		accessoryManager.reportsHeardOnCurrentLora
			&& UnheardOnCurrentLoraOffer.isMostOfList(unheard: reportedUnheardCount, reported: radioNodeCount)
			&& UnheardOnCurrentLoraOffer.shouldOffer(count: unheardNodes.count, forNode: connectedNodeNum)
	}

	private func dismiss(connectedNodeNum: Int64) {
		UnheardOnCurrentLoraOffer.dismiss(count: unheardNodes.count, forNode: connectedNodeNum)
	}

	private func content(connectedNodeNum: Int64) -> some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: "antenna.radiowaves.left.and.right.slash")
				.font(.title3)
				.foregroundStyle(.orange)

			VStack(alignment: .leading, spacing: 6) {
				// The honest claim: the radio has not heard them on these settings. It cannot know
				// they moved to another preset — a radio cannot observe a channel it is not tuned to.
				Text(UnheardNodesStrings.headline(count: unheardNodes.count))
					.font(.callout.weight(.semibold))
				Text("Your radio has not heard them on the settings it is using now, or no longer has them. Favorites and the connected node are kept.")
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
				Text("Remove", comment: "Confirms removing nodes not heard on the current LoRa settings")
			}
			Button(role: .cancel) { } label: {
				Text("Cancel")
			}
		} message: {
			Text("They are removed from this app, and from the radio if it still has them. Any that are still out there come back when they are next heard.")
		}
	}

	/// A node the radio no longer has: it sends the field, a node database has been saved this
	/// session (so absent nodes have been marked), and it gave no answer for this node. The radio
	/// adds every node it hears, so it has not heard these on its current settings either.
	private func isAppOnly(_ node: NodeInfoEntity) -> Bool {
		accessoryManager.nodeDatabaseSavedAt != nil && node.heardOnCurrentLora == nil && !node.viaMqtt
	}

	private func isRemovable(_ node: NodeInfoEntity) -> Bool {
		node.isUnheardOnCurrentLora || isAppOnly(node)
	}

	/// Nodes the radio reports unheard on its current settings, plus nodes only the app still has,
	/// excluding favorites and the radio itself.
	private func refresh() {
		guard let connectedNodeNum, accessoryManager.reportsHeardOnCurrentLora else {
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
			Logger.data.error("Could not read nodes not heard on the current LoRa settings: \(error.localizedDescription, privacy: .public)")
			unheardNodes = []
			return
		}
		radioNodeCount = candidates.filter { !$0.viaMqtt && $0.heardOnCurrentLora != nil }.count
		reportedUnheardCount = candidates.filter(\.isUnheardOnCurrentLora).count
		unheardNodes = candidates.filter(isRemovable)
		// Only once this session's node database is saved: before that, nodes the radio no longer
		// has aren't counted yet, and a low early count would bring the offer back after every launch.
		if accessoryManager.nodeDatabaseSavedAt != nil {
			UnheardOnCurrentLoraOffer.lowerDismissal(toCount: unheardNodes.count, forNode: connectedNodeNum)
		}
	}

	private func removeUnheardNodes(connectedNodeNum: Int64) async {
		isRemoving = true
		defer { isRemoving = false }

		// The list was built when the banner appeared. A node can be heard again between then and the
		// confirmation, and removing one that has just come back is the one outcome worth avoiding
		// here — so each is re-checked rather than trusted.
		var removed = 0
		var failed = 0
		var recovered = 0

		for node in unheardNodes {
			guard isRemovable(node) else {
				recovered += 1
				continue
			}
			do {
				if isAppOnly(node) {
					// The radio doesn't have it, so there is nothing to remove there.
					if let user = node.user { context.delete(user) }
					context.delete(node)
					try context.save()
				} else {
					try await accessoryManager.removeNode(node: node, connectedNodeNum: connectedNodeNum)
				}
				removed += 1
				unheardNodes.removeAll { $0.num == node.num }
			} catch {
				// Keep going: one node the radio refuses should not strand the rest.
				failed += 1
				Logger.data.error("Could not remove unheard node \(node.num.toHex(), privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
		Logger.data.info("Removed \(removed, privacy: .public) nodes not heard on the current LoRa settings, \(failed, privacy: .public) failed, \(recovered, privacy: .public) heard again before removal")

		// Only stand the offer down once nothing is left to remove. Dismissing after a partial
		// failure would hide the banner and take the retry with it.
		if failed == 0 {
			dismiss(connectedNodeNum: connectedNodeNum)
		}
		refresh()
	}
}
