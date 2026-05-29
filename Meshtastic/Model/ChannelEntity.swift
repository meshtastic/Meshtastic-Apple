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

	var myInfoChannel: MyInfoEntity?

	init() {}
}
