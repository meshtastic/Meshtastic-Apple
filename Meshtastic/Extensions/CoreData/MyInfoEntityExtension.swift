//
//  MyInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import CoreData
import MeshtasticProtobufs

extension MyInfoEntity {

	convenience init(
		context: NSManagedObjectContext,
		myInfo: MyNodeInfo,
		peripheralId: String
	) {
		self.init(context: context)
		self.peripheralId = peripheralId
		self.myNodeNum = Int64(myInfo.myNodeNum)
		self.rebootCount = Int32(myInfo.rebootCount)
	}
	
	var messageList: [MessageEntity] {
		self.value(forKey: "allMessages") as? [MessageEntity] ?? [MessageEntity]()
	}

	var unreadMessages: Int {
		let unreadMessages = messageList.filter { ($0 as AnyObject).read == false && ($0 as AnyObject).isEmoji == false }
		return unreadMessages.count
	}
	var hasAdmin: Bool {
		let adminChannel = channels?.filter { ($0 as AnyObject).name?.lowercased() == "admin" }
		return adminChannel?.count ?? 0 > 0
	}
}
