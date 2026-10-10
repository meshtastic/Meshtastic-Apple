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

	// MARK: Multi-radio (feature 021)

	/// When the app last finished connecting to this radio.
	var lastConnected: Date?
	/// Reconnect to this radio on launch and after it drops. Replaces the single preferred radio.
	var autoConnect: Bool = false
	/// `TransportType` raw value of the last connection (BLE, TCP, serial).
	var transport: String?
	/// Position in the user's radio list.
	var sortOrder: Int32 = 0
	/// Colour used to tell this radio apart in the UI, as `#RRGGBB`. Nil means the default.
	var displayColor: String?

	@Relationship(deleteRule: .cascade, inverse: \ChannelEntity.myInfoChannel)
	var channels: [ChannelEntity] = []

	var myInfoNode: NodeInfoEntity?

	init() {}
}
