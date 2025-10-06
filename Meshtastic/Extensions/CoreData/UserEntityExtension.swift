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
		let unreadMessages = messageList.filter { ($0 as AnyObject).read == false && ($0 as AnyObject).isEmoji == false }
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
		case "HELTECMESHPOCKET":
			return "HELTECMESHPOCKET"
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
		case "TLORAT3S3V1", "TLORAT3S3":
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
		case "SEEEDSOLARNODE":
			return "SEEEDSOLARNODE"
		case "SEEEDWIOTRACKERL1":
			return "SEEEDWIOTRACKERL1"
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

public func createUser(num: Int64, context: NSManagedObjectContext) throws -> UserEntity {
	// Validate Input
	guard num >= 0 else {
		throw CoreDataError.invalidInput(message: "User number cannot be negative.")
	}

	var newUser: UserEntity! // Use an implicitly unwrapped optional, but ensure it's assigned

	context.performAndWait {
		newUser = UserEntity(context: context)
		newUser.num = num
		let userId = num.toHex()
		newUser.userId = userId
		let last4 = String(userId.suffix(4))
		newUser.longName = "Meshtastic \(last4)"
		newUser.shortName = last4
		newUser.hwModel = "UNSET"
	}

	return newUser
}

enum CoreDataError: Error, LocalizedError {
	case invalidInput(message: String)
	case saveFailed(message: String)
	case entityCreationFailed(message: String) // In case UserEntity(context:) fails for some reason

	var errorDescription: String? {
		switch self {
		case .invalidInput(let message):
			return "Core Data Input Error: \(message)"
		case .saveFailed(let message):
			return "Core Data Save Error: \(message)"
		case .entityCreationFailed(let message):
			return "Core Data Entity Creation Error: \(message)"
		}
	}
}
