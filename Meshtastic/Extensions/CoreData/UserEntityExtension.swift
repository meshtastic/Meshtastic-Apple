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
		self.value(forKey: "allMessages") as? [MessageEntity] ?? [MessageEntity]()
	}

	var sensorMessageList: [MessageEntity] {
		self.value(forKey: "detectionSensorMessages") as? [MessageEntity] ?? [MessageEntity]()
	}

	var unreadMessages: Int {
		let unreadMessages = messageList.filter { ($0 as AnyObject).read == false }
		return unreadMessages.count
	}
	
	var hardwareImage: String? {
		guard let hwModel else { return nil }
		switch hwModel {
		case "HELTECV1", "HELTECV3", "HELTECV20", "HELTECV21":
			return "HELTECV3"
		case "HELTECWIRELESSPAPER", "HELTECWIRELESSPAPERV10":
			return "HELTECWIRELESSPAPER"
		case "HELTECWIRELESSTRACKER", "HELTECWIRELESSTRACKERV10":
			return "HELTECWIRELESSTRACKER"
		case "HELTECWSLV3":
			return "HELTECWSLV3"
		case "LILYGOTBEAMSCORE":
			return "LILYGOTBEAMS3CORE"
		case "NANOG1", "NANOG1EXPLORER":
			return "NANOG1"
		case "NANOG2ULTRA":
			return "NANOG2ULTRA"
		case "RAK4631":
			return "RAK4631"
		case "RAK11200":
			return "RAK11200"
		case "SOLAR_NODE":
			return "SOLAR_NODE"
		case "STATIONG1":
			return "STATIONG1"
		case "ТВЕАМ", "TBEAMVOP7":
			return "ТВЕАМ"
		case "TECHO":
			return "TECHO"
		case "TLORAV1", "TLORAV11P3":
			return "TLORAV1"
		case "TLORAV2", "TLORAT3S3", "TLORAV211P6", "TLORAV211P8":
			return "TLORABOARD"
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
