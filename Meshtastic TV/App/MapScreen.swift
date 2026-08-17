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
	@State private var pollTick = 0
	// Row focus is the browse signal on tvOS: List(selection:) does not follow
	// focus for NavigationLink rows, so track it explicitly and mirror it into
	// the map selection (debounced map-side).
	@FocusState private var focusedNodeNum: UInt32?
	@State private var navPath: [UInt32] = []

	/// The persisted node store — the map and list read from here, not the client.
	@Query private var allNodes: [MeshNode]

	/// Decoded offline basemap. Held here (not in MeshTVMapView) so the decode survives
	/// the representable's updates; it publishes nothing until a region is downloaded.
	@StateObject private var offlineVectors = OfflineVectorTileProvider()

	/// Mesh stats strip visibility + position, shared with SettingsView via the same keys.
	@AppStorage("tv.statsBar.enabled") private var statsBarEnabled = true
	@AppStorage("tv.statsBar.edge") private var statsBarEdge: StatsStripEdge = .top

	// Cached sort/filter results so we don't re-sort 1000+ nodes on every body eval.
	@State private var sortedNodes: [MeshNode] = []
	@State private var locatedNodes: [MeshNode] = []

	var body: some View {
		HStack(spacing: 0) {
			nodeList
				.frame(width: TVTheme.sideListWidth)

			MeshTVMapView(
				nodes: locatedNodes,
				selectedNodeNum: $selectedNodeNum,
				recenterToken: recenterToken,
				onMenuExit: escapeMap,
				offlineVectors: offlineVectors
			)
			.ignoresSafeArea()
			// Overlay, not safeAreaInset: an inset resizes the MKMapView and re-triggers
			// the representable's region framing every time the strip toggles or moves.
			.overlay(alignment: statsBarEdge == .top ? .top : .bottom) {
				if statsBarEnabled {
					MeshStatsStrip(
						stats: client.stats,
						storeOnlineCount: allNodes.filter(\.isOnline).count,
						storeTotalCount: allNodes.count,
						edition: EventEdition(client.firmwareEdition)
					)
					.padding(TVTheme.statsStripMargin)
				}
			}
		}
		.onChange(of: allNodes) { _, newNodes in
			recomputeNodeLists(from: newNodes)
		}
		// onChange(of: allNodes) only fires on membership changes — SwiftData models
		// compare by identity, so in-place mutations (a node gaining a position, or
		// lastHeard updating) never trigger it once inserts stop. Poll on a gentle
		// cadence like the iOS mesh map does, so the cached lists can't go stale.
		.onChange(of: pollTick, initial: true) {
			recomputeNodeLists(from: allNodes)
		}
		.task {
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(2))
				pollTick += 1
			}
		}
	}

	private func recomputeNodeLists(from nodes: [MeshNode]) {
		let newSorted = nodes.sorted {
			if $0.hasLocation != $1.hasLocation { return $0.hasLocation }
			return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
		}
		let newLocated = nodes.filter(\.hasLocation)
			.sorted { ($0.lastHeard ?? .distantPast) > ($1.lastHeard ?? .distantPast) }
		if newSorted.map(\.num) != sortedNodes.map(\.num) { sortedNodes = newSorted }
		if newLocated.map(\.num) != locatedNodes.map(\.num) { locatedNodes = newLocated }
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
					.frame(height: TVTheme.wordmarkHeight)
				Text(client.host)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
		}
		.padding(.horizontal, 32)
		.padding(.vertical, 16)
		.background {
			// Frost the list rows that scroll up behind the wordmark, fading to clear at
			// the header's bottom edge so the logo/host never collides with moving data.
			Rectangle()
				.fill(.ultraThinMaterial)
				.mask(
					LinearGradient(
						stops: [
							.init(color: .black, location: 0.0),
							.init(color: .black, location: 0.7),
							.init(color: .clear, location: 1.0)
						],
						startPoint: .top,
						endPoint: .bottom
					)
				)
				.ignoresSafeArea(edges: [.top, .leading])
		}
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

/// Compact node row, modelled on the iOS `NodeListItemCompact`: node-color circle,
/// name, then a secondary line of last-heard (green when online) and role.
private struct NodeRow: View {
	let node: MeshNode

	var body: some View {
		HStack(spacing: 16) {
			// Same circle badge as the map pin (node color + short name).
			CircleText(
				text: node.shortName.isEmpty ? "?" : node.shortName,
				color: Color(UIColor(hex: node.num)),
				circleSize: TVTheme.listAvatarSize
			)
			.opacity(node.hasLocation ? 1 : 0.55)

			VStack(alignment: .leading, spacing: 6) {
				Text(node.displayName)
					.lineLimit(1)

				HStack(spacing: 14) {
					if let lastHeard = node.lastHeard {
						Label {
								// Abbreviated: the full "10 minutes ago" crowds out the role
							// and position labels beside it on a 520pt list.
							Text(lastHeard.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
						} icon: {
							Image(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill")
								.foregroundStyle(node.isOnline ? Color("MeshtasticSuccess") : Color("MeshtasticWarning"))
						}
					}
					if let role = node.nodeRole {
						Label(role.name, systemImage: role.systemName)
					}
					if !node.hasLocation {
						Label("No position", systemImage: "location.slash")
					}
				}
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
			}
			// Take the row's remaining width outright. A trailing Spacer() competes
			// with the text for it, and Text yields by truncating — which is why the
			// metadata line clipped while the row still had space to its right.
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}
