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

	convenience init(
		context: NSManagedObjectContext,
		id: Int32,
		index: Int32,
		uplinkEnabled: Bool,
		downlinkEnabled: Bool,
		name: String?,
		role: Int32,
		psk: Data,
		positionPrecision: Int32
	) {
		self.init(context: context)
		self.id = id
		self.index = index
		self.uplinkEnabled = uplinkEnabled
		self.downlinkEnabled = downlinkEnabled
		self.name = name
		self.role = role
		self.psk = psk
		self.positionPrecision = positionPrecision
	}
	
	convenience init(
		context: NSManagedObjectContext,
		channel: Channel
	) {
		self.init(context: context)
		self.id = Int32(channel.index)
		self.index = Int32(channel.index)
		self.uplinkEnabled = channel.settings.uplinkEnabled
		self.downlinkEnabled = channel.settings.downlinkEnabled
		self.name = channel.settings.name
		self.role = Int32(channel.role.rawValue)
		self.psk = channel.settings.psk
		if channel.settings.hasModuleSettings {
			self.positionPrecision = Int32(truncatingIfNeeded: channel.settings.moduleSettings.positionPrecision)
			self.mute = channel.settings.moduleSettings.isClientMuted
		}
	}
	
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
