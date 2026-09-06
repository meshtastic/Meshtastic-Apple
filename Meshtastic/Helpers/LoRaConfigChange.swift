//
//  LoRaConfigChange.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Foundation

/// The LoRa settings that decide which channel the radio actually listens on.
///
/// Changing any of these moves the radio to a different frequency, and the node db does not move
/// with it: every node in the list was heard under the old settings and may no longer be reachable.
/// Firmware will eventually report this per node (`NodeInfo.heard_on_current_lora`), but the app can
/// already tell, because it stores the settings and the last-heard time for every node.
struct LoRaChannelSettings: Equatable {
	let regionCode: Int32
	let modemPreset: Int32
	let usePreset: Bool
	let channelNum: Int32
	let overrideFrequency: Float
	/// Only meaningful when `usePreset` is false — a custom setup is defined by these three.
	let bandwidth: Int32
	let spreadFactor: Int32
	let codingRate: Int32

	/// Whether moving from `other` to this puts the radio on a different channel.
	///
	/// The custom radio parameters only count when the radio is actually using them; editing
	/// bandwidth while `usePreset` is true changes a stored value the radio is ignoring.
	func movesOffChannel(from other: LoRaChannelSettings) -> Bool {
		if regionCode != other.regionCode { return true }
		if usePreset != other.usePreset { return true }
		if channelNum != other.channelNum { return true }
		if overrideFrequency != other.overrideFrequency { return true }

		if usePreset {
			return modemPreset != other.modemPreset
		}
		return bandwidth != other.bandwidth
			|| spreadFactor != other.spreadFactor
			|| codingRate != other.codingRate
	}
}

/// Records when the connected radio last moved to a different channel, so nodes heard before that
/// can be marked — and offered up for deletion, since they have no channel in common any more.
enum LoRaConfigChange {

	/// Kept in `UserDefaults` rather than the store: it is one timestamp per radio, and
	/// `MeshtasticSchemaV1` is frozen, so a persisted model change would force a new schema version
	/// and a migration stage for a single date.
	static func key(forNode nodeNum: Int64) -> String {
		"loraChannelChangedAt.\(nodeNum)"
	}

	static func changedAt(forNode nodeNum: Int64, store: UserDefaults = .standard) -> Date? {
		store.object(forKey: key(forNode: nodeNum)) as? Date
	}

	static func recordChange(forNode nodeNum: Int64, at date: Date = .now, store: UserDefaults = .standard) {
		store.set(date, forKey: key(forNode: nodeNum))
	}

	static func clear(forNode nodeNum: Int64, store: UserDefaults = .standard) {
		store.removeObject(forKey: key(forNode: nodeNum))
		store.removeObject(forKey: dismissedKey(forNode: nodeNum))
	}

	// MARK: - Offer to clean up

	private static func dismissedKey(forNode nodeNum: Int64) -> String {
		"loraChannelChangeDismissedAt.\(nodeNum)"
	}

	/// Records that the user has seen the offer for this change and does not want it again.
	///
	/// Stored as the change's own timestamp rather than a flag, so the next channel change offers
	/// again instead of staying silent forever.
	static func dismissOffer(forNode nodeNum: Int64, store: UserDefaults = .standard) {
		guard let changedAt = changedAt(forNode: nodeNum, store: store) else { return }
		store.set(changedAt, forKey: dismissedKey(forNode: nodeNum))
	}

	/// Whether to offer the cleanup for this radio's most recent channel change.
	static func shouldOfferCleanup(forNode nodeNum: Int64, store: UserDefaults = .standard) -> Bool {
		guard let changedAt = changedAt(forNode: nodeNum, store: store) else { return false }
		let dismissed = store.object(forKey: dismissedKey(forNode: nodeNum)) as? Date
		return dismissed != changedAt
	}

	/// Whether this node has not been heard since the radio changed channel.
	///
	/// A node heard over MQTT arrived over the internet rather than this radio's channel, so hearing
	/// it says nothing about whether the two share a channel. A node with no last-heard time at all
	/// has never been heard, so there is nothing to compare and it is left unflagged — that is a
	/// different problem from having gone quiet.
	static func isUnheard(lastHeard: Date?, viaMqtt: Bool, changedAt: Date?) -> Bool {
		guard let changedAt else { return false }
		guard !viaMqtt else { return false }
		guard let lastHeard, lastHeard > Date(timeIntervalSince1970: 0) else { return false }
		return lastHeard < changedAt
	}
}
