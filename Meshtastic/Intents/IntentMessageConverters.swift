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
	static let meshtasticDomain = "@meshtastic.local"

	/// Converts a `UserEntity` to an `INPerson` for use with SiriKit intents.
	/// Uses the `@meshtastic.local` email format so the handle matches `CPContactMessageButton` identifiers.
	static func inPerson(from user: UserEntity) -> INPerson {
		let handleValue = "\(user.num)\(meshtasticDomain)"
		let handle = INPersonHandle(value: handleValue, type: .emailAddress)
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
		let groupName: INSpeakableString? = message.toUser == nil
			? INSpeakableString(spokenPhrase: channelDisplayName(for: message.channel, named: nil))
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
		if let nodeNum = directMessageNodeNum(from: searchTerm) {
			let fetchRequest: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
			fetchRequest.fetchLimit = 1
			fetchRequest.predicate = NSPredicate(format: "num == %lld", nodeNum)
			return (try? context.fetch(fetchRequest)) ?? []
		}

		let fetchRequest: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
		fetchRequest.predicate = NSPredicate(
			format: "longName CONTAINS[cd] %@ OR shortName CONTAINS[cd] %@ OR userId CONTAINS[cd] %@",
			searchTerm, searchTerm, searchTerm
		)
		return (try? context.fetch(fetchRequest)) ?? []
	}

	/// Looks up a `ChannelEntity` by matching name.
	static func findChannels(matching name: String, in context: NSManagedObjectContext) -> [ChannelEntity] {
		if let explicitIndex = channelIndex(fromHandleOrName: name) {
			let fetchRequest: NSFetchRequest<ChannelEntity> = ChannelEntity.fetchRequest()
			fetchRequest.fetchLimit = 1
			fetchRequest.predicate = NSPredicate(format: "index == %d", explicitIndex)
			return (try? context.fetch(fetchRequest)) ?? []
		}

		let fetchRequest: NSFetchRequest<ChannelEntity> = ChannelEntity.fetchRequest()
		fetchRequest.predicate = NSPredicate(
			format: "name != nil AND name != '' AND name CONTAINS[cd] %@", name
		)
		return (try? context.fetch(fetchRequest)) ?? []
	}

	/// Resolves a channel index from a spoken group name, defaulting to the primary channel.
	static func channelIndex(for name: String, in context: NSManagedObjectContext) -> Int {
		if let explicitIndex = channelIndex(fromHandleOrName: name) {
			return explicitIndex
		}

		let channels = findChannels(matching: name, in: context)
		return channels.first.map { Int($0.index) } ?? 0
	}

	static func directMessageNodeNum(from value: String) -> Int64? {
		if let nodeNum = Int64(value) {
			return nodeNum
		}

		if value.hasSuffix(meshtasticDomain) {
			let rawValue = String(value.dropLast(meshtasticDomain.count))
			return Int64(rawValue)
		}

		return nil
	}

	static func channelIndex(fromHandleOrName value: String) -> Int? {
		if value.caseInsensitiveCompare("Primary Channel") == .orderedSame {
			return 0
		}

		if value.hasPrefix("Channel "), let index = Int(value.dropFirst("Channel ".count)) {
			return index
		}

		let channelPrefix = "channel-"
		if value.hasPrefix(channelPrefix) {
			let remainder = String(value.dropFirst(channelPrefix.count))
			let rawIndex = remainder.hasSuffix(meshtasticDomain)
				? String(remainder.dropLast(meshtasticDomain.count))
				: remainder
			return Int(rawIndex)
		}

		return nil
	}

	static func channelDisplayName(for index: Int32, named name: String?) -> String {
		if let name, !name.isEmpty {
			return name
		}

		if index == 0 {
			return "Primary Channel"
		}

		return "Channel \(index)"
	}
}
