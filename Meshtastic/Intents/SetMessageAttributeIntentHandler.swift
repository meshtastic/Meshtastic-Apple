//
//  SetMessageAttributeIntentHandler.swift
//  Meshtastic
//
//  Handles INSetMessageAttributeIntent for CarPlay and Siri.
//  Marks messages as read or unread in Core Data.
//

#if os(iOS)
import CoreData
import Intents
import OSLog

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
		// Use a private background context so Core Data work does not block the main thread.
		let bgContext = PersistenceController.shared.container.newBackgroundContext()
		bgContext.automaticallyMergesChangesFromParent = true

		let success: Bool = await bgContext.perform {
			let messageIds = identifiers.compactMap { Int64($0) }
			guard !messageIds.isEmpty else { return false }

			let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
			fetchRequest.predicate = NSPredicate(format: "messageId IN %@", messageIds)

			do {
				let messages = try bgContext.fetch(fetchRequest)
				guard !messages.isEmpty else { return false }

				for message in messages {
					switch attribute {
					case .read:
						message.read = true
					case .unread:
						message.read = false
					case .flagged, .unflagged:
						// Meshtastic does not support message flagging
						break
					default:
						break
					}
				}

				if bgContext.hasChanges {
					try bgContext.save()
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
#endif
