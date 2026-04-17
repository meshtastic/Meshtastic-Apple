// MARK: CarPlayIntentDonation
//
//  CarPlayIntentDonation.swift
//  Meshtastic
//
//  Donates SiriKit interactions when messages are received so that
//  conversations appear in CarPlay's messaging interface and Siri
//  can read them aloud.
//

import CoreData
import Intents
import OSLog

enum CarPlayIntentDonation {

	/// Donates an incoming message interaction so it appears in CarPlay Messages.
	/// Call this after saving a new `MessageEntity` to Core Data.
	static func donateReceivedMessage(_ message: MessageEntity) {
		guard let fromUser = message.fromUser else { return }
		guard !message.isEmoji, !message.admin else { return }

		let sender = IntentMessageConverters.inPerson(from: fromUser)
		let me = mePerson()

		let intent: INSendMessageIntent
		if message.toUser != nil {
			// Direct message
			intent = INSendMessageIntent(
				recipients: [me],
				outgoingMessageType: .outgoingMessageText,
				content: message.messagePayload,
				speakableGroupName: nil,
				conversationIdentifier: "dm-\(fromUser.num)",
				serviceName: "Meshtastic",
				sender: sender,
				attachments: nil
			)
		} else {
			// Channel message
			let channelName = channelDisplayName(for: message.channel)
			let groupName = INSpeakableString(spokenPhrase: channelName)
			intent = INSendMessageIntent(
				recipients: [me],
				outgoingMessageType: .outgoingMessageText,
				content: message.messagePayload,
				speakableGroupName: groupName,
				conversationIdentifier: "channel-\(message.channel)",
				serviceName: "Meshtastic",
				sender: sender,
				attachments: nil
			)
			intent.setImage(
				INImage(named: "antenna.radiowaves.left.and.right"),
				forParameterNamed: \.speakableGroupName
			)
		}

		let interaction = INInteraction(intent: intent, response: nil)
		interaction.direction = .incoming
		interaction.donate { error in
			if let error {
				Logger.services.error("🚗 [CarPlay] Failed to donate interaction: \(error.localizedDescription, privacy: .public)")
			} else {
				Logger.services.debug("🚗 [CarPlay] Donated incoming message from \(fromUser.longName ?? "unknown", privacy: .public)")
			}
		}
	}

	/// Donates an outgoing message interaction after the user sends a message.
	static func donateOutgoingMessage(content: String, toUserNum: Int64, channel: Int32) {
		let me = mePerson()

		let intent: INSendMessageIntent
		if toUserNum != 0 {
			let recipientHandle = INPersonHandle(value: String(toUserNum), type: .unknown)
			let recipient = INPerson(
				personHandle: recipientHandle,
				nameComponents: nil,
				displayName: "Node \(toUserNum.toHex())",
				image: nil,
				contactIdentifier: String(toUserNum),
				customIdentifier: String(toUserNum)
			)
			intent = INSendMessageIntent(
				recipients: [recipient],
				outgoingMessageType: .outgoingMessageText,
				content: content,
				speakableGroupName: nil,
				conversationIdentifier: "dm-\(toUserNum)",
				serviceName: "Meshtastic",
				sender: me,
				attachments: nil
			)
		} else {
			let channelName = channelDisplayName(for: channel)
			let groupName = INSpeakableString(spokenPhrase: channelName)
			intent = INSendMessageIntent(
				recipients: nil,
				outgoingMessageType: .outgoingMessageText,
				content: content,
				speakableGroupName: groupName,
				conversationIdentifier: "channel-\(channel)",
				serviceName: "Meshtastic",
				sender: me,
				attachments: nil
			)
		}

		let interaction = INInteraction(intent: intent, response: nil)
		interaction.direction = .outgoing
		interaction.donate { error in
			if let error {
				Logger.services.error("🚗 [CarPlay] Failed to donate outgoing interaction: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	// MARK: - Helpers

	private static func mePerson() -> INPerson {
		let meHandle = INPersonHandle(value: "me", type: .unknown)
		return INPerson(
			personHandle: meHandle,
			nameComponents: nil,
			displayName: "Me",
			image: nil,
			contactIdentifier: "me",
			customIdentifier: "me",
			isMe: true
		)
	}

	private static func channelDisplayName(for index: Int32) -> String {
		if index == 0 {
			return "Primary Channel"
		}
		return "Channel \(index)"
	}
}
