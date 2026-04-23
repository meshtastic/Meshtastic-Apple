//
//  MyInfoEntity.swift
//  Meshtastic
//
//  SwiftData model for connected device info.
//

import Foundation
import SwiftData

@Model
final class MyInfoEntity {
	var bleName: String?
	var deviceId: Data?
	var minAppVersion: Int32 = 0
	var myNodeNum: Int64 = 0
	var peripheralId: String?
	var pioEnv: String?
	var rebootCount: Int32 = 0
	var registered: Bool = false

	@Relationship(deleteRule: .cascade, inverse: \ChannelEntity.myInfoChannel)
	var channels: [ChannelEntity] = []

	var myInfoNode: NodeInfoEntity?

	init() {}
}
