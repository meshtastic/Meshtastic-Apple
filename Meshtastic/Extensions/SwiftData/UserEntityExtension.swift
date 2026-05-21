//
//  UserEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/3/22.
//

import Foundation
@preconcurrency import SwiftData
import MeshtasticProtobufs

extension UserEntity {
	/// Builds a predicate for messages involving this user, excluding emoji/admin/sensor messages
	@MainActor
	private static func userMessagePredicate(userNum: Int64, portNum: Int32 = 10) -> Predicate<MessageEntity> {
		return #Predicate<MessageEntity> {
			($0.fromUser?.num == userNum || $0.toUser?.num == userNum)
			&& $0.isEmoji == false && $0.admin == false && $0.portNum != portNum
		}
	}

	@MainActor
	var messageList: [MessageEntity] {
		guard let ctx = modelContext else { return [] }
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: Self.userMessagePredicate(userNum: self.num),
			sortBy: [SortDescriptor(\MessageEntity.messageTimestamp)]
		)
		return (try? ctx.fetch(descriptor)) ?? []
	}

	@MainActor
	var mostRecentMessage: MessageEntity? {
		guard let ctx = modelContext, self.lastMessage != nil else { return nil }
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: Self.userMessagePredicate(userNum: self.num),
			sortBy: [SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? ctx.fetch(descriptor).first
	}

	@MainActor
	var sensorMessageList: [MessageEntity] {
		guard let ctx = modelContext else { return [] }
		let userNum = self.num
		let portNum: Int32 = 10
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { $0.fromUser?.num == userNum && $0.portNum == portNum },
			sortBy: [SortDescriptor(\MessageEntity.messageTimestamp)]
		)
		return (try? ctx.fetch(descriptor)) ?? []
	}

	@MainActor
	func unreadMessages(context: ModelContext, skipLastMessageCheck: Bool = false) -> Int {
		guard self.lastMessage != nil || skipLastMessageCheck else { return 0 }
		guard let ctx = modelContext else { return 0 }
		let userNum = self.num
		let portNum: Int32 = 10
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				($0.fromUser?.num == userNum || $0.toUser?.num == userNum)
				&& $0.read == false
				&& $0.isEmoji == false && $0.admin == false && $0.portNum != portNum
			}
		)
		return (try? ctx.fetchCount(descriptor)) ?? 0
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
		throw PersistenceError.invalidInput(message: "User number cannot be negative.")
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

enum PersistenceError: Error, LocalizedError {
	case invalidInput(message: String)
	case saveFailed(message: String)
	case entityCreationFailed(message: String)

	var errorDescription: String? {
		switch self {
		case .invalidInput(let message):
			return "Persistence Input Error: \(message)"
		case .saveFailed(let message):
			return "Persistence Save Error: \(message)"
		case .entityCreationFailed(let message):
			return "Persistence Entity Creation Error: \(message)"
		}
	}
}
