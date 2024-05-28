//
//  UserEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/3/22.
//

import Foundation
import CoreData

extension UserEntity {
	

	var messageList: [MessageEntity] {
		self.value(forKey: "allMessages") as? [MessageEntity] ?? [MessageEntity]()
	}

	var adminMessageList: [MessageEntity] {
		self.value(forKey: "adminMessages") as? [MessageEntity] ?? [MessageEntity]()
	}
	
	var sensorMessageList: [MessageEntity] {
		self.value(forKey: "detectionSensorMessages") as? [MessageEntity] ?? [MessageEntity]()
	}
	
	var unreadMessages: Int {
		let unreadMessages = messageList.filter{ ($0 as AnyObject).read == false } 
		return unreadMessages.count
	}
}


public func createUser(num: Int64, context: NSManagedObjectContext) -> UserEntity {
	let newUser = UserEntity(context: context)
	newUser.num = Int64(num)
	let userId = String(format:"%2X", num)
	newUser.userId = "!\(userId)"
	let last4 = String(userId.suffix(4))
	newUser.longName = "Meshtastic \(last4)"
	newUser.shortName = last4
	newUser.hwModel = "UNSET"
	return newUser
}
