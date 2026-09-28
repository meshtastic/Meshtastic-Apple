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

	// MARK: - Conversations and radios (feature 021, T157)

	/// A Siri / CarPlay conversation: a channel slot or a DM, and with several radios the radio
	/// it's on. A slot number only means something on one radio, and a DM reply goes through the
	/// conversation's radio (D-13), so a reply needs both.
	enum Conversation: Equatable {
		case channel(index: Int, radioNum: Int64?)
		case directMessage(nodeNum: Int64, radioNum: Int64?)

		var radioNum: Int64? {
			switch self {
			case let .channel(_, radioNum), let .directMessage(_, radioNum): return radioNum
			}
		}
	}

	/// Marks the radio in a conversation identifier: "channel-2:r167772170".
	static let radioMarker = ":r"

	/// "channel-<N>", with the radio when the store holds several radios.
	static func channelConversationIdentifier(index: Int32, radioNum: Int64?) -> String {
		"channel-\(index)" + (radioNum.map { "\(radioMarker)\($0)" } ?? "")
	}

	/// "dm-<nodeNum>", with the radio when the store holds several radios.
	static func directMessageConversationIdentifier(nodeNum: Int64, radioNum: Int64?) -> String {
		"dm-\(nodeNum)" + (radioNum.map { "\(radioMarker)\($0)" } ?? "")
	}

	/// Parses a conversation identifier made by the two functions above (and the older form
	/// without a radio).
	static func conversation(fromIdentifier identifier: String) -> Conversation? {
		var body = Substring(identifier)
		var radioNum: Int64?
		if let marker = body.range(of: radioMarker) {
			radioNum = Int64(body[marker.upperBound...])
			body = body[..<marker.lowerBound]
		}
		if body.hasPrefix("dm-"), let nodeNum = Int64(body.dropFirst("dm-".count)) {
			return .directMessage(nodeNum: nodeNum, radioNum: radioNum)
		}
		if body.hasPrefix("channel-"), let index = Int(body.dropFirst("channel-".count)).flatMap(validChannelIndex) {
			return .channel(index: index, radioNum: radioNum)
		}
		return nil
	}

	/// The radio to name in `message`'s conversation identifier: the radio it came in on or went
	/// out through, when the store holds more than one radio connected with this version; nil
	/// otherwise, so a single radio's identifiers stay as they were.
	static func conversationRadio(for message: MessageEntity) -> Int64? {
		guard let radioNum = message.localNodeNum, let context = message.modelContext,
			  isMultiRadio(in: context) else { return nil }
		return radioNum
	}

	/// More than one radio connected with this version (`MyInfoEntity.lastConnected`).
	static func isMultiRadio(in context: ModelContext) -> Bool {
		let connected = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.lastConnected != nil })
		return ((try? context.fetchCount(connected)) ?? 0) > 1
	}

	/// `radioNum`'s channel keys by slot: from its LoRa settings, or the keys stored on its
	/// channels when those aren't in the store.
	static func channelKeys(ofRadio radioNum: Int64, in context: ModelContext) -> [Int32: String] {
		var keys: [Int32: String] = [:]
		var descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == radioNum })
		descriptor.fetchLimit = 1
		for channel in (try? context.fetch(descriptor))?.first?.channels ?? [] {
			if let key = channel.channelKey { keys[channel.index] = key }
		}
		let computed = (try? MultiRadioBackfill.channelKeysByIndex(for: radioNum, in: context, updateStored: false)) ?? [:]
		return keys.merging(computed) { _, fresh in fresh }
	}

	/// Whether a channel message belongs to slot `index` of `radioNum`, as the app's timeline
	/// decides it (`ChannelMessageQuery`, T192): by channel key, since a channel several radios
	/// have is stored once under whichever radio delivered it first; otherwise, for a row without
	/// a key, by this radio's slot. With no radio, by slot as before. `keys` is
	/// `channelKeys(ofRadio:in:)`, looked up once by the caller.
	static func channelMessage(_ message: MessageEntity, isInSlot index: Int32, ofRadio radioNum: Int64?, keys: [Int32: String]) -> Bool {
		guard message.toUser == nil else { return false }
		guard let radioNum else { return message.channel == index }
		if let key = keys[index], message.channelKey == key { return true }
		return message.channel == index && (message.localNodeNum ?? radioNum) == radioNum
	}

	/// The spoken name of slot `index`: the channel's own name on `radioNum` when it has one,
	/// so "reply to Family" finds it; otherwise "Primary Channel" / "Channel N" as before.
	static func channelSpokenName(index: Int32, radioNum: Int64?, in context: ModelContext?) -> String {
		guard let radioNum, let context else { return channelDisplayName(for: index, named: nil) }
		var descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == radioNum })
		descriptor.fetchLimit = 1
		let name = (try? context.fetch(descriptor))?.first?.channels.first { $0.index == index }?.name
		return channelDisplayName(for: index, named: name)
	}

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
		let radioNum = conversationRadio(for: message)
		if let toUser = message.toUser {
			return directMessageConversationIdentifier(nodeNum: toUser.num, radioNum: radioNum)
		}
		return channelConversationIdentifier(index: message.channel, radioNum: radioNum)
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
		// Feature 021 (T104): the radio CarPlay & Siri send through.
		let connectedNum = AccessoryManager.shared.radioNum(for: .carPlay)

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
		channelSlot(for: name, in: context)?.index
	}

	/// The slot a spoken group name resolves to, with the radio it's on: a name matched only on
	/// another radio (the `findChannels` fallback) is that radio's slot, not the CarPlay
	/// radio's, so the reply must go through it (T157). nil radio: the CarPlay radio.
	@MainActor
	static func channelSlot(for name: String, in context: ModelContext) -> (index: Int, radioNum: Int64?)? {
		if let explicitIndex = channelIndex(fromHandleOrName: name) {
			return (explicitIndex, nil)
		}
		guard let channel = findChannels(matching: name, in: context).first else { return nil }
		let carPlayRadio = AccessoryManager.shared.radioNum(for: .carPlay)
		let owner = channel.myInfoChannel?.myNodeNum
		return (Int(channel.index), owner == carPlayRadio ? nil : owner)
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
			var remainder = String(value.dropFirst(channelPrefix.count))
			if let marker = remainder.range(of: radioMarker) {
				remainder = String(remainder[..<marker.lowerBound])
			}
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
