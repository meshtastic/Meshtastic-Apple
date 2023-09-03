//
//  UserEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/3/22.
//

import Foundation

extension UserEntity {

	var messageList: [MessageEntity] {
		self.value(forKey: "allMessages") as? [MessageEntity] ?? [MessageEntity]()
	}

	var adminMessageList: [MessageEntity] {
		self.value(forKey: "adminMessages") as? [MessageEntity] ?? [MessageEntity]()
	}
	
	var unreadMessages: Int {
		let unreadMessages = messageList.filter{ ($0 as AnyObject).read == false } 
		return unreadMessages.count
	}
}
