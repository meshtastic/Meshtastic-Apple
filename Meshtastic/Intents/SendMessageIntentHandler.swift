//
//  SendMessageIntentHandler.swift
//  Meshtastic
//
//  Handles INSendMessageIntent for CarPlay and Siri messaging.
//  Meshtastic supports exactly one destination per message: either a single
//  direct-message recipient (a mesh node) or a channel (speakableGroupName).
//  Multiple recipients are not supported.
//

import Intents
import OSLog

final class SendMessageIntentHandler: NSObject, INSendMessageIntentHandling {

	/// Where a send intent is addressed. Resolution and handling have to read an
	/// intent the same way: a resolver that asks for a value the handler would not
	/// have used turns into a question the user cannot answer sensibly.
	enum Destination: Equatable {
		/// A channel Siri named. The index still needs a lookup against the store.
		case namedChannel(String)
		/// A channel the conversation identifier names outright.
		case channel(Int)
		/// One or more people to resolve.
		case recipients
		/// Nothing usable.
		case unknown
	}

	/// Siri drops the speakable group name on some channel replies — notification
	/// replies, and replying to a channel thread in CarPlay — but the conversation
	/// identifier still carries "channel-<N>". Reading that here is what keeps a
	/// channel reply from being asked who it is for.
	static func destination(
		speakableGroupName: String?,
		conversationIdentifier: String?,
		hasRecipients: Bool
	) -> Destination {
		if let speakableGroupName {
			return .namedChannel(speakableGroupName)
		}
		if let conversationIdentifier,
		   let index = IntentMessageConverters.channelIndex(fromHandleOrName: conversationIdentifier) {
			return .channel(index)
		}
		return hasRecipients ? .recipients : .unknown
	}

	private static func destination(for intent: INSendMessageIntent) -> Destination {
		destination(
			speakableGroupName: intent.speakableGroupName?.spokenPhrase,
			conversationIdentifier: intent.conversationIdentifier,
			hasRecipients: !(intent.recipients ?? []).isEmpty
		)
	}

	// MARK: - Resolution

	func resolveRecipients(for intent: INSendMessageIntent) async -> [INSendMessageRecipientResolutionResult] {
		switch Self.destination(for: intent) {
		case .namedChannel, .channel:
			// A channel message has no recipient. Resolving whoever Siri attached to
			// the reply — the thread's sender — could only prompt: for one name it is
			// noise, for several it is a disambiguation list, and the handler ignores
			// the answer either way.
			return []
		case .unknown:
			return [.needsValue()]
		case .recipients:
			break
		}

		guard let recipients = intent.recipients, !recipients.isEmpty else {
			return [.needsValue()]
		}

		// Meshtastic only supports a single direct-message recipient.
		if recipients.count > 1 {
			return [.unsupported(forReason: .noAccount)]
		}

		let recipient = recipients[0]
		let handleValue = recipient.personHandle?.value ?? ""

		// If this is a channel handle, accept it directly
		if IntentMessageConverters.channelIndex(fromHandleOrName: handleValue) != nil {
			return [.success(with: recipient)]
		}

		// If the handle resolves to a node number, accept it directly
		if IntentMessageConverters.directMessageNodeNum(from: handleValue) != nil {
			return [.success(with: recipient)]
		}

		let searchTerm = recipient.displayName.isEmpty ? handleValue : recipient.displayName
		let matchingUsers = await MainActor.run {
			let context = PersistenceController.shared.context
			return IntentMessageConverters.findUsers(matching: searchTerm, in: context)
		}

		if matchingUsers.isEmpty {
			return [.unsupported(forReason: .noAccount)]
		} else if matchingUsers.count == 1, let user = matchingUsers.first {
			return [.success(with: IntentMessageConverters.inPerson(from: user))]
		} else {
			let persons = matchingUsers.map { IntentMessageConverters.inPerson(from: $0) }
			return [.disambiguation(with: persons)]
		}
	}

	func resolveContent(for intent: INSendMessageIntent) async -> INStringResolutionResult {
		guard let content = intent.content, !content.isEmpty else {
			return .needsValue()
		}

		guard let data = content.data(using: .utf8), data.count <= 200 else {
			return .unsupported()
		}

		return .success(with: content)
	}

	func resolveSpeakableGroupName(for intent: INSendMessageIntent) async -> INSpeakableStringResolutionResult {
		let groupName: INSpeakableString
		switch Self.destination(for: intent) {
		case .namedChannel:
			guard let named = intent.speakableGroupName else { return .needsValue() }
			groupName = named
		case .channel, .recipients:
			// The channel is already known from the conversation identifier, or this is
			// a direct message. Either way there is nothing to ask for.
			return .notRequired()
		case .unknown:
			return .needsValue()
		}

		let matchingChannels = await MainActor.run {
			let context = PersistenceController.shared.context
			return IntentMessageConverters.findChannels(matching: groupName.spokenPhrase, in: context)
		}

		if matchingChannels.count == 1, let channel = matchingChannels.first {
			let speakable = INSpeakableString(
				spokenPhrase: IntentMessageConverters.channelDisplayName(for: channel.index, named: channel.name)
			)
			return .success(with: speakable)
		} else if matchingChannels.count > 1 {
			let speakables = matchingChannels.map {
				INSpeakableString(
					spokenPhrase: IntentMessageConverters.channelDisplayName(for: $0.index, named: $0.name)
				)
			}
			return .disambiguation(with: speakables)
		}

		return .unsupported()
	}

	// MARK: - Confirmation

	func confirm(intent: INSendMessageIntent) async -> INSendMessageIntentResponse {
		let connected = await AccessoryManager.shared.isConnected
		guard connected else {
			return INSendMessageIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil)
		}
		return INSendMessageIntentResponse(code: .ready, userActivity: nil)
	}

	// MARK: - Handling

	func handle(intent: INSendMessageIntent) async -> INSendMessageIntentResponse {
		let connected = await AccessoryManager.shared.isConnected
		guard connected else {
			return INSendMessageIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil)
		}

		guard let content = intent.content, !content.isEmpty else {
			return INSendMessageIntentResponse(code: .failure, userActivity: nil)
		}

		do {
			// Same order as resolution, through the same helper, so the two cannot drift.
			switch Self.destination(for: intent) {
			case .namedChannel(let name):
				let channelIndex = await MainActor.run {
					let context = PersistenceController.shared.context
					return IntentMessageConverters.channelIndex(for: name, in: context)
				}
				// A group name that matches no channel is a failure — the old
				// fallback to index 0 silently sent the reply to Primary instead.
				guard let channelIndex else {
					Logger.services.error("CarPlay/Siri: No channel matches group name \(name, privacy: .public)")
					return INSendMessageIntentResponse(code: .failure, userActivity: nil)
				}
				try await AccessoryManager.shared.sendMessage(
					message: content,
					toUserNum: 0,
					channel: Int32(channelIndex),
					isEmoji: false,
					replyID: 0
				)
			case .channel(let channelIndex):
				// Siri dropped the group name but the conversation identifier still names
				// the channel. Before this was read, the reply fell through to the recipient
				// handle — the message's SENDER — and went out as a DM to that person.
				try await AccessoryManager.shared.sendMessage(
					message: content,
					toUserNum: 0,
					channel: Int32(channelIndex),
					isEmoji: false,
					replyID: 0
				)
			case .recipients:
				guard let handleValue = intent.recipients?.first?.personHandle?.value else {
					return INSendMessageIntentResponse(code: .failure, userActivity: nil)
				}
				if let channelIndex = IntentMessageConverters.channelIndex(fromHandleOrName: handleValue) {
					try await AccessoryManager.shared.sendMessage(
						message: content,
						toUserNum: 0,
						channel: Int32(channelIndex),
						isEmoji: false,
						replyID: 0
					)
				} else if let nodeNum = IntentMessageConverters.directMessageNodeNum(from: handleValue) {
					try await AccessoryManager.shared.sendMessage(
						message: content,
						toUserNum: nodeNum,
						channel: 0,
						isEmoji: false,
						replyID: 0
					)
				} else {
					return INSendMessageIntentResponse(code: .failure, userActivity: nil)
				}
			case .unknown:
				return INSendMessageIntentResponse(code: .failure, userActivity: nil)
			}

			Logger.services.info("CarPlay/Siri: Message sent successfully")
			return INSendMessageIntentResponse(code: .success, userActivity: nil)
		} catch {
			Logger.services.error("CarPlay/Siri: Failed to send message: \(error.localizedDescription)")
			return INSendMessageIntentResponse(code: .failure, userActivity: nil)
		}
	}
}
