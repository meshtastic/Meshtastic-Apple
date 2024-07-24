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
		let time = messageTimestamp <= 0 ? receivedTimestamp : messageTimestamp
		return Date(timeIntervalSince1970: TimeInterval(time))
	}

	var canRetry: Bool {
		return ackError == 9 || ackError == 5 || ackError == 3
	}

	var tapbacks: [MessageEntity] {
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.predicate = NSPredicate(format: "replyID == %lld AND isEmoji == true", self.messageId)

		return (try? context.fetch(fetchRequest)) ?? [MessageEntity]()
	}
}
