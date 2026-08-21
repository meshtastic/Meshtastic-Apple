//
//  ChannelEntity+Proto.swift
//  Meshtastic
//

import Foundation
import MeshtasticProtobufs

extension ChannelEntity {
	func update(from channel: Channel) {
		id = Int32(bitPattern: channel.settings.id)
		index = channel.index
		uplinkEnabled = channel.settings.uplinkEnabled
		downlinkEnabled = channel.settings.downlinkEnabled
		name = channel.settings.name
		role = Int32(channel.role.rawValue)
		psk = channel.settings.psk
		if channel.settings.hasModuleSettings {
			positionPrecision = Int32(truncatingIfNeeded: channel.settings.moduleSettings.positionPrecision)
			mute = channel.settings.moduleSettings.isMuted
		} else {
			positionPrecision = 0
			mute = false
		}
	}

	var settingsProto: ChannelSettings {
		var settings = ChannelSettings()
		settings.name = name ?? ""
		settings.psk = psk ?? Data()
		settings.id = UInt32(bitPattern: id)
		settings.uplinkEnabled = uplinkEnabled
		settings.downlinkEnabled = downlinkEnabled
		settings.moduleSettings.positionPrecision = UInt32(truncatingIfNeeded: positionPrecision)
		settings.moduleSettings.isMuted = mute
		return settings
	}
}
