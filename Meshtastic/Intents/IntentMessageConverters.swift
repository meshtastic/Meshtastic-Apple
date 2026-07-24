//
//  IntentMessageConverters.swift
//  Meshtastic
//
//  Helpers for converting Core Data entities to SiriKit intent objects (INPerson, INMessage)
//  used by the CarPlay messaging intent handlers.
//

import Intents
@preconcurrency import SwiftData

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
	static func findUsers(matching searchTerm: String, in context: ModelContext) -> [UserEntity] {
		if let nodeNum = directMessageNodeNum(from: searchTerm) {
			let descriptor = FetchDescriptor<UserEntity>(
				predicate: #Predicate<UserEntity> { user in
					user.num == nodeNum
				}
			)
			return (try? context.fetch(descriptor)) ?? []
		}

		let normalized = searchTerm.lowercased()
		let users = (try? context.fetch(FetchDescriptor<UserEntity>())) ?? []
		return users.filter { user in
			(user.longName?.lowercased().contains(normalized) ?? false)
				|| (user.shortName?.lowercased().contains(normalized) ?? false)
				|| (user.userId?.lowercased().contains(normalized) ?? false)
		}
	}

	/// Looks up a `ChannelEntity` by matching name, scoped to the connected
	/// node's channel table.
	///
	/// Scoping matters: `ChannelEntity` rows exist per `MyInfoEntity`, so anyone
	/// who has ever connected more than one radio has duplicate rows per index.
	/// Unscoped, "Channel 2" matched several identical channels and Siri replied
	/// with a disambiguation between indistinguishable options (or failed) —
	/// breaking channel replies from CarPlay.
	@MainActor
	static func findChannels(matching name: String, in context: ModelContext) -> [ChannelEntity] {
		let connectedNum = AccessoryManager.shared.activeDeviceNum

		// Filter to the connected node's myInfo in Swift, not the predicate —
		// optional-relationship comparisons in #Predicate crash SwiftData on iOS 26.
		func scoped(_ channels: [ChannelEntity]) -> [ChannelEntity] {
			guard let connectedNum else { return channels }
			let mine = channels.filter { $0.myInfoChannel?.myNodeNum == connectedNum }
			// Fall back to the unscoped list if the connected node has no matching
			// row (e.g. channel DB not yet synced) rather than failing outright.
			return mine.isEmpty ? channels : mine
		}

		if let explicitIndex = channelIndex(fromHandleOrName: name) {
			let explicitIndex32 = Int32(explicitIndex)
			let descriptor = FetchDescriptor<ChannelEntity>(
				predicate: #Predicate<ChannelEntity> { channel in
					channel.index == explicitIndex32
				}
			)
			// The duplicates are interchangeable for index-addressed lookups —
			// return at most one so resolution never disambiguates identical rows.
			return Array(scoped((try? context.fetch(descriptor)) ?? []).prefix(1))
		}

		let normalized = name.lowercased()
		let channels = (try? context.fetch(FetchDescriptor<ChannelEntity>())) ?? []
		let matches = scoped(channels.filter { channel in
			guard let channelName = channel.name, !channelName.isEmpty else { return false }
			return channelName.lowercased().contains(normalized)
		})
		// Collapse duplicate (index, name) rows left over from other radios.
		var seen = Set<Int32>()
		return matches.filter { seen.insert($0.index).inserted }
	}

	/// Resolves a channel index from a spoken group name. Returns nil when the
	/// name matches nothing — callers must fail rather than fall back: the old
	/// default of 0 silently sent channel replies to Primary when Siri's
	/// transcription didn't match any channel name.
	@MainActor
	static func channelIndex(for name: String, in context: ModelContext) -> Int? {
		if let explicitIndex = channelIndex(fromHandleOrName: name) {
			return explicitIndex
		}

		let channels = findChannels(matching: name, in: context)
		return channels.first.map { Int($0.index) }
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
			return validChannelIndex(index)
		}

		let channelPrefix = "channel-"
		if value.hasPrefix(channelPrefix) {
			let remainder = String(value.dropFirst(channelPrefix.count))
			let rawIndex = remainder.hasSuffix(meshtasticDomain)
				? String(remainder.dropLast(meshtasticDomain.count))
				: remainder
			return Int(rawIndex).flatMap(validChannelIndex)
		}

		return nil
	}

	/// The mesh supports at most 8 channels (indices 0–7). Rejecting anything
	/// outside that range here also protects the `Int32(_:)` conversions at
	/// every caller — an unbounded parse let a malformed handle like
	/// "channel-2147483648" through as an `Int` and trapped on the send path.
	private static func validChannelIndex(_ index: Int) -> Int? {
		(0...7).contains(index) ? index : nil
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
