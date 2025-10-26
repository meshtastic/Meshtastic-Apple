//
//  MessageEntityExtension.swift
//  Meshtastic
//
//  Created by Ben on 8/22/23.
//

import Foundation

import CoreData
import CoreLocation
import MapKit
import SwiftUI

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
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "messageTimestamp", ascending: true)]
		fetchRequest.predicate = NSPredicate(format: "replyID == %lld AND isEmoji == true", self.messageId)

		return (try? context.fetch(fetchRequest)) ?? [MessageEntity]()
	}

	func displayTimestamp(aboveMessage: MessageEntity?) -> Bool {
		if let aboveMessage = aboveMessage {
			return aboveMessage.timestamp.addingTimeInterval(3600) < timestamp // 60 minutes
		}
		return false // First message will have no timestamp
	}
	
	func relayDisplay() -> String?  {

		   guard self.relayNode != 0 else { return nil }
			let context = PersistenceController.shared.container.viewContext

		   let relaySuffix = Int64(self.relayNode & 0xFF)
		   let request: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
		   request.predicate = NSPredicate(format: "(num & 0xFF) == %lld", relaySuffix)

		   do {
			   let users = try context.fetch(request)
			   
			   // If exactly one match is found, return its name
			   if users.count == 1, let name = users.first?.longName, !name.isEmpty {
				   return "\(name)"
			   }
			   
			   // If no exact match, find the node with the smallest hopsAway
			   if let closestNode = users.min(by: { lhs, rhs in
				   guard let lhsHops = lhs.userNode?.hopsAway, let rhsHops = rhs.userNode?.hopsAway else {
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
