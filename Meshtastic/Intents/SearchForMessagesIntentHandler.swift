//
//  SearchForMessagesIntentHandler.swift
//  Meshtastic
//
//  Handles INSearchForMessagesIntent for CarPlay and Siri.
//  Queries SwiftData for messages matching the intent criteria
//  and returns them as INMessage objects.
//

import Intents
import OSLog
import SwiftData

final class SearchForMessagesIntentHandler: NSObject, INSearchForMessagesIntentHandling {

	/// Maximum number of messages to return in a single search.
	private static let maxResults = 20

	// MARK: - Handling

	func handle(intent: INSearchForMessagesIntent) async -> INSearchForMessagesIntentResponse {
		let messages: [INMessage] = await MainActor.run {
			let context = PersistenceController.shared.context
			let descriptor = FetchDescriptor<MessageEntity>(
				sortBy: [SortDescriptor(\.messageTimestamp, order: .reverse)]
			)

			guard let fetched = try? context.fetch(descriptor) else {
				Logger.services.error("CarPlay/Siri: Failed to search messages")
				return []
			}

			var results = fetched.filter { !$0.admin && !$0.isEmoji }

			if let conversationIds = intent.conversationIdentifiers, !conversationIds.isEmpty {
				let dmNums = Set(conversationIds.compactMap { convId -> Int64? in
					guard convId.hasPrefix("dm-") else { return nil }
					return Int64(convId.dropFirst("dm-".count))
				})
				let channelNums = Set(conversationIds.compactMap { convId -> Int32? in
					guard convId.hasPrefix("channel-") else { return nil }
					return Int32(convId.dropFirst("channel-".count))
				})

				results = results.filter { message in
					let isDM = message.fromUser.map { dmNums.contains($0.num) } ?? false
					let isChannel = message.toUser == nil && channelNums.contains(message.channel)
					return isDM || isChannel
				}
			}

			if let identifiers = intent.identifiers, !identifiers.isEmpty {
				let messageIds = Set(identifiers.compactMap(Int64.init))
				results = results.filter { messageIds.contains($0.messageId) }
			}

			if let senders = intent.senders, !senders.isEmpty {
				let senderNums = Set(senders.compactMap { sender -> Int64? in
					guard let handleValue = sender.personHandle?.value else { return nil }
					return IntentMessageConverters.directMessageNodeNum(from: handleValue)
				})
				results = results.filter { message in
					guard let senderNum = message.fromUser?.num else { return false }
					return senderNums.contains(senderNum)
				}
			}

			if let dateRange = intent.dateTimeRange {
				let calendar = Calendar.current
				let startTimestamp = dateRange.startDateComponents.flatMap { calendar.date(from: $0) }
					.map { Int32($0.timeIntervalSince1970) }
				let endTimestamp = dateRange.endDateComponents.flatMap { calendar.date(from: $0) }
					.map { Int32($0.timeIntervalSince1970) }

				results = results.filter { message in
					if let startTimestamp, message.messageTimestamp < startTimestamp { return false }
					if let endTimestamp, message.messageTimestamp > endTimestamp { return false }
					return true
				}
			}

			if let groupNames = intent.speakableGroupNames, !groupNames.isEmpty {
				let channelIndices = Set(groupNames.compactMap { groupName -> Int32? in
					if let idx = IntentMessageConverters.channelIndex(fromHandleOrName: groupName.spokenPhrase) {
						return Int32(idx)
					}
					let channels = IntentMessageConverters.findChannels(matching: groupName.spokenPhrase, in: context)
					return channels.first.map(\.index)
				})
				results = results.filter { $0.toUser == nil && channelIndices.contains($0.channel) }
			}

			let attributes = intent.attributes
			if attributes.contains(.read) {
				results = results.filter(\.read)
			} else if attributes.contains(.unread) {
				results = results.filter { !$0.read }
			}

			return Array(results.prefix(Self.maxResults)).map { IntentMessageConverters.inMessage(from: $0) }
		}

		let response = INSearchForMessagesIntentResponse(code: .success, userActivity: nil)
		response.messages = messages
		return response
	}
}
#endif
