//
//  UserEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/3/22.
//

import Foundation
import CoreData
import MeshtasticProtobufs

extension UserEntity {

	var messageList: [MessageEntity] {
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "messageTimestamp", ascending: true)]
		fetchRequest.predicate = NSPredicate(format: "((toUser == %@) OR (fromUser == %@)) AND toUser != nil AND fromUser != nil AND isEmoji == false AND admin = false AND portNum != 10", self, self)

		return (try? context.fetch(fetchRequest)) ?? [MessageEntity]()
	}

	var sensorMessageList: [MessageEntity] {
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "messageTimestamp", ascending: true)]
		fetchRequest.predicate = NSPredicate(format: "(fromUser == %@) AND portNum = 10", self)

		return (try? context.fetch(fetchRequest)) ?? [MessageEntity]()
	}

	var unreadMessages: Int {
		let unreadMessages = messageList.filter { ($0 as AnyObject).read == false }
		return unreadMessages.count
	}

	var hardwareImage: String? {
		guard let hwModel else { return nil }
		switch hwModel {
		/// SVG Images for Vendors who are project backers
		/// Heltec
		case "HELTECV3":
			return "HELTECV3"
		case "HELTECWIRELESSPAPER", "HELTECWIRELESSPAPERV10":
			return "HELTECWIRELESSPAPER"
		case "HELTECWIRELESSTRACKER", "HELTECWIRELESSTRACKERV10":
			return "HELTECWIRELESSTRACKER"
		case "HELTECWSLV3":
			return "HELTECWSLV3"
		/// LilyGO
		case "TBEAM", "TBEAM_V0P7":
			return "TBEAM"
		case "TLORAT3S3V1":
			return "TLORAT3S3V1"
		case "TLORAC6":
			return "TLORAC6"
		/// B&O Consulting
		case "NANOG1", "NANOG1EXPLORER":
			return "NANOG1"
		case "NANOG2ULTRA":
			return "NANOG2ULTRA"
		case "STATIONG2":
			return "STATIONG2"
		case "SOLAR_NODE":
			return "SOLAR_NODE"

		case "UNPHONE":
			return "UNPHONE"
		default:
			return "UNSET"
		}
	}
}
public func createUser(num: Int64, context: NSManagedObjectContext) -> UserEntity {
	let newUser = UserEntity(context: context)
	newUser.num = Int64(num)
	let userId = String(format: "%2X", num)
	newUser.userId = "!\(userId)"
	let last4 = String(userId.suffix(4))
	newUser.longName = "Meshtastic \(last4)"
	newUser.shortName = last4
	newUser.hwModel = "UNSET"
	return newUser
}
