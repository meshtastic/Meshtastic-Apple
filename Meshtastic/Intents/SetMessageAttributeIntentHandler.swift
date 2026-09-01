//
//  SetMessageAttributeIntentHandler.swift
//  Meshtastic
//
//  Handles INSetMessageAttributeIntent for CarPlay and Siri.
//  Marks messages as read or unread in SwiftData.
//

import Intents
import OSLog
import SwiftData

final class SetMessageAttributeIntentHandler: NSObject, INSetMessageAttributeIntentHandling {

	// MARK: - Resolution

	func resolveAttribute(for intent: INSetMessageAttributeIntent) async -> INMessageAttributeResolutionResult {
		let attribute = intent.attribute
		guard attribute != .unknown else {
			return .needsValue()
		}
		return .success(with: attribute)
	}

	// MARK: - Confirmation

	func confirm(intent: INSetMessageAttributeIntent) async -> INSetMessageAttributeIntentResponse {
		guard let identifiers = intent.identifiers, !identifiers.isEmpty else {
			return INSetMessageAttributeIntentResponse(code: .failure, userActivity: nil)
		}
		return INSetMessageAttributeIntentResponse(code: .ready, userActivity: nil)
	}

	// MARK: - Handling

	func handle(intent: INSetMessageAttributeIntent) async -> INSetMessageAttributeIntentResponse {
		guard let identifiers = intent.identifiers, !identifiers.isEmpty else {
			return INSetMessageAttributeIntentResponse(code: .failure, userActivity: nil)
		}

		let attribute = intent.attribute
		let messageIds = Set(identifiers.compactMap(Int64.init))
		guard !messageIds.isEmpty else {
			return INSetMessageAttributeIntentResponse(code: .failure, userActivity: nil)
		}

		let success = await MainActor.run { () -> Bool in
			let context = PersistenceController.shared.context
			let descriptor = FetchDescriptor<MessageEntity>()

			do {
				let allMessages = try context.fetch(descriptor)
				let messages = allMessages.filter { messageIds.contains($0.messageId) }
				guard !messages.isEmpty else {
					return false
				}

				for message in messages {
					switch attribute {
					case .read:
						message.read = true
					case .unread:
						message.read = false
					case .flagged, .unflagged:
						break
					default:
						break
					}
				}

				if context.hasChanges {
					try context.save()
				}
				Logger.services.info("CarPlay/Siri: Updated \(messages.count) message(s) to \(String(describing: attribute))")
				return true
			} catch {
				Logger.services.error("CarPlay/Siri: Failed to update message attributes: \(error.localizedDescription)")
				return false
			}
		}

		return INSetMessageAttributeIntentResponse(
			code: success ? .success : .failure,
			userActivity: nil
		)
	}
}
