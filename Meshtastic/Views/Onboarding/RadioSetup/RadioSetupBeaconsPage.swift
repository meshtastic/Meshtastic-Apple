//
//  RadioSetupBeaconsPage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/26.
//

import OSLog
import SwiftData
import SwiftUI

/// Firmware 2.8 and later: listen for beacons from meshes nearby, join or add one heard so far,
/// or go on to scan for meshes or broadcast a beacon of your own. Skippable.
struct RadioSetupBeaconsPage: View {
	let model: RadioSetupModel
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Query private var nodes: [NodeInfoEntity]
	/// Newest first; the ones heard outside a scan are picked out in memory, as the Nearby
	/// Meshes list does, to keep a relationship out of the predicate.
	@Query(sort: \DiscoveredBeaconEntity.timestamp, order: .reverse)
	private var allBeacons: [DiscoveredBeaconEntity]
	@State private var join = BeaconJoinController()

	/// How many heard beacons the page lists. The rest are in Local Mesh Discovery.
	private static let shownBeacons = 5

	init(model: RadioSetupModel) {
		self.model = model
		let num = model.nodeNum
		_nodes = Query(filter: #Predicate<NodeInfoEntity> { $0.num == num })
	}

	private var node: NodeInfoEntity? { nodes.first }

	private var isListening: Bool {
		MeshBeaconFlags.has(node?.meshBeaconConfig?.flags ?? 0, MeshBeaconFlags.listenEnabled)
	}

	private var listening: Binding<Bool> {
		Binding(
			get: { isListening },
			set: { listen in Task { await model.setListening(listen, using: accessoryManager, context: context) } }
		)
	}

	private var heardBeacons: [DiscoveredBeaconEntity] {
		Array(allBeacons.lazy.filter { $0.session == nil }.prefix(Self.shownBeacons))
	}

	var body: some View {
		OnboardingPage(
			title: String(localized: "Nearby Meshes", comment: "Radio setup beacons title"),
			intro: AttributedString(localized: "Meshes near you can advertise themselves with a beacon. Listen for them to see what's around and join one.", comment: "Radio setup beacons intro"),
			errorMessage: model.saveError,
			action: { model.advance(from: .beacons) }
		) {
			OnboardingFeatureRow(
				symbol: "antenna.radiowaves.left.and.right",
				title: String(localized: "Listen for Beacons"),
				text: node?.meshBeaconConfig == nil
					? String(localized: "Waiting for your radio's beacon settings.", comment: "Radio setup beacons page; the listen setting has not arrived from the radio yet")
					: String(localized: "Hear beacons from meshes nearby. They show here and in Local Mesh Discovery.", comment: "Radio setup beacons page; the listen setting"),
				isOn: listening
			)
			.disabled(node?.meshBeaconConfig == nil || model.isSaving)

			if isListening, heardBeacons.isEmpty {
				OnboardingFeatureRow(
					symbol: "ellipsis",
					color: .secondary,
					text: String(localized: "None heard yet. A mesh's beacon can take an hour or more to arrive.", comment: "Radio setup beacons page; listening but nothing heard")
				)
			}
			ForEach(heardBeacons) { beacon in
				BeaconRow(beacon: beacon, joinOption: accessoryManager.beaconJoinOption(for: beacon), join: join)
			}

			NavigationLink {
				DiscoveryScanView()
			} label: {
				OnboardingFeatureRow(
					symbol: "magnifyingglass",
					color: .purple,
					title: String(localized: "Scan for Meshes", comment: "Radio setup beacons page; opens Local Mesh Discovery"),
					text: String(localized: "Local Mesh Discovery listens on each preset in turn and reports who it hears.", comment: "Radio setup beacons page")
				)
			}
			.buttonStyle(.plain)
			if let node {
				NavigationLink {
					MeshBeaconConfig(node: node)
				} label: {
					OnboardingFeatureRow(
						symbol: "dot.radiowaves.up.forward",
						color: .orange,
						title: String(localized: "Broadcast a Beacon", comment: "Radio setup beacons page; opens the Mesh Beacon settings"),
						text: String(localized: "Advertise your own mesh so people nearby can find and join it.", comment: "Radio setup beacons page")
					)
				}
				.buttonStyle(.plain)
			}
		}
		.beaconJoinPrompts(join)
		.onChange(of: isListening, initial: true) { _, listening in
			if node?.meshBeaconConfig != nil { model.listensForBeacons = listening }
		}
		.task {
			// The radio sends its module configs when it connects; ask again if this one is missing.
			guard node?.meshBeaconConfig == nil, let user = node?.user else { return }
			do {
				try await accessoryManager.requestMeshBeaconModuleConfig(fromUser: user, toUser: user)
			} catch {
				Logger.mesh.error("📡 [Beacon] Radio setup could not request the beacon config: \(error.localizedDescription, privacy: .public)")
				model.saveError = error.localizedDescription
			}
		}
	}
}

/// A beacon heard so far: its mesh, its message, and Join, or Add when the mesh runs on the
/// radio's own preset and slot.
private struct BeaconRow: View {
	let beacon: DiscoveredBeaconEntity
	let joinOption: BeaconJoinOption
	let join: BeaconJoinController
	@EnvironmentObject private var accessoryManager: AccessoryManager

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(beacon.displayName)
				.font(.headline)
			if !beacon.message.isEmpty {
				Text(beacon.message)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			if joinOption != .none {
				HStack(spacing: 8) {
					Button(String(localized: "Join", comment: "Radio setup beacons page; switch to a heard mesh")) {
						join.askToSwitch(to: beacon)
					}
					if joinOption == .add {
						Button(String(localized: "Add", comment: "Radio setup beacons page; add a heard mesh's channel")) {
							join.askToAdd(beacon)
						}
					}
				}
				.buttonStyle(.bordered)
				.disabled(!accessoryManager.isConnected)
				.padding(.top, 2)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(16)
		.background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
}
