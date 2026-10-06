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

/// The radio whose heard-on-current-LoRa answers the shared node rows hold (feature 021,
/// review V35-2).
///
/// `main`'s #2575 stores one radio's answers on the node rows, and they outlast its connection.
/// When a different radio is next connected on its own they aren't its answers, so they're
/// cleared before it stores or shows any (`AccessoryManager.claimHeardOnCurrentLora(for:)`), and
/// none are kept while several radios are connected. Recorded at launch, like `BackfillOwner`: a
/// store from before feature 021 holds the preferred radio's answers.
enum HeardOnCurrentLoraAnswers {
	static let nodeNumKey = "multiRadio.heardOnCurrentLoraRadioNum"

	/// The radio the stored answers are, 0 for none; the preferred radio when none is recorded.
	static func radioNum(in store: UserDefaults = .standard) -> Int64 {
		(store.object(forKey: nodeNumKey) as? NSNumber)?.int64Value ?? PreferredRadio.nodeNum
	}

	static func set(_ radioNum: Int64, in store: UserDefaults = .standard) {
		store.set(NSNumber(value: radioNum), forKey: nodeNumKey)
	}

	/// Records the preferred radio, unless a radio is recorded already. At launch, before a
	/// connect can change the preferred radio.
	static func recordIfNeeded(in store: UserDefaults = .standard) {
		guard store.object(forKey: nodeNumKey) == nil else { return }
		set(PreferredRadio.nodeNum, in: store)
	}

	/// The store was renumbered (the 2.8 node number change): the radio's answers are still its own.
	static func renumber(from oldNum: Int64, to newNum: Int64, in store: UserDefaults = .standard) {
		guard (store.object(forKey: nodeNumKey) as? NSNumber)?.int64Value == oldNum else { return }
		set(newNum, in: store)
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
