//
//  MessageEntityExtension.swift
//  Meshtastic
//
//  Created by Ben on 8/22/23.
//

import CoreData
import CoreLocation
import Foundation
import MapKit
import SwiftUI

public struct PartialVoiceInfo: Codable {
    public let id: UInt16
    public let total: Int
    public var chunks: [Int: Data]
}

extension MessageEntity {

	var timestamp: Date {
		let time = messageTimestamp
		return Date(timeIntervalSince1970: TimeInterval(time))
	}

	var canRetry: Bool {
		let re = RoutingError(rawValue: Int(ackError))
		return re?.canRetry ?? false
	}

	var tapbacks: [MessageEntity] {
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [
			NSSortDescriptor(key: "messageTimestamp", ascending: true)
		]
		fetchRequest.predicate = NSPredicate(
			format: "replyID == %lld AND isEmoji == true",
			self.messageId
		)

		return (try? context.fetch(fetchRequest)) ?? [MessageEntity]()
	}

	func displayTimestamp(aboveMessage: MessageEntity?) -> Bool {
		if let aboveMessage = aboveMessage {
			return aboveMessage.timestamp.addingTimeInterval(3600) < timestamp  // 60 minutes
		}
		return false  // First message will have no timestamp
	}

	public var partialAudioInfo: PartialVoiceInfo? {
		guard let data = audioData else { return nil }
		if let prefix = "PARTIAL_AUDIO:".data(using: .utf8), data.count >= prefix.count, data.prefix(prefix.count) == prefix {
			let json = data.dropFirst(prefix.count)
			return try? JSONDecoder().decode(PartialVoiceInfo.self, from: json)
		}
		return nil
	}

	public var isAudioMessage: Bool {
		return audioData != nil && !audioData!.isEmpty && partialAudioInfo == nil
	}

	func relayDisplay() -> String? {

		guard self.relayNode != 0 else { return nil }
		let context = PersistenceController.shared.container.viewContext

		let relaySuffix = Int64(self.relayNode & 0xFF)
		let request: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
		request.predicate = NSPredicate(
			format: "(num & 0xFF) == %lld",
			relaySuffix
		)

		do {
			let users = try context.fetch(request)

			// If exactly one match is found, return its name
			if users.count == 1, let name = users.first?.longName, !name.isEmpty
			{
				return "\(name)"
			}

			// If no exact match, find the node with the smallest hopsAway
			if let closestNode = users.min(by: { lhs, rhs in
				guard let lhsHops = lhs.userNode?.hopsAway,
					let rhsHops = rhs.userNode?.hopsAway
				else {
					return false
				}
				return lhsHops < rhsHops
			}), let name = closestNode.longName, !name.isEmpty {
				return "\(name)"
			}

			// Fallback to hex node number if no matches
			return String(format: "Node 0x%02X", UInt32(self.relayNode & 0xFF))

		} catch {
			return String(format: "Node 0x%02X", UInt32(self.relayNode & 0xFF))
		}
	}
}
