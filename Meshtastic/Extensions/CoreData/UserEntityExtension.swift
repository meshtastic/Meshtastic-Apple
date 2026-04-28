//
//  UserEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/3/22.
//

import Foundation
import SwiftData
import MeshtasticProtobufs

extension UserEntity {
	@MainActor
	var messageList: [MessageEntity] {
		let context = PersistenceController.shared.context
		let messages = (self.sentMessages ?? []) + (self.receivedMessages ?? [])
		return messages.filter { msg in
			msg.toUser != nil && msg.fromUser != nil && !msg.isEmoji && !msg.admin && msg.portNum != 10
		}.sorted { $0.messageTimestamp < $1.messageTimestamp }
	}

	@MainActor
	var mostRecentMessage: MessageEntity? {
		guard self.lastMessage != nil else { return nil }
		return messageList.last
	}

	@MainActor
	var sensorMessageList: [MessageEntity] {
		return (self.sentMessages ?? []).filter { $0.portNum == 10 }
			.sorted { $0.messageTimestamp < $1.messageTimestamp }
	}

	@MainActor
	func unreadMessages(context: ModelContext, skipLastMessageCheck: Bool = false) -> Int {
		guard self.lastMessage != nil || skipLastMessageCheck else { return 0 }
		return messageList.filter { !$0.read }.count
	}

	@MainActor
	var unreadMessages: Int { unreadMessages(context: PersistenceController.shared.context) }

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
		case "HELTECV4":
			return "HELTECV4"
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
		/// Muzi Works
		case "MUZIR1NEO":
			return "MUZIR1NEO"
		case "STATIONG2":
			return "STATIONG2"
		/// Elecrow
		case "THINKNODEM1":
			return "THINKNODEM1"
		case "THINKNODEM2":
			return "THINKNODEM2"
		case "THINKNODEM3":
			return "THINKNODEM3"
		case "THINKNODEM4":
			return "THINKNODEM4"
		/// DIY Devices
		case "RPIPICO":
			return "RPIPICO"
		default:
			return "UNSET"
		}
	}
}

func createUser(num: Int64, context: ModelContext) throws -> UserEntity {
	// Validate Input
	guard num >= 0 else {
		throw CoreDataError.invalidInput(message: "User number cannot be negative.")
	}

	let newUser = UserEntity()
	newUser.num = num
	let userId = num.toHex()
	newUser.userId = userId
	let last4 = String(userId.suffix(4))
	newUser.longName = "Meshtastic \(last4)"
	newUser.shortName = last4
	newUser.hwModel = "UNSET"
	newUser.unmessagable = false
	context.insert(newUser)
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
