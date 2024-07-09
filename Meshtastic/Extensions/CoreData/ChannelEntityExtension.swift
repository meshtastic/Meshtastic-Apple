//
//  ChannelEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/22.
//
import Foundation
import CoreData
import MeshtasticProtobufs

extension ChannelEntity {

	var allPrivateMessages: [MessageEntity] {
		let predicate = NSPredicate(format: "channel == %d", self.index)
		return Array((self.channelMessages ?? []).filtered(using: predicate)) as? [MessageEntity] ?? []
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
