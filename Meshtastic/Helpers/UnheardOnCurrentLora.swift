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

	static func shouldOffer(count: Int, forNode nodeNum: Int64, store: UserDefaults = .standard) -> Bool {
		count > store.integer(forKey: key(forNode: nodeNum))
	}

	static func dismiss(count: Int, forNode nodeNum: Int64, store: UserDefaults = .standard) {
		store.set(count, forKey: key(forNode: nodeNum))
	}
}
