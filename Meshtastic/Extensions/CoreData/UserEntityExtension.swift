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
	/// SVG Images for Vendors who are signed project backers
	var hardwareImage: String? {
		guard let hwModel else { return nil }
		switch hwModel {
		/// Heltec
		case "HELTECHT62":
			return "HELTECHT62"
		case "HELTECMESHNODET114":
			return "HELTECMESHNODET114"
		case "HELTECV3":
			return "HELTECV3"
		case "HELTECVISIONMASTERE213":
			return "HELTECVISIONMASTERE213"
		case "HELTECVISIONMASTERE290":
			return "HELTECVISIONMASTERE290"
		case "HELTECWIRELESSPAPER", "HELTECWIRELESSPAPERV10":
			return "HELTECWIRELESSPAPER"
		case "HELTECWIRELESSTRACKER", "HELTECWIRELESSTRACKERV10":
			return "HELTECWIRELESSTRACKER"
		case "HELTECWSLV3":
			return "HELTECWSLV3"
		/// LilyGO
		case "TDECK":
			return "TDECK"
		case "TECHO":
			return "TECHO"
		case "TWATCHS3":
			return "TWATCHS3"
		case "LILYGOTBEAMS3CORE":
			return "LILYGOTBEAMS3CORE"
		case "TBEAM", "TBEAM_V0P7":
			return "TBEAM"
		case "TLORAC6":
			return "TLORAC6"
		case "TLORAT3S3EPAPER":
			return "TLORAT3S3EPAPER"
		case "TLORAT3S3V1":
			return "TLORAT3S3V1"
		case "TLORAV211P6":
			return "TLORAV211P6"
		case "TLORAV211P8":
			return "TLORAV211P8"
		/// Seeed Studio
		case "SENSECAPINDICATOR":
			return "SENSECAPINDICATOR"
		case "TRACKERT1000E":
			return "TRACKERT1000E"
		case "SEEEDXIAOS3":
			return "SEEEDXIAOS3"
		case "WIOWM1110":
			return "WIOWM1110"
		/// RAK Wireless
		case "RAK4631":
			return "RAK4631"
		case "RAK11310":
			return "RAK11310"
		case "WISMESHTAP":
			return "WISMESHTAP"
		/// B&Q Consulting
		case "NANOG1", "NANOG1EXPLORER":
			return "NANOG1"
		case "NANOG2ULTRA":
			return "NANOG2ULTRA"
		case "STATIONG2":
			return "STATIONG2"
		/// DIY Devices
		case "RPIPICO":
			return "RPIPICO"
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
