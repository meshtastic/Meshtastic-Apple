//
//  WaypointRecipientPicker.swift
//  Meshtastic
//

import MeshtasticProtobufs
import SwiftUI
@preconcurrency import SwiftData

/// Display label for channel `index`: its configured name, else — for the primary channel only —
/// `channelDisplayName` (the same preset-name/"Custom"/"Broadcast" fallback rules the Channels settings
/// screen uses, so the two screens never show different names for the same channel), else "Channel N" for
/// an unnamed secondary channel.
func waypointChannelLabel(index: Int32, channels: [ChannelEntity], node: NodeInfoEntity?) -> String {
	if let channel = channels.first(where: { $0.index == index }), let name = channel.name, !name.isEmpty {
		return name
	}
	guard index == 0 else { return "Channel \(index)".localized }
	return channelDisplayName(channels: channels, node: node)
}

/// Display label for a node, for the recipient picker or the "currently selected" summary: the user's local
/// custom display name if set (matching every other node label in the app), else the long name, short name,
/// or a fallback derived from its node number — never blank, and never rendered as "Broadcast" just because
/// a bare/unconfigured node has no name set yet.
func waypointNodeLabel(_ node: NodeInfoEntity) -> String {
	if let custom = NodeDisplayNameStore.displayName(for: node.num) { return custom }
	if let longName = node.user?.longName, !longName.isEmpty { return longName }
	if let shortName = node.user?.shortName, !shortName.isEmpty { return shortName }
	return node.num.toHex()
}

/// Display label for a waypoint's currently selected destination.
func waypointDestinationLabel(_ destination: WaypointDestination, channels: [ChannelEntity], nodes: [NodeInfoEntity], node: NodeInfoEntity?) -> String {
	switch destination {
	case let .channel(index):
		return waypointChannelLabel(index: index, channels: channels, node: node)
	case let .user(num):
		if let match = nodes.first(where: { $0.num == num }) {
			return waypointNodeLabel(match)
		}
		return num.toHex()
	}
}

/// The connected node's configured channels (deduped by index, ascending) — used both to render the primary
/// channel's real name and to list secondary channels in the recipient picker. Shares its dedup logic with
/// the Channels settings screen via `dedupedChannels(for:)`.
func waypointChannels(for node: NodeInfoEntity?) -> [ChannelEntity] {
	dedupedChannels(for: node)
}

/// Channel rows to list in the recipient picker: the primary channel (0) always appears even if it hasn't
/// synced into `channels` yet (config sync populates channels incrementally, one packet at a time), plus
/// whatever secondary channels are currently known.
func waypointChannelIndexes(channels: [ChannelEntity]) -> [Int32] {
	Array(Set([0] + channels.map(\.index))).sorted()
}

/// Node rows to list in the recipient picker: `nodes` minus `ownNodeNum` and ignored nodes, narrowed by a
/// case-insensitive substring match on `filterText` against each node's display label.
func waypointFilterNodes(_ nodes: [NodeInfoEntity], excluding ownNodeNum: Int64?, matching filterText: String) -> [NodeInfoEntity] {
	let candidates = nodes.filter { $0.num != ownNodeNum && !$0.ignored }
	guard !filterText.isEmpty else { return candidates }
	return candidates.filter { waypointNodeLabel($0).localizedCaseInsensitiveContains(filterText) }
}

/// Lists the primary channel (labelled by its real configured name), then any secondary channels, then a
/// divider, then every known node — letting a waypoint be broadcast, sent to a secondary channel, or DM'd
/// to a specific node, matching the destinations the Python Meshtastic CLI/API can already target.
///
/// Node rows can number in the thousands on an MQTT-bridged mesh, so a name filter narrows them; channel
/// rows are never hidden by the filter. This is a small, purpose-built filter rather than a reuse of
/// `NodeFilterParameters` — that type is a shared app-wide singleton (`.shared`) backing the Nodes tab's own
/// filter UI, and driving it from this transient sheet would leak filter state into that unrelated screen.
struct WaypointRecipientPicker: View {

	let node: NodeInfoEntity?
	/// The connected device's own node number, for excluding it from the DM list. Taken directly from
	/// `AccessoryManager.activeDeviceNum` rather than derived from `node` — `node` is populated by an async
	/// SwiftData fetch and can still be nil the moment this picker opens, which would otherwise let the
	/// user "DM" themselves during that brief window.
	let ownNodeNum: Int64?
	@Binding var selection: WaypointDestination
	@Environment(\.dismiss) private var dismiss
	@State private var filterText: String = ""

	@Query(sort: \NodeInfoEntity.lastHeard, order: .reverse)
	private var allNodes: [NodeInfoEntity]

	// Node rows can number in the thousands (see the type doc above), so `filteredNodes` is cached in
	// @State and only recomputed on an actual filter/list change — not on every body re-render (e.g. a
	// selection change toggling a checkmark) — to avoid re-scanning + re-labelling the full list needlessly.
	@State private var filteredNodes: [NodeInfoEntity] = []

	private var channels: [ChannelEntity] {
		waypointChannels(for: node)
	}

	private var channelIndexes: [Int32] {
		waypointChannelIndexes(channels: channels)
	}

	private func updateFilteredNodes() {
		filteredNodes = waypointFilterNodes(allNodes, excluding: ownNodeNum, matching: filterText)
	}

	var body: some View {
		NavigationStack {
			List {
				Section {
					ForEach(channelIndexes, id: \.self) { index in
						Button {
							selection = .channel(index)
							dismiss()
						} label: {
							recipientRow(
								label: waypointChannelLabel(index: index, channels: channels, node: node),
								selected: selection == .channel(index)
							)
						}
					}
				}
				Section {
					ForEach(filteredNodes, id: \.num) { candidate in
						Button {
							selection = .user(candidate.num)
							dismiss()
						} label: {
							recipientRow(
								label: waypointNodeLabel(candidate),
								selected: selection == .user(candidate.num)
							)
						}
					}
				}
			}
			.searchable(text: $filterText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a node")
			.autocorrectionDisabled(true)
			.navigationTitle("Send to")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
			}
		}
		.onAppear {
			updateFilteredNodes()
		}
		.onChange(of: filterText) {
			updateFilteredNodes()
		}
		.onChange(of: allNodes.count) {
			updateFilteredNodes()
		}
	}

	@ViewBuilder
	private func recipientRow(label: String, selected: Bool) -> some View {
		HStack {
			Text(label)
				.foregroundColor(.primary)
			Spacer()
			if selected {
				Image(systemName: "checkmark")
					.foregroundColor(.accentColor)
			}
		}
	}
}
