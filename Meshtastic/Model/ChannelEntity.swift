//
//  ChannelEntity.swift
//  Meshtastic
//
//  SwiftData model for channels.
//

import Foundation
import SwiftData

@Model
final class ChannelEntity {
	var downlinkEnabled: Bool = false
	var id: Int32 = 0
	var index: Int32 = 0
	var mute: Bool = false
	var name: String?
	var positionPrecision: Int32 = 32
	var psk: Data?
	var role: Int32 = 0
	var uplinkEnabled: Bool = false
	/// `ChannelIdentity` key: equal on every radio that has this same channel, whatever the slot
	/// index (feature 021, D-14). Nil until computed from the owning radio's LoRa settings.
	var channelKey: String?

	var myInfoChannel: MyInfoEntity?

	init() {}
}
