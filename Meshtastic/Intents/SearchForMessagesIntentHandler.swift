//
//  SearchForMessagesIntentHandler.swift
//  Meshtastic
//
//  Handles INSearchForMessagesIntent for CarPlay and Siri.
//  Queries Core Data for messages matching the intent criteria
//  and returns them as INMessage objects.
//

import CoreData
import Intents
import OSLog

final class SearchForMessagesIntentHandler: NSObject, INSearchForMessagesIntentHandling {

	/// Maximum number of messages to return in a single search.
	private static let maxResults = 20

	// MARK: - Handling

	func handle(intent: INSearchForMessagesIntent) async -> INSearchForMessagesIntentResponse {
		let context = PersistenceController.shared.container.viewContext

		let messages: [INMessage] = await MainActor.run {
			let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
			var predicates: [NSPredicate] = []

			// Exclude admin and emoji messages
			predicates.append(NSPredicate(format: "admin == NO"))
			predicates.append(NSPredicate(format: "isEmoji == NO"))

			// Filter by identifiers (specific message IDs)
			if let identifiers = intent.identifiers, !identifiers.isEmpty {
				let messageIds = identifiers.compactMap { Int64($0) }
				if !messageIds.isEmpty {
					predicates.append(NSPredicate(format: "messageId IN %@", messageIds))
				}
			}

			// Filter by sender
			if let senders = intent.senders, !senders.isEmpty {
				let senderNums = senders.compactMap { $0.personHandle?.value }.compactMap { Int64($0) }
				if !senderNums.isEmpty {
					predicates.append(NSPredicate(format: "fromUser.num IN %@", senderNums))
				}
			}

			// Filter by date range
			if let dateRange = intent.dateTimeRange {
				if let startDate = dateRange.startDate {
					let startTimestamp = Int32(startDate.timeIntervalSince1970)
					predicates.append(NSPredicate(format: "messageTimestamp >= %d", startTimestamp))
				}
				if let endDate = dateRange.endDate {
					let endTimestamp = Int32(endDate.timeIntervalSince1970)
					predicates.append(NSPredicate(format: "messageTimestamp <= %d", endTimestamp))
				}
			}

			// Filter by group/channel name
			if let groupNames = intent.speakableGroupNames, !groupNames.isEmpty {
				let channelIndices: [Int32] = groupNames.compactMap { groupName in
					let channels = IntentMessageConverters.findChannels(
						matching: groupName.spokenPhrase, in: context
					)
					return channels.first.map { Int32($0.index) }
				}
				if !channelIndices.isEmpty {
					predicates.append(NSPredicate(format: "channel IN %@", channelIndices))
				}
			}

			// Filter by read/unread attribute
			let attributes = intent.attributes
			if attributes.contains(.read) {
				predicates.append(NSPredicate(format: "read == YES"))
			} else if attributes.contains(.unread) {
				predicates.append(NSPredicate(format: "read == NO"))
			}

			fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
			fetchRequest.sortDescriptors = [
				NSSortDescriptor(key: "messageTimestamp", ascending: false)
			]
			fetchRequest.fetchLimit = Self.maxResults
			fetchRequest.relationshipKeyPathsForPrefetching = ["fromUser", "toUser"]

			do {
				let results = try context.fetch(fetchRequest)
				return results.map { IntentMessageConverters.inMessage(from: $0) }
			} catch {
				Logger.services.error("CarPlay/Siri: Failed to search messages: \(error.localizedDescription)")
				return []
			}
		}

		let response = INSearchForMessagesIntentResponse(code: .success, userActivity: nil)
		response.messages = messages
		return response
	}
}
