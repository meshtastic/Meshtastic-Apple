//
//  MessageEntityExtension.swift
//  Meshtastic
//
//  Created by Ben on 8/22/23.
//

@preconcurrency import SwiftData
import CoreLocation
import Foundation
import MapKit
import SwiftUI

extension MessageEntity {
	var hasTranslatedPayload: Bool {
		!(messagePayloadTranslated?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
	}

	var displayedPayload: String {
		if showTranslatedMessage, hasTranslatedPayload {
			return messagePayloadTranslated ?? messagePayload ?? "EMPTY MESSAGE"
		}
		return messagePayload ?? "EMPTY MESSAGE"
	}

	var displayedMarkdownPayload: String {
		if showTranslatedMessage, hasTranslatedPayload {
			return messagePayloadTranslatedMarkdown ?? messagePayloadTranslated ?? messagePayload ?? "EMPTY MESSAGE"
		}
		return messagePayloadMarkdown ?? messagePayload ?? "EMPTY MESSAGE"
	}

	var timestamp: Date {
		let time = messageTimestamp
		return Date(timeIntervalSince1970: TimeInterval(time))
	}

	var canRetry: Bool {
		let re = RoutingError(rawValue: Int(ackError))
		return re?.canRetry ?? false
	}

	func deliveryStatus(isDirectMessage: Bool) -> MessageDeliveryStatus {
		if receivedACK {
			if isDirectMessage {
				return realACK ? .deliveredToRecipient : .relayedNotConfirmed
			}
			return .deliveredToMesh
		}

		guard ackError != 0 else { return .sending }

		if let routingError = RoutingError(rawValue: Int(ackError)) {
			return .failed(routingError)
		}

		return MessageDeliveryStatus(
			text: "Could not send message".localized,
			detail: "The radio reported an unknown delivery error.".localized,
			systemImage: "exclamationmark.circle.fill",
			color: Color(uiColor: .systemOrange),
			canRetry: true
		)
	}

	@MainActor
	var tapbacks: [MessageEntity] {
		let context = PersistenceController.shared.context
		let msgId = self.messageId
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.replyID == msgId && msg.isEmoji == true
			},
			sortBy: [SortDescriptor(\MessageEntity.messageTimestamp, order: .forward)]
		)
		return (try? context.fetch(descriptor)) ?? []
	}

	func displayTimestamp(aboveMessage: MessageEntity?) -> Bool {
		if let aboveMessage = aboveMessage {
			return aboveMessage.timestamp.addingTimeInterval(3600) < timestamp  // 60 minutes
		}
		return false  // First message will have no timestamp
	}

	@MainActor
	func relayDisplay() -> String? {
		// This message can be read from a retained row after it (or the models it reaches through)
		// were deleted underneath the list; reading a persisted property of a dead @Model fatally
		// traps in SwiftData (SIGTRAP). Bail while `self` is no longer live before touching any of
		// its stored properties. Mirrors the row guard in ChannelMessageRow/UserMessageRow (#2014).
		guard modelContext != nil, !isDeleted else { return nil }

		guard self.relayNode != 0 else { return nil }
		let relaySuffix = Int64(self.relayNode & 0xFF)
		let hexFallback = String(format: "Node 0x%02X", UInt32(self.relayNode & 0xFF))

		let context = PersistenceController.shared.context
		let descriptor = FetchDescriptor<UserEntity>()

		guard let users = try? context.fetch(descriptor) else {
			return hexFallback
		}
		// Only consider users still live in the context — a freshly-fetched set can still contain
		// entries being torn down, and reading their name or `userNode` relationship would trap.
		let matchingUsers = users.filter { user in
			user.modelContext != nil && !user.isDeleted && (user.num & 0xFF) == relaySuffix
		}

		// If exactly one match is found, return its name
		if matchingUsers.count == 1 {
			let name = matchingUsers.first!.displayLongName
			if !name.isEmpty { return name }
		}

		// If no exact match, find the node with the smallest hopsAway. Users whose hops are unknown
		// can't be ranked, so filter them out before comparing — leaving them in makes the comparator
		// return false for every pair involving them, which isn't a strict weak ordering and lets a
		// nil-hops user "win" purely by its position in the array. Fall back to the first match when
		// none have hops. `liveUserNode` guards the relationship read so a faulted node can't trap.
		let rankable = matchingUsers.filter { $0.liveUserNode?.hopsAway != nil }
		if let closestNode = rankable.min(by: { ($0.liveUserNode?.hopsAway ?? .max) < ($1.liveUserNode?.hopsAway ?? .max) })
			?? matchingUsers.first {
			let name = closestNode.displayLongName
			if !name.isEmpty { return name }
		}

		// Fallback to hex node number if no matches
		return hexFallback
	}
}

extension UserEntity {
	/// The `userNode` relationship, but only when this user is still live in its context. Reading a
	/// relationship on a deleted/zombie @Model fatally traps in SwiftData; callers on render paths
	/// use this so a node pruned underneath them can't crash the read.
	var liveUserNode: NodeInfoEntity? {
		guard modelContext != nil, !isDeleted else { return nil }
		return userNode
	}
}
