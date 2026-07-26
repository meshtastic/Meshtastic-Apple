//
//  MapScreen.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Live mesh map with a focusable node side-list for Siri Remote operation.
//  The list is the primary, reliable selection path on tvOS; clicking a pin on
//  the map (focus engine) selects too and keeps the list in sync. Rows carry the
//  same node-color circle badges as the map pins (CircleText, shared with iOS).
//

import SwiftUI
import SwiftData

struct MapScreen: View {
	@Bindable var client: MeshClient
	@State private var selectedNodeNum: UInt32?
	@State private var recenterToken = 0
	// Row focus is the browse signal on tvOS: List(selection:) does not follow
	// focus for NavigationLink rows, so track it explicitly and mirror it into
	// the map selection (debounced map-side).
	@FocusState private var focusedNodeNum: UInt32?
	@State private var navPath: [UInt32] = []

	/// The persisted node store — the map and list read from here, not the client.
	@Query private var allNodes: [MeshNode]

	/// All nodes for the side list: located first, then alphabetically.
	private var sortedNodes: [MeshNode] {
		allNodes.sorted {
			if $0.hasLocation != $1.hasLocation { return $0.hasLocation }
			return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
		}
	}

	/// Located nodes, most-recently-heard first — the map's data source.
	private var locatedNodes: [MeshNode] {
		allNodes.filter(\.hasLocation)
			.sorted { ($0.lastHeard ?? .distantPast) > ($1.lastHeard ?? .distantPast) }
	}

	var body: some View {
		HStack(spacing: 0) {
			nodeList
				.frame(width: 520)

			MeshTVMapView(
				nodes: locatedNodes,
				selectedNodeNum: $selectedNodeNum,
				recenterToken: recenterToken,
				onMenuExit: escapeMap
			)
			.ignoresSafeArea()
		}
	}

	/// Menu pressed while the map held focus: pop any open node detail and hand
	/// focus back to the node list — without this, MKMapView is a focus trap.
	private func escapeMap() {
		navPath = []
		focusedNodeNum = selectedNodeNum ?? sortedNodes.first?.num
	}

	private var nodeList: some View {
		NavigationStack(path: $navPath) {
			List {
				// Map controls live in the list column — the overlay buttons were
				// unreachable by remote once the map started capturing focus.
				Section {
					Button {
						selectedNodeNum = nil
						recenterToken += 1
					} label: {
						Label("Re-center Map", systemImage: "scope")
					}
					NavigationLink {
						SettingsView()
					} label: {
						Label("Settings", systemImage: "gearshape")
					}
					Button(role: .destructive) {
						client.disconnect()
					} label: {
						Label("Disconnect", systemImage: "xmark.circle.fill")
					}
				}

				Section {
					ForEach(sortedNodes) { node in
						NavigationLink(value: node.num) {
							NodeRow(node: node)
						}
						.focused($focusedNodeNum, equals: node.num)
					}
				} header: {
					Text("\(allNodes.count) nodes · \(locatedNodes.count) on map")
				}
			}
			.onChange(of: focusedNodeNum) { _, newValue in
				if let newValue { selectedNodeNum = newValue }
			}
			.navigationDestination(for: UInt32.self) { num in
				if let node = allNodes.first(where: { $0.num == num }) {
					NodeDetailView(node: node)
				}
			}
			.safeAreaInset(edge: .top) {
				header
			}
		}
	}

	private var header: some View {
		HStack(spacing: 20) {
			VStack(alignment: .leading, spacing: 6) {
				Image("meshtastic-wordmark-white")
					.resizable()
					.scaledToFit()
					.frame(height: 30)
				Text(client.host)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
		}
		.padding(.horizontal, 32)
		.padding(.vertical, 16)
	}

	private var disconnectButton: some View {
		Button(role: .destructive) {
			client.disconnect()
		} label: {
			Label("Disconnect", systemImage: "xmark.circle.fill")
		}
		.buttonStyle(.bordered)
	}
}

private struct NodeRow: View {
	let node: MeshNode

	var body: some View {
		HStack(spacing: 16) {
			// Same circle badge as the map pin (node color + short name).
			CircleText(
				text: node.shortName.isEmpty ? "?" : node.shortName,
				color: Color(UIColor(hex: node.num)),
				circleSize: 52
			)
			.opacity(node.hasLocation ? 1 : 0.45)

			VStack(alignment: .leading, spacing: 4) {
				Text(node.displayName)
					.lineLimit(1)
				HStack(spacing: 12) {
					if let battery = node.batteryLevel {
						Label("\(battery)%", systemImage: battery > 20 ? "battery.75percent" : "battery.25percent")
							.foregroundStyle(Color("LightIndigo"))
					}
					if !node.hasLocation {
						Label("No position", systemImage: "location.slash")
							.foregroundStyle(.secondary)
					}
				}
				.font(.caption)
			}
			Spacer()
		}
	}
}
