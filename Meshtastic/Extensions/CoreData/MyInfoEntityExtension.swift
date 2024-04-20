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
		let unreadMessages = messageList.filter{ ($0 as AnyObject).read == false && ($0 as AnyObject).isEmoji == false }
		return unreadMessages.count
	}
	var hasAdmin: Bool {
		let adminChannel = channels?.filter{ ($0 as AnyObject).name?.lowercased() == "admin" }
		return adminChannel?.count ?? 0 > 0
	}
}
