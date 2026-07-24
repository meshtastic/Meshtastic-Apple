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

struct MapScreen: View {
	@Bindable var client: MeshClient
	@State private var selectedNodeNum: UInt32?
	@State private var recenterToken = 0

	var body: some View {
		HStack(spacing: 0) {
			nodeList
				.frame(width: 520)

			MeshTVMapView(
				nodes: client.locatedNodes,
				selectedNodeNum: $selectedNodeNum,
				recenterToken: recenterToken
			)
			.ignoresSafeArea()
		}
		.overlay(alignment: .topTrailing) {
			HStack(spacing: 20) {
				recenterButton
				disconnectButton
			}
			.padding(40)
		}
	}

	private var recenterButton: some View {
		Button {
			selectedNodeNum = nil
			recenterToken += 1
		} label: {
			Label("Re-center", systemImage: "scope")
				// The brand-green tint renders .bordered pills green-on-green on
				// tvOS; force a readable label (focus styling still overrides).
				.foregroundStyle(.white)
		}
		.buttonStyle(.bordered)
		.tint(.secondary)
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
			.navigationDestination(for: UInt32.self) { num in
				if let node = client.nodes[num] {
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
			Image("m-logo-white")
				.resizable()
				.scaledToFit()
				.frame(height: 44)
			VStack(alignment: .leading, spacing: 2) {
				Text("Meshtastic")
					.font(.system(size: 34, weight: .heavy, design: .rounded))
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
