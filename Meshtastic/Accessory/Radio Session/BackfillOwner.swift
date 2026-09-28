//
//  BackfillOwner.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation

/// The radio a store's rows from before feature 021 belong to, for the backfill that gives them
/// their radio columns (T193). Recorded at launch, before any connect can change the preferred
/// radio: a switch to another radio moves `PreferredRadio` before that radio connects, and the old
/// rows must still go to the radio they came from. Cleared once nothing is left to backfill.
enum BackfillOwner {
	private static let nodeNumKey = "multiRadio.backfillOwnerNum"
	private static let peripheralIdKey = "multiRadio.backfillOwnerPeripheral"

	struct Radio: Equatable {
		let nodeNum: Int64
		let peripheralId: String
	}

	/// The recorded radio, or the preferred one when none is recorded.
	static func current(in store: UserDefaults = .standard) -> Radio {
		if let num = (store.object(forKey: nodeNumKey) as? NSNumber)?.int64Value, num != 0 {
			return Radio(nodeNum: num, peripheralId: store.string(forKey: peripheralIdKey) ?? "")
		}
		return Radio(nodeNum: PreferredRadio.nodeNum, peripheralId: PreferredRadio.peripheralId)
	}

	/// Records the preferred radio as the owner, unless one is recorded already.
	static func recordIfNeeded(in store: UserDefaults = .standard) {
		guard store.object(forKey: nodeNumKey) == nil, PreferredRadio.nodeNum != 0 else { return }
		store.set(NSNumber(value: PreferredRadio.nodeNum), forKey: nodeNumKey)
		store.set(PreferredRadio.peripheralId, forKey: peripheralIdKey)
	}

	/// The store was renumbered (the 2.8 node number change): an owner recorded under the old
	/// number is the same radio under the new one (T213). Otherwise the backfill would credit the
	/// old rows to a number no radio has.
	static func renumber(from oldNum: Int64, to newNum: Int64, in store: UserDefaults = .standard) {
		guard (store.object(forKey: nodeNumKey) as? NSNumber)?.int64Value == oldNum else { return }
		store.set(NSNumber(value: newNum), forKey: nodeNumKey)
	}

	static func clear(in store: UserDefaults = .standard) {
		store.removeObject(forKey: nodeNumKey)
		store.removeObject(forKey: peripheralIdKey)
	}
}
