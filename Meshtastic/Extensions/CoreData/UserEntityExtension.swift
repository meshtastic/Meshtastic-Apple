//
//  UserEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/3/22.
//

import Foundation
import CoreData

extension UserEntity {
	convenience init(
		context: NSManagedObjectContext,
		user: User,
		num: Int
	) {
		self.init(context: context)
		self.userId = user.id
		self.num = Int64(num)
		self.longName = user.longName
		self.shortName = user.shortName
		self.hwModel = String(describing: user.hwModel).uppercased()
		self.isLicensed = user.isLicensed
		self.role = Int32(user.role.rawValue)
	}
	
	convenience init(context: NSManagedObjectContext, num: Int) {
		self.init(context: context)
		self.num = Int64(num)
		let userId = String(format: "!%2X", num)
		self.userId = userId
		let last4 = String(userId.suffix(4))
		self.longName = "Meshtastic \(last4)"
		self.shortName = last4
		self.hwModel = "UNSET"
	}

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
		let unreadMessages = messageList.filter { ($0 as AnyObject).read == false }
		return unreadMessages.count
	}
}
