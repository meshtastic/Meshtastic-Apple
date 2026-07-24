//
//  MapScreen.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Live mesh map with a focusable node side-list for Siri Remote operation.
//  The list is the primary, reliable selection path on tvOS; clicking a pin on
//  the map (focus engine) selects too and keeps the list in sync.
//

import SwiftUI

struct MapScreen: View {
	@Bindable var client: MeshClient
	@State private var selectedNodeNum: UInt32?

	var body: some View {
		HStack(spacing: 0) {
			nodeList
				.frame(width: 520)

			MeshTVMapView(nodes: client.locatedNodes, selectedNodeNum: $selectedNodeNum)
				.ignoresSafeArea()
		}
		.overlay(alignment: .topTrailing) {
			disconnectButton
				.padding(40)
		}
	}

	private var nodeList: some View {
		NavigationStack {
			List(selection: $selectedNodeNum) {
				Section {
					ForEach(client.sortedNodes) { node in
						NavigationLink(value: node.num) {
							NodeRow(node: node)
						}
					}
				} header: {
					Text("\(client.nodes.count) nodes · \(client.locatedNodes.count) on map")
				}
			}
			.navigationTitle(client.host)
			.navigationDestination(for: UInt32.self) { num in
				if let node = client.nodes[num] {
					NodeDetailView(node: node)
				}
			}
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

private struct NodeRow: View {
	let node: MeshNode

	var body: some View {
		HStack(spacing: 16) {
			Image(systemName: node.hasLocation ? "mappin.circle.fill" : "antenna.radiowaves.left.and.right")
				.foregroundStyle(node.hasLocation ? .green : .secondary)
			VStack(alignment: .leading, spacing: 4) {
				Text(node.displayName)
					.lineLimit(1)
				if let battery = node.batteryLevel {
					Text("Battery \(battery)%")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			Spacer()
		}
	}
}
