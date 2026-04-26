//
//  SearchForMessagesIntentHandler.swift
//  Meshtastic
//
//  Handles INSearchForMessagesIntent for CarPlay and Siri.
//  Queries Core Data for messages matching the intent criteria
//  and returns them as INMessage objects.
//

#if os(iOS)
import CoreData
import Intents
import OSLog

final class SearchForMessagesIntentHandler: NSObject, INSearchForMessagesIntentHandling {

	/// Maximum number of messages to return in a single search.
	private static let maxResults = 20

	// MARK: - Handling

	func handle(intent: INSearchForMessagesIntent) async -> INSearchForMessagesIntentResponse {
		// Use a private background context so the fetch does not block the main thread.
		let bgContext = PersistenceController.shared.container.newBackgroundContext()
		bgContext.automaticallyMergesChangesFromParent = true

		let messages: [INMessage] = await bgContext.perform {
			let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
			var predicates: [NSPredicate] = []

			// Exclude admin and emoji messages
			predicates.append(NSPredicate(format: "admin == NO"))
			predicates.append(NSPredicate(format: "isEmoji == NO"))

			// Filter by conversation identifiers (e.g., "dm-123456" or "channel-0")
			// This is the primary filter when Siri reads messages for a CarPlay contact.
			if let conversationIds = intent.conversationIdentifiers, !conversationIds.isEmpty {
				var conversationPredicates: [NSPredicate] = []
				for convId in conversationIds {
					if convId.hasPrefix("dm-"), let nodeNum = Int64(convId.dropFirst("dm-".count)) {
						conversationPredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
							NSPredicate(format: "fromUser.num == %lld", nodeNum),
							NSPredicate(format: "toUser.num == %lld", nodeNum)
						]))
					} else if convId.hasPrefix("channel-"), let channelIndex = Int32(convId.dropFirst("channel-".count)) {
						conversationPredicates.append(NSPredicate(format: "channel == %d AND toUser == nil", channelIndex))
					}
				}
				if !conversationPredicates.isEmpty {
					predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: conversationPredicates))
				}
			}

			// Filter by identifiers (specific message IDs)
			if let identifiers = intent.identifiers, !identifiers.isEmpty {
				let messageIds = identifiers.compactMap { Int64($0) }
				if !messageIds.isEmpty {
					predicates.append(NSPredicate(format: "messageId IN %@", messageIds))
				}
			}

			// Filter by sender — parse @meshtastic.local email-format handles
			if let senders = intent.senders, !senders.isEmpty {
				let senderNums = senders.compactMap { sender -> Int64? in
					guard let handleValue = sender.personHandle?.value else { return nil }
					return IntentMessageConverters.directMessageNodeNum(from: handleValue)
				}
				if !senderNums.isEmpty {
					predicates.append(NSPredicate(format: "fromUser.num IN %@", senderNums))
				}
			}

			// Filter by date range.
			// INDateComponentsRange exposes DateComponents on all platforms;
			// .startDate/.endDate are iOS-only and unavailable on Mac Catalyst.
			if let dateRange = intent.dateTimeRange {
				let calendar = Calendar.current
				if let startComponents = dateRange.startDateComponents,
				   let startDate = calendar.date(from: startComponents) {
					let startTimestamp = Int32(startDate.timeIntervalSince1970)
					predicates.append(NSPredicate(format: "messageTimestamp >= %d", startTimestamp))
				}
				if let endComponents = dateRange.endDateComponents,
				   let endDate = calendar.date(from: endComponents) {
					let endTimestamp = Int32(endDate.timeIntervalSince1970)
					predicates.append(NSPredicate(format: "messageTimestamp <= %d", endTimestamp))
				}
			}

			// Filter by group/channel name or handle
			if let groupNames = intent.speakableGroupNames, !groupNames.isEmpty {
				let channelIndices: [Int32] = groupNames.compactMap { groupName in
					if let idx = IntentMessageConverters.channelIndex(fromHandleOrName: groupName.spokenPhrase) {
						return Int32(idx)
					}
					let channels = IntentMessageConverters.findChannels(
						matching: groupName.spokenPhrase, in: bgContext
					)
					return channels.first.map { Int32($0.index) }
				}
				if !channelIndices.isEmpty {
					predicates.append(NSPredicate(format: "channel IN %@ AND toUser == nil", channelIndices))
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
				let results = try bgContext.fetch(fetchRequest)
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
#endif
