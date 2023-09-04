//
//  MyInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation

extension MyInfoEntity {
	
	var messageList: [MessageEntity] {
		self.value(forKey: "allMessages") as? [MessageEntity] ?? [MessageEntity]()
	}
	
	var unreadMessages: Int {
		let unreadMessages = messageList.filter{ ($0 as AnyObject).read == false }
		return unreadMessages.count
	}
}
