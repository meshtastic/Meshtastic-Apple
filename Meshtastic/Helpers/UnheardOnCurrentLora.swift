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
/// Keep stores the count it was dismissed at, not a flag. The radio's settings can change from the
/// device menu or the CLI without the app seeing it, so the offer comes back when the count grows.
enum UnheardOnCurrentLoraOffer {
	static func key(forNode nodeNum: Int64) -> String {
		"unheardOnCurrentLoraDismissedCount.\(nodeNum)"
	}

	/// Whether unheard nodes are most of the nodes the radio reported on. Nodes it never reported on
	/// are unknown and don't count either way.
	static func isMostOfList(unheard: Int, reported: Int) -> Bool {
		unheard > 0 && unheard * 2 >= reported
	}

	static func shouldOffer(count: Int, forNode nodeNum: Int64, store: UserDefaults = .standard) -> Bool {
		count > store.integer(forKey: key(forNode: nodeNum))
	}

	static func dismiss(count: Int, forNode nodeNum: Int64, store: UserDefaults = .standard) {
		store.set(count, forKey: key(forNode: nodeNum))
	}

	/// Lowers a kept count when fewer nodes are unheard now, so the next rise offers again.
	/// Without this, switching back to a preset the nodes are heard on and then away again
	/// would need more unheard nodes than last time before offering.
	static func lowerDismissal(toCount count: Int, forNode nodeNum: Int64, store: UserDefaults = .standard) {
		let key = key(forNode: nodeNum)
		if count < store.integer(forKey: key) {
			store.set(count, forKey: key)
		}
	}
}

/// Whether the node database asked for after the latest app-initiated LoRa change has been saved.
///
/// Each change asks again after a short wait. When changes come quickly, only the newest one asks,
/// and a download already under way for older settings doesn't count as the answer.
struct LoRaChangeNodeDatabaseTracker {
	private var generation = 0
	private var requestedGeneration = 0
	private var outstanding = 0

	var isAwaiting: Bool { outstanding > 0 || requestedGeneration != generation }

	/// Records a change and returns its number, to pass to `request` once the wait is over.
	mutating func changed() -> Int {
		generation += 1
		return generation
	}

	/// Whether `changeNumber` is still the newest change and should ask for the node database.
	mutating func request(_ changeNumber: Int) -> Bool {
		guard changeNumber == generation else { return false }
		requestedGeneration = changeNumber
		outstanding += 1
		return true
	}

	/// A node database download finished (saved, or the ask failed).
	mutating func finished() {
		outstanding = max(0, outstanding - 1)
	}

	mutating func reset() {
		requestedGeneration = generation
		outstanding = 0
	}
}
