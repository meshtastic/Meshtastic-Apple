//
//  UnheardOnCurrentLora.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/4/26.
//

import Foundation

/// The marker for a node the radio has not heard on its current LoRa settings (meshtastic/design#146).
///
/// The copy says only that: a radio cannot observe a channel it is not tuned to, so it must not
/// suggest the node changed settings or moved.
enum UnheardOnCurrentLora {
	static let systemImage = "antenna.radiowaves.left.and.right.slash"
	/// Short enough for one line in a node row.
	static var shortLabel: String {
		String(localized: "Not heard on current LoRa", comment: "Node row marker for a node the radio has not heard on its current LoRa settings")
	}
	/// The full wording, for VoiceOver and the node detail screen.
	static var label: String {
		String(localized: "Not heard on your current LoRa settings", comment: "Marker for a node the radio has not heard on its current LoRa settings")
	}
}

/// Whether to show the aggregate for nodes the radio reports unheard on its current LoRa settings.
///
/// Offered while most of the list is unheard, which is what a settings change does all at once.
/// Keep holds until that clears (the nodes are heard again, or the settings go back), so the next
/// change offers again. The radio's settings can change from the device menu or the CLI without the
/// app seeing it, which is why this follows the radio's answers rather than the app's own saves.
enum UnheardOnCurrentLoraOffer {
	static func key(forNode nodeNum: Int64) -> String {
		"unheardOnCurrentLoraDismissed.\(nodeNum)"
	}

	/// Whether unheard nodes are most of the nodes the radio reported on. Nodes it never reported on
	/// are unknown and don't count either way.
	static func isMostOfList(unheard: Int, reported: Int) -> Bool {
		unheard > 0 && unheard * 2 >= reported
	}

	static func isDismissed(forNode nodeNum: Int64, store: UserDefaults = .standard) -> Bool {
		store.bool(forKey: key(forNode: nodeNum))
	}

	static func dismiss(forNode nodeNum: Int64, store: UserDefaults = .standard) {
		store.set(true, forKey: key(forNode: nodeNum))
	}

	/// Most of the list is heard again, so the next time it isn't is a new change worth offering for.
	static func clearDismissal(forNode nodeNum: Int64, store: UserDefaults = .standard) {
		store.removeObject(forKey: key(forNode: nodeNum))
	}

	/// Earlier versions stored the count Keep was tapped at and hid the banner until the count went
	/// above it. Carries that over once: still dismissed if the count hasn't gone above it.
	static func migrateCountDismissal(currentCount: Int, forNode nodeNum: Int64, store: UserDefaults = .standard) {
		let oldKey = "unheardOnCurrentLoraDismissedCount.\(nodeNum)"
		guard store.object(forKey: oldKey) != nil else { return }
		if currentCount <= store.integer(forKey: oldKey) {
			dismiss(forNode: nodeNum, store: store)
		}
		store.removeObject(forKey: oldKey)
	}
}

/// Whether the node database asked for after the latest app-initiated LoRa change has been saved.
///
/// Each change asks again after a short wait. When changes come quickly, only the newest one asks.
/// A completion only counts when it belongs to the newest change's request, so a connect-time
/// download, an older change's download, or a save that finishes after a disconnect can't end the wait.
struct LoRaChangeNodeDatabaseTracker {
	private var generation = 0
	private var requestedGeneration = 0
	private var completedGeneration = 0

	var isAwaiting: Bool { completedGeneration != generation }

	/// Records a change and returns its number, to pass to `request` once the wait is over.
	mutating func changed() -> Int {
		generation += 1
		return generation
	}

	/// Whether `changeNumber` is still the newest change and should ask for the node database.
	mutating func request(_ changeNumber: Int) -> Bool {
		guard changeNumber == generation else { return false }
		requestedGeneration = changeNumber
		return true
	}

	/// The download asked for by `changeNumber` was saved, or the ask failed. Ignored unless it is
	/// the newest change's request.
	mutating func finished(_ changeNumber: Int) {
		guard changeNumber == generation, changeNumber == requestedGeneration else { return }
		completedGeneration = changeNumber
	}

	/// A dropped connection never finishes its download; the reconnect brings a fresh one anyway.
	mutating func reset() {
		requestedGeneration = generation
		completedGeneration = generation
	}
}
