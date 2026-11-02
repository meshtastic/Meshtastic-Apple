//
//  BeaconJoinPrompts.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//
//  The join actions for a mesh a beacon advertises, and the confirmations and error alerts
//  they raise. Held apart from any one screen so more than one can offer the same Switch,
//  Add and Replace buttons.
//

import SwiftUI

/// Holds which beacon is waiting on a confirmation and runs the join once confirmed. A screen
/// keeps one in `@State`, attaches `beaconJoinPrompts(_:)` and calls `askToSwitch(to:)` or
/// `askToAdd(_:)` from its buttons.
@MainActor @Observable
final class BeaconJoinController {
	/// Beacon awaiting a "switch to this channel" confirmation; drives the alert.
	var beaconToJoin: DiscoveredBeaconEntity?
	var joinErrorMessage: String?
	/// Beacon awaiting an "add channel" confirmation; drives the Add alert.
	var beaconToAdd: DiscoveredBeaconEntity?
	var addErrorMessage: String?
	/// Beacon awaiting a "replace which secondary channel?" choice when no free slot exists (D2).
	var beaconToReplace: DiscoveredBeaconEntity?

	func askToSwitch(to beacon: DiscoveredBeaconEntity) {
		beaconToJoin = beacon
	}

	func askToAdd(_ beacon: DiscoveredBeaconEntity) {
		beaconToAdd = beacon
	}

	/// Applies a beacon's advertised channel and region/preset to the connected radio. Before
	/// firmware 2.8 the radio reboots onto the advertised mesh. Failures surface in an alert.
	func switchToBeaconChannel(_ beacon: DiscoveredBeaconEntity, using accessoryManager: AccessoryManager) {
		beaconToJoin = nil
		Task {
			do {
				try await accessoryManager.joinBeaconMesh(
					channelName: beacon.offerChannelName,
					channelPSK: beacon.offerChannelPSK,
					region: beacon.offeredRegion,
					preset: beacon.offeredPreset,
					frequencySlot: beacon.offeredFrequencySlot
				)
			} catch {
				joinErrorMessage = error.localizedDescription
			}
		}
	}

	/// Adds a beacon's advertised channel to a free secondary slot (no reboot). When every
	/// secondary slot is full, asks which one to replace instead of failing (D2).
	func addBeaconChannel(_ beacon: DiscoveredBeaconEntity, using accessoryManager: AccessoryManager) {
		beaconToAdd = nil
		// No free slot: let the user choose an existing secondary to replace (never the primary).
		guard accessoryManager.beaconHasFreeSecondarySlot() else {
			beaconToReplace = beacon
			return
		}
		Task {
			do {
				try await accessoryManager.addBeaconChannel(
					channelName: beacon.offerChannelName,
					channelPSK: beacon.offerChannelPSK
				)
			} catch {
				addErrorMessage = error.localizedDescription
			}
		}
	}

	/// Replaces the secondary channel at `index` with the beacon's advertised channel (D2).
	/// Cancelling the picker makes no change.
	func replaceBeaconChannel(_ beacon: DiscoveredBeaconEntity, atIndex index: Int32, using accessoryManager: AccessoryManager) {
		beaconToReplace = nil
		Task {
			do {
				try await accessoryManager.addBeaconChannel(
					channelName: beacon.offerChannelName,
					channelPSK: beacon.offerChannelPSK,
					replacingIndex: index
				)
			} catch {
				addErrorMessage = error.localizedDescription
			}
		}
	}
}

extension View {
	/// Attaches the Switch, Add and Replace confirmations and their error alerts for `controller`.
	func beaconJoinPrompts(_ controller: BeaconJoinController) -> some View {
		modifier(BeaconJoinPrompts(controller: controller))
	}
}

private struct BeaconJoinPrompts: ViewModifier {
	let controller: BeaconJoinController
	@EnvironmentObject private var accessoryManager: AccessoryManager

	func body(content: Content) -> some View {
		content
			.hostedAlert("Switch to this channel?", isPresented: Binding(
				get: { controller.beaconToJoin != nil },
				set: { if !$0 { controller.beaconToJoin = nil } }
			), presenting: controller.beaconToJoin) { beacon in
				Button("Cancel", role: .cancel) { controller.beaconToJoin = nil }
				Button("Switch") { controller.switchToBeaconChannel(beacon, using: accessoryManager) }
			} message: { beacon in
				Text(accessoryManager.beaconSwitchPrompt(for: beacon))
			}
			.hostedAlert("Couldn't switch channel", isPresented: Binding(
				get: { controller.joinErrorMessage != nil },
				set: { if !$0 { controller.joinErrorMessage = nil } }
			)) {
				Button("OK", role: .cancel) { controller.joinErrorMessage = nil }
			} message: {
				Text(controller.joinErrorMessage ?? "")
			}
			.hostedAlert("Add this channel?", isPresented: Binding(
				get: { controller.beaconToAdd != nil },
				set: { if !$0 { controller.beaconToAdd = nil } }
			), presenting: controller.beaconToAdd) { beacon in
				Button("Cancel", role: .cancel) { controller.beaconToAdd = nil }
				Button("Add") { controller.addBeaconChannel(beacon, using: accessoryManager) }
			} message: { beacon in
				Text("Add \"\(beacon.offerChannelName)\" as an additional channel — your radio keeps its current mesh, no reboot.")
			}
			.hostedAlert("Couldn't add channel", isPresented: Binding(
				get: { controller.addErrorMessage != nil },
				set: { if !$0 { controller.addErrorMessage = nil } }
			)) {
				Button("OK", role: .cancel) { controller.addErrorMessage = nil }
			} message: {
				Text(controller.addErrorMessage ?? "")
			}
			.hostedConfirmation(
				"Replace which channel?",
				isPresented: Binding(
					get: { controller.beaconToReplace != nil },
					set: { if !$0 { controller.beaconToReplace = nil } }
				),
				titleVisibility: .visible,
				presenting: controller.beaconToReplace
			) { beacon in
				ForEach(accessoryManager.beaconReplaceableSecondaryChannels()) { channel in
					Button("\(channel.name) (slot \(channel.index))", role: .destructive) {
						controller.replaceBeaconChannel(beacon, atIndex: channel.index, using: accessoryManager)
					}
				}
				Button("Cancel", role: .cancel) { controller.beaconToReplace = nil }
			} message: { _ in
				Text("All secondary channel slots are full. Choose an existing secondary channel to replace — your primary channel is never touched.")
			}
	}
}
