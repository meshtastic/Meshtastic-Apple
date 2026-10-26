//
//  WidgetsSheet.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import SwiftData
import SwiftUI

/// The Live Activity, the Home Screen and Lock Screen widgets, and the
/// controls, in one place. The Live Activity is chosen and started here;
/// widgets and controls are added on the screens themselves — iOS gives apps
/// no way to place them — so their sections show what's added and how.
struct WidgetsSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Environment(\.scenePhase) private var scenePhase
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@ObservedObject var liveActivities: MeshLiveActivityManager
	@ObservedObject var inventory: WidgetInventory

	private enum Choice: Hashable {
		case meshStatus
		case trackNode
	}

	@State private var choice: Choice = .meshStatus
	@State private var selectedNode: Int64?
	@State private var nodes: [NodePickerRow] = []

	private static let appleWidgetGuide = URL(string: "https://support.apple.com/118610")!

	var body: some View {
		SheetNavigationStack {
			Form {
				liveActivitySections
				widgetsSection
				if #available(iOS 18.0, *) {
					controlsSection
				}
			}
			.navigationTitle("Widgets")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
			.onAppear {
				inventory.refresh()
				loadNodes()
				// Open on what's running, so Stop is one tap away.
				if let tracked = liveActivities.currentMode?.trackedNodeNum {
					choice = .trackNode
					selectedNode = tracked
				}
			}
			.onChange(of: scenePhase) { _, phase in
				// Back from adding a widget on the Home Screen.
				if phase == .active { inventory.refresh() }
			}
		}
	}

	// MARK: - Live Activity

	@ViewBuilder
	private var liveActivitySections: some View {
		if liveActivities.isAvailable || liveActivities.currentMode != nil {
			Section {
				Picker("Show", selection: $choice) {
					Text("Mesh Status").tag(Choice.meshStatus)
					Text("Track a Node").tag(Choice.trackNode)
				}
				.pickerStyle(.inline)
				.labelsHidden()
				if choice == .trackNode {
					NavigationLink {
						NodePicker(nodes: nodes, selection: $selectedNode)
					} label: {
						HStack {
							Text("Node")
							Spacer(minLength: 8)
							Text(selectedNodeName ?? String(localized: "Choose"))
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.trailing)
						}
					}
				}
				actionButtons
			} header: {
				Text("Live Activity")
			} footer: {
				if let updatesEndAt = liveActivities.updatesEndAt {
					Text("Updates until \(updatesEndAt.formatted(date: .omitted, time: .shortened)). iOS stops a Live Activity after 8 hours.")
				} else {
					Text(choice == .meshStatus
						? "On the Lock Screen and in the Dynamic Island: the connection, nodes online, unread messages and the radio's battery."
						: "On the Lock Screen and in the Dynamic Island: one node's battery, signal, when it was last heard and how far away it is.")
				}
			}
		} else if UIDevice.current.userInterfaceIdiom == .phone {
			Section("Live Activity") {
				Text("Live Activities are turned off for Meshtastic.")
					.foregroundStyle(.secondary)
				if let settings = URL(string: UIApplication.openSettingsURLString) {
					Link("Open Settings", destination: settings)
				}
			}
		}
	}

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

	private var selectedNodeName: String? {
		guard let selectedNode else { return nil }
		return nodes.first { $0.num == selectedNode }?.longName
			?? liveActivities.trackedNodeShortName
	}

	@ViewBuilder
	private var actionButtons: some View {
		let running = liveActivities.currentMode
		if let running, running == chosenMode {
			Button("Stop Live Activity", role: .destructive) {
				liveActivities.stop()
			}
		} else {
			Button(running == nil ? "Start Live Activity" : "Switch Live Activity") {
				if let chosenMode {
					liveActivities.start(mode: chosenMode)
				}
			}
			.disabled(chosenMode == nil || !accessoryManager.isConnected)
			if running != nil {
				Button("Stop Live Activity", role: .destructive) {
					liveActivities.stop()
				}
			}
		}
	}

	// MARK: - Widgets

	private var widgetsSection: some View {
		Section {
			ForEach(WidgetInventory.widgets) { widget in
				AddedRow(
					title: widget.title,
					systemImage: widget.systemImage,
					status: inventory.widgetStatus(for: widget.kind)
				)
			}
		} header: {
			Text("Home Screen & Lock Screen")
		} footer: {
			VStack(alignment: .leading, spacing: 6) {
				Text("Home Screen: touch and hold an empty spot, tap Edit, then Add Widget, and search for Meshtastic. Lock Screen: touch and hold it, tap Customize, then Lock Screen, tap the widget area and choose Meshtastic. To pick a Node Tracker's node, touch and hold the widget and choose Edit Widget.")
				Link("Apple's guide to widgets", destination: Self.appleWidgetGuide)
			}
		}
	}

	// MARK: - Controls

	@available(iOS 18.0, *)
	private var controlsSection: some View {
		Section {
			ForEach(WidgetInventory.controls) { control in
				AddedRow(
					title: control.title,
					systemImage: control.systemImage,
					status: inventory.controlStatus(for: control.kind)
				)
			}
		} header: {
			Text("Controls")
		} footer: {
			Text("Control Center: swipe down from the top right, tap +, then Add a Control and search for Meshtastic. Lock Screen: touch and hold it, tap Customize, then replace a button at the bottom. Action button: Settings, Action Button, then Controls.")
		}
	}

	// MARK: - Nodes

	/// Favorites first, then the most recently heard, the same order as the
	/// node tracker widget's picker. Fetched by scalars only; nodes without a
	/// user, ignored nodes and the connected radio are filtered in Swift.
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
		nodes = (favorites + recent).compactMap { node -> NodePickerRow? in
			guard node.num != radioNum, !node.ignored, let user = node.user else { return nil }
			return NodePickerRow(
				num: node.num,
				shortName: user.shortName ?? "?",
				longName: user.longName ?? node.num.toHex(),
				lastHeard: node.lastHeard,
				favorite: node.favorite
			)
		}
	}
}

/// A widget or control and whether it's on a screen.
private struct AddedRow: View {
	let title: LocalizedStringKey
	let systemImage: String
	let status: WidgetInventory.AddedStatus

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: systemImage)
				.foregroundStyle(Color.accentColor)
				.frame(width: 24)
			Text(title)
			Spacer(minLength: 8)
			switch status {
			case .added(let description):
				Text(description)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.trailing)
			case .notAdded:
				Text("Not added")
					.font(.subheadline)
					.foregroundStyle(.tertiary)
			case .unknown:
				// Nothing claimed until iOS says what's there.
				EmptyView()
			}
		}
	}
}

/// A node as the picker shows it, copied out of SwiftData so the sheet never
/// holds a model object.
struct NodePickerRow: Identifiable, Hashable {
	let num: Int64
	let shortName: String
	let longName: String
	let lastHeard: Date?
	let favorite: Bool

	var id: Int64 { num }
}

/// Choose the node a Live Activity tracks.
private struct NodePicker: View {
	@Environment(\.dismiss) private var dismiss
	let nodes: [NodePickerRow]
	@Binding var selection: Int64?
	@State private var searchText = ""

	var body: some View {
		List {
			if filtered.isEmpty {
				Text("No nodes to track yet")
					.foregroundStyle(.secondary)
			}
			ForEach(filtered) { node in
				Button {
					selection = node.num
					dismiss()
				} label: {
					HStack(spacing: 12) {
						CircleText(text: node.shortName, color: Color(UIColor(hex: UInt32(truncatingIfNeeded: node.num))), circleSize: 36)
						VStack(alignment: .leading, spacing: 2) {
							HStack(spacing: 4) {
								Text(node.longName)
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
						if selection == node.num {
							Image(systemName: "checkmark")
								.foregroundStyle(Color.accentColor)
						}
					}
				}
				.foregroundStyle(.primary)
			}
		}
		.searchable(text: $searchText, prompt: "Search nodes")
		.navigationTitle("Track a Node")
		.navigationBarTitleDisplayMode(.inline)
	}

	private var filtered: [NodePickerRow] {
		guard !searchText.isEmpty else { return nodes }
		return nodes.filter {
			$0.longName.localizedCaseInsensitiveContains(searchText)
				|| $0.shortName.localizedCaseInsensitiveContains(searchText)
		}
	}
}
#endif
