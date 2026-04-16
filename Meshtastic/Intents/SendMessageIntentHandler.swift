//
//  SendMessageIntentHandler.swift
//  Meshtastic
//
//  Handles INSendMessageIntent for CarPlay and Siri messaging.
//  Meshtastic supports exactly one destination per message: either a single
//  direct-message recipient (a mesh node) or a channel (speakableGroupName).
//  Multiple recipients are not supported.
//

import CoreData
import Intents
import OSLog

final class SendMessageIntentHandler: NSObject, INSendMessageIntentHandling {

	// MARK: - Resolution

	func resolveRecipients(for intent: INSendMessageIntent) async -> [INSendMessageRecipientResolutionResult] {
		guard let recipients = intent.recipients, !recipients.isEmpty else {
			if intent.speakableGroupName != nil {
				return []
			}
			return [.needsValue()]
		}

		// Meshtastic only supports a single direct-message recipient.
		if recipients.count > 1 {
			return [.unsupported(forReason: .noAccount)]
		}

		let context = PersistenceController.shared.container.viewContext
		let searchTerm = recipients[0].displayName
		let matchingUsers = await MainActor.run {
			IntentMessageConverters.findUsers(matching: searchTerm, in: context)
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
		guard let groupName = intent.speakableGroupName else {
			if let recipients = intent.recipients, !recipients.isEmpty {
				return .notRequired()
			}
			return .needsValue()
		}

		let context = PersistenceController.shared.container.viewContext
		let matchingChannels = await MainActor.run {
			IntentMessageConverters.findChannels(matching: groupName.spokenPhrase, in: context)
		}

		if matchingChannels.count == 1, let channel = matchingChannels.first {
			let speakable = INSpeakableString(spokenPhrase: channel.name ?? "Channel \(channel.index)")
			return .success(with: speakable)
		} else if matchingChannels.count > 1 {
			let speakables = matchingChannels.map {
				INSpeakableString(spokenPhrase: $0.name ?? "Channel \($0.index)")
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
			if let groupName = intent.speakableGroupName {
				// Channel message
				let context = PersistenceController.shared.container.viewContext
				let channelIndex = await MainActor.run {
					IntentMessageConverters.channelIndex(for: groupName.spokenPhrase, in: context)
				}
				try await AccessoryManager.shared.sendMessage(
					message: content,
					toUserNum: 0,
					channel: Int32(channelIndex),
					isEmoji: false,
					replyID: 0
				)
			} else if let recipient = intent.recipients?.first,
					  let handleValue = recipient.personHandle?.value,
					  let nodeNum = Int64(handleValue) {
				// Direct message to a single node
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

			Logger.services.info("CarPlay/Siri: Message sent successfully")
			return INSendMessageIntentResponse(code: .success, userActivity: nil)
		} catch {
			Logger.services.error("CarPlay/Siri: Failed to send message: \(error.localizedDescription)")
			return INSendMessageIntentResponse(code: .failure, userActivity: nil)
		}
	}
}
