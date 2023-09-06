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
		
		let unreadMessages = allPrivateMessages.filter{ ($0 as AnyObject).read == false }
		return unreadMessages.count
	}
}
