/*
Abstract:
An NSManagedObject subclass for the Message entity.
*/

import CoreData
import SwiftUI
import OSLog

class MessageEntity: NSManagedObject {
	
	// A unique identifier used to avoid duplicates in the persistent store.
	// Constrain the MessageEntity on this attribute in the data model editor.
	@NSManaged var id: UUID
	
	// The characteristics of a Message.
	@NSManaged var messageId: UInt32
	@NSManaged var messageTimestamp: UInt32
	@NSManaged var fromUserId: UInt32
	@NSManaged var toUserId: UInt32
	@NSManaged var fromUserLongName: String
	@NSManaged var toUserLongName: String
	@NSManaged var fromUserShortName: String
	@NSManaged var toUserShortName: String
	@NSManaged var receivedACK: Bool
	@NSManaged var messagePayload: String
	@NSManaged var direction: String
	
	/// Updates a Message instance with the values from a MessageProperties.
	/// Messages should only be updated with the num and ack
	func update(from messageProperties: MessageProperties) throws {
		
		let dictionary = messageProperties.dictionaryValue
		guard let newMessageId = dictionary["messageId"] as? UInt32,
			  let newReceivedACK = dictionary["receivedACK"] as? Bool
		else {
			throw MeshDataError.missingData
		}
		
		messageId = newMessageId
		receivedACK = newReceivedACK
	}
}

extension MessageEntity {
	
	/// An earthquake for use with canvas previews.
	static var preview: MessageEntity {
		let messages = MessageEntity.makeMessagePreviews(count: 1)
		return messages[0]
	}

	@discardableResult
	static func makeMessagePreviews(count: Int) -> [MessageEntity] {
		var messages = [MessageEntity]()
		let viewContext = MeshProvider.preview.container.viewContext
		for index in 0..<count {
			let message = MessageEntity(context: viewContext)
			message.id = UUID()
			//message.messageTimestamp = DatetimeIntervalSince1970(Date().addingTimeInterval(Double(index) * 100))
			//quake.magnitude = .random(in: -1.1...10.0)
			//quake.place = "15km SSW of Cupertino, CA"
			messages.append(message)
		}
		return messages
	}
}

/// A struct encapsulating the properties of a Message.
struct MessageProperties: Decodable {

	// MARK: Codable
	
	private enum CodingKeys: String, CodingKey {
		case messageId
		case messageTimestamp
		case fromUserId
		case toUserId
		case fromUserLongName
		case toUserLongName
		case fromUserShortName
		case toUserShortName
		case receivedACK
		case messagePayload
		case direction
	}
	
	let messageId: UInt32
	let messageTimestamp: UInt32
	let fromUserId: UInt32
	let toUserId: UInt32       		
	let fromUserLongName: String
	let toUserLongName: String
	let fromUserShortName: String
	let toUserShortName: String
	let receivedACK: Bool
	let messagePayload: String
	let direction: String
	
	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		let rawMessageId = try? values.decode(UInt32.self, forKey: .messageId)
		let rawMessageTimestamp = try? values.decode(UInt32.self, forKey: .messageTimestamp)
		let rawFromUserId = try? values.decode(UInt32.self, forKey: .fromUserId)
		let rawToUserId = try? values.decode(UInt32.self, forKey: .toUserId)
		let rawFromUserLongName = try? values.decode(String.self, forKey: .fromUserLongName)
		let rawToUserLongName = try? values.decode(String.self, forKey: .toUserLongName)
		let rawFromUserShortName = try? values.decode(String.self, forKey: .fromUserShortName)
		let rawToUserShortName = try? values.decode(String.self, forKey: .toUserShortName)
		let rawReceivedACK = try? values.decode(Bool.self, forKey: .receivedACK)
		let rawMessagePayload = try? values.decode(String.self, forKey: .messagePayload)
		let rawDirection = try? values.decode(String.self, forKey: .direction)
		
		// Ignore earthquakes with missing data.
		guard let messageId = rawMessageId,
			  let messageTimestamp = rawMessageTimestamp,
			  let fromUserId = rawFromUserId,
			  let toUserId = rawToUserId,
			  let fromUserLongName = rawFromUserLongName,
			  let toUserLongName = rawToUserLongName,
			  let fromUserShortName = rawFromUserShortName,
			  let toUserShortName = rawToUserShortName,
			  let receivedACK = rawReceivedACK,
			  let messagePayload = rawMessagePayload,
			  let direction = rawDirection
		else {
			let values = "messageId = \(rawMessageId?.description ?? "nil"), "
			+ "messageTimestamp = \(rawMessageTimestamp?.description ?? "nil"), "
			+ "fromUserId = \(rawFromUserId?.description ?? "nil"), "
			+ "toUserId = \(rawToUserId?.description ?? "nil"), "
			+ "fromUserLongName = \(rawFromUserLongName?.description ?? "nil"), "
			+ "toUserLongName = \(rawToUserLongName?.description ?? "nil"), "
			+ "fromUserShortName = \(rawFromUserShortName?.description ?? "nil"), "
			+ "toUserShortName = \(rawToUserShortName?.description ?? "nil"), "
			+ "receivedACK = \(rawReceivedACK?.description ?? "nil"), "
			+ "messagePayload = \(rawMessagePayload?.description ?? "nil"), "
			+ "direction = \(rawDirection?.description ?? "nil")"
			

			let logger = Logger(subsystem: "com.example.apple-samplecode.Earthquakes", category: "parsing")
			logger.debug("Ignored: \(values)")

			throw MeshDataError.missingData
		}
		
		self.messageId = messageId
		self.messageTimestamp = messageTimestamp
		self.fromUserId = fromUserId
		self.toUserId = toUserId
		self.fromUserLongName = fromUserLongName
		self.toUserLongName = toUserLongName
		self.fromUserShortName = fromUserShortName
		self.toUserShortName = toUserShortName
		self.receivedACK = receivedACK
		self.messagePayload = messagePayload
		self.direction = direction
		
	}
	
	// The keys must have the same name as the attributes of the Quake entity.
	var dictionaryValue: [String: Any] {
		[
			"messageId": messageId,
			"messageTimestamp": Date(timeIntervalSince1970: TimeInterval(messageTimestamp) / 1000),
			"fromUserId": fromUserId,
			"toUserId": toUserId
		]
	}
}












