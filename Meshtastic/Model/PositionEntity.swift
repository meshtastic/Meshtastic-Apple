//
//  PositionEntity.swift
//  Meshtastic
//
//  SwiftData model for node positions.
//

import Foundation
import SwiftData

@Model
final class PositionEntity {
	var altitude: Int32 = 0
	var heading: Int32 = 0
	var latest: Bool = false
	var latitudeI: Int32 = 0
	var longitudeI: Int32 = 0
	var precisionBits: Int32 = 32
	var rssi: Int32 = 0
	var satsInView: Int32 = 0
	var seqNo: Int32 = 0
	var snr: Float = 0.0
	var speed: Int32 = 0
	var time: Date?
	/// Mesh packet id this position arrived in, 0 when unknown. With the sender, identifies a
	/// packet heard by several local radios so it is stored once (feature 021).
	var packetId: Int64 = 0

	var nodePosition: NodeInfoEntity?

	init() {}
}
