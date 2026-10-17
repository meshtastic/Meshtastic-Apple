//
//  LiveActivitySheet.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//

import SwiftData
import SwiftUI

/// Choose what the Live Activity shows — a mesh status glance or one node —
/// and start, switch or stop it.
struct LiveActivitySheet: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@ObservedObject var liveActivities: MeshLiveActivityManager

	private enum Choice: Hashable {
		case meshStatus
		case trackNode
	}

	/// A node as the picker shows it, copied out of SwiftData so the sheet
	/// never holds a model object.
	private struct NodeRow: Identifiable, Hashable {
		let num: Int64
		let shortName: String
		let longName: String
		let lastHeard: Date?
		let favorite: Bool

		var id: Int64 { num }
	}

	@State private var choice: Choice = .meshStatus
	@State private var selectedNode: Int64?
	@State private var nodes: [NodeRow] = []
	@State private var searchText = ""

	private static let topID = "top"

	var body: some View {
		NavigationStack {
			ScrollViewReader { proxy in
				Form {
					Section {
						Picker("Show", selection: $choice) {
							Text("Mesh Status").tag(Choice.meshStatus)
							Text("Track a Node").tag(Choice.trackNode)
						}
						.pickerStyle(.inline)
						.labelsHidden()
					} header: {
						Text("Show")
					} footer: {
						Text(choice == .meshStatus
							? "The connection, nodes online, unread messages and the radio's battery."
							: "One node's battery, signal, when it was last heard and how far away it is.")
					}
					.id(Self.topID)

					// Start, switch and stop sit above the node list, which can be long, with the
					// picked node shown here so it's clear what starting will track.
					Section {
						if choice == .trackNode {
							if let node = nodes.first(where: { $0.num == selectedNode }) {
								nodeLabel(node)
							} else {
								Text("Pick a node below")
									.foregroundStyle(.secondary)
							}
						}
						actionButtons
					} footer: {
						if let updatesEndAt = liveActivities.updatesEndAt {
							Text("Updates until \(updatesEndAt.formatted(date: .omitted, time: .shortened)). iOS stops a Live Activity after 8 hours.")
						} else {
							Text("iOS stops a Live Activity after 8 hours. Only one runs at a time.")
						}
					}

					if choice == .trackNode {
						Section("Node") {
							if filteredNodes.isEmpty {
								Text("No nodes to track yet")
									.foregroundStyle(.secondary)
							}
							ForEach(filteredNodes) { node in
								Button {
									selectedNode = node.num
									// Back up to the picked node and the button that starts or switches to it.
									withAnimation {
										proxy.scrollTo(Self.topID, anchor: .top)
									}
								} label: {
									nodeLabel(node)
								}
								.foregroundStyle(.primary)
							}
						}
					}
				}
			}
			.searchable(text: $searchText, prompt: "Search nodes")
			.navigationTitle("Live Activity")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
				}
			}
			.onAppear {
				loadNodes()
				// Open on what's running, so Stop is one tap away.
				if let tracked = liveActivities.currentMode?.trackedNodeNum {
					choice = .trackNode
					selectedNode = tracked
				}
			}
		}
	}

	// MARK: - Actions

	/// The mode the current choices describe, or nil when tracking but no node
	/// is picked yet.
	private var chosenMode: LiveActivityMode? {
		switch choice {
		case .meshStatus:
			return .meshStatus
		case .trackNode:
			return selectedNode.map { .trackNode(num: $0) }
		}
	}

	@ViewBuilder
	private var actionButtons: some View {
		let running = liveActivities.currentMode
		if let running, running == chosenMode {
			Button("Stop Live Activity", role: .destructive) {
				liveActivities.stop()
				dismiss()
			}
		} else {
			Button(running == nil ? "Start Live Activity" : "Switch Live Activity") {
				if let chosenMode {
					liveActivities.start(mode: chosenMode)
					dismiss()
				}
			}
			.disabled(chosenMode == nil || !accessoryManager.isConnected)
			if running != nil {
				Button("Stop Live Activity", role: .destructive) {
					liveActivities.stop()
					dismiss()
				}
			}
		}
	}

	// MARK: - Nodes

	private var filteredNodes: [NodeRow] {
		guard !searchText.isEmpty else { return nodes }
		return nodes.filter {
			$0.longName.localizedCaseInsensitiveContains(searchText)
				|| $0.shortName.localizedCaseInsensitiveContains(searchText)
		}
	}

	private func nodeLabel(_ node: NodeRow) -> some View {
		HStack(spacing: 12) {
			CircleText(text: node.shortName, color: Color(UIColor(hex: UInt32(truncatingIfNeeded: node.num))), circleSize: 36)
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 4) {
					Text(node.longName)
						.font(.body)
					if node.favorite {
						Image(systemName: "star.fill")
							.font(.caption)
							.foregroundStyle(.yellow)
					}
				}
				if let lastHeard = node.lastHeard {
					Text("Heard \(lastHeard, style: .relative) ago")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			Spacer(minLength: 4)
			if selectedNode == node.num {
				Image(systemName: "checkmark")
					.foregroundStyle(Color.accentColor)
			}
		}
	}

	/// Favorites first, then the most recently heard, the same order as the
	/// node tracker widget's picker. Fetched by scalars only; nodes without a
	/// user, and the connected radio, are filtered in Swift.
	private func loadNodes() {
		let radioNum = accessoryManager.activeDeviceNum
		let favoritesDescriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { $0.favorite == true },
			sortBy: [SortDescriptor(\.lastHeard, order: .reverse)]
		)
		var recentDescriptor = FetchDescriptor<NodeInfoEntity>(
			sortBy: [SortDescriptor(\.lastHeard, order: .reverse)]
		)
		recentDescriptor.fetchLimit = 100
		let favorites = (try? context.fetch(favoritesDescriptor)) ?? []
		let recent = ((try? context.fetch(recentDescriptor)) ?? []).filter { !$0.favorite }
		nodes = (favorites + recent).compactMap { node -> NodeRow? in
			guard node.num != radioNum, !node.ignored, let user = node.user else { return nil }
			return NodeRow(
				num: node.num,
				shortName: user.shortName ?? "?",
				longName: user.longName ?? node.num.toHex(),
				lastHeard: node.lastHeard,
				favorite: node.favorite
			)
		}
	}
}
