//
//  IntentMessageConverters.swift
//  Meshtastic
//
//  Helpers for converting Core Data entities to SiriKit intent objects (INPerson, INMessage)
//  used by the CarPlay messaging intent handlers.
//

import CoreData
import Intents

enum IntentMessageConverters {

	/// Converts a `UserEntity` to an `INPerson` for use with SiriKit intents.
	static func inPerson(from user: UserEntity) -> INPerson {
		let handle = INPersonHandle(value: String(user.num), type: .unknown)
		return INPerson(
			personHandle: handle,
			nameComponents: nil,
			displayName: user.longName ?? user.shortName ?? "Node \(user.num)",
			image: nil,
			contactIdentifier: String(user.num),
			customIdentifier: String(user.num)
		)
	}

	/// Converts a `MessageEntity` to an `INMessage` for use with SiriKit search results.
	static func inMessage(from message: MessageEntity) -> INMessage {
		let sender: INPerson? = message.fromUser.map { inPerson(from: $0) }
		let recipients: [INPerson]? = message.toUser.map { [inPerson(from: $0)] }
		let dateSent = Date(timeIntervalSince1970: TimeInterval(message.messageTimestamp))
		let groupName: INSpeakableString? = message.channel > 0
			? INSpeakableString(spokenPhrase: "Channel \(message.channel)")
			: nil

		return INMessage(
			identifier: String(message.messageId),
			conversationIdentifier: conversationIdentifier(for: message),
			content: message.messagePayload,
			dateSent: dateSent,
			sender: sender,
			recipients: recipients,
			groupName: groupName,
			messageType: .text
		)
	}

	/// Builds a stable conversation identifier from a message.
	/// Channel messages use "channel-<N>", direct messages use "dm-<nodeNum>".
	static func conversationIdentifier(for message: MessageEntity) -> String {
		if let toUser = message.toUser {
			return "dm-\(toUser.num)"
		}
		return "channel-\(message.channel)"
	}

	/// Searches for `UserEntity` objects whose name matches the given search term.
	static func findUsers(matching searchTerm: String, in context: NSManagedObjectContext) -> [UserEntity] {
		let fetchRequest: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
		fetchRequest.predicate = NSPredicate(
			format: "longName CONTAINS[cd] %@ OR shortName CONTAINS[cd] %@",
			searchTerm, searchTerm
		)
		return (try? context.fetch(fetchRequest)) ?? []
	}

	/// Looks up a `ChannelEntity` by matching name.
	static func findChannels(matching name: String, in context: NSManagedObjectContext) -> [ChannelEntity] {
		let fetchRequest: NSFetchRequest<ChannelEntity> = ChannelEntity.fetchRequest()
		fetchRequest.predicate = NSPredicate(
			format: "name != nil AND name != '' AND name CONTAINS[cd] %@", name
		)
		return (try? context.fetch(fetchRequest)) ?? []
	}

	/// Resolves a channel index from a spoken group name, defaulting to the primary channel.
	static func channelIndex(for name: String, in context: NSManagedObjectContext) -> Int {
		let channels = findChannels(matching: name, in: context)
		return channels.first.map { Int($0.index) } ?? 0
	}
}
