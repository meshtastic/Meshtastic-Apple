//
//  NodeObservationEntity.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import SwiftData

/// One local radio's view of one mesh node (feature 021).
///
/// With several radios connected, the same node is heard at different signal strengths and hop
/// counts, and can be a favorite or ignored on one radio but not another. Node identity (user,
/// keys, positions, telemetry) stays on `NodeInfoEntity`, stored once; what depends on which radio
/// is listening lives here, one row per (radio, node). `NodeInfoEntity`'s own copies of these
/// fields become aggregates across radios, so existing queries keep working.
///
/// Flat node numbers instead of relationships keep lookups to a single indexed-by-uniqueness
/// fetch on `key` (the project targets iOS 17, so no `#Index`).
@Model
final class NodeObservationEntity {
	/// `"\(radioNum):\(nodeNum)"`. Unique, so a second insert for the same pair updates the row.
	@Attribute(.unique) var key: String = ""
	/// Node number of the local radio that made the observation.
	var radioNum: Int64 = 0
	/// Node number of the observed node.
	var nodeNum: Int64 = 0
	var firstHeard: Date?
	var lastHeard: Date?
	var hopsAway: Int32 = 0
	var snr: Float = 0.0
	var rssi: Int32 = 0
	var viaMqtt: Bool = false
	/// The observing radio's channel slot the node was last heard on.
	var channel: Int32 = 0
	var favorite: Bool = false
	var ignored: Bool = false
	var isKeyManuallyVerified: Bool = false
	/// Remote-admin session with this node, held by the observing radio.
	var sessionPasskey: Data?
	var sessionExpiration: Date?
	/// The observing radio's NodeInfo.heard_on_current_lora (firmware 2.8.1+): whether it has
	/// heard the node on its current LoRa settings. Nil when it doesn't send the field or no
	/// longer has the node. Each radio answers for its own settings, so this isn't aggregated:
	/// a window shows its radio's (`NodeInfoEntity.heardOnCurrentLora` is `main`'s one-radio copy).
	var heardOnCurrentLora: Bool?

	init() {}

	init(radioNum: Int64, nodeNum: Int64) {
		self.key = Self.key(radioNum: radioNum, nodeNum: nodeNum)
		self.radioNum = radioNum
		self.nodeNum = nodeNum
	}

	static func key(radioNum: Int64, nodeNum: Int64) -> String {
		"\(radioNum):\(nodeNum)"
	}
}
