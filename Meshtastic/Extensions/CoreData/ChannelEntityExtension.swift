//
//  ChannelEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/22.
//
import Foundation

extension ChannelEntity {

	var allPrivateMessages: [MessageEntity] {

		self.value(forKey: "allPrivateMessages") as? [MessageEntity] ?? [MessageEntity]()
	}

	var unreadMessages: Int {

		let unreadMessages = allPrivateMessages.filter { ($0 as AnyObject).read == false }
		return unreadMessages.count
	}

	var protoBuf: Channel {
		var channel = Channel()
		channel.index = self.index
		channel.settings.name = self.name ?? ""
		channel.settings.psk = self.psk ?? Data()
		channel.role = Channel.Role(rawValue: Int(self.role)) ?? Channel.Role.secondary
		channel.settings.moduleSettings.positionPrecision = UInt32(self.positionPrecision)
		return channel
	}
}
