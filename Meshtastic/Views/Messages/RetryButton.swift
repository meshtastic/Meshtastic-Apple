import SwiftUI
import OSLog

struct RetryButton: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	let message: MessageEntity
	let destination: MessageDestination
	@State var isShowingConfirmation = false

	var body: some View {
		Button {
			isShowingConfirmation = true
		} label: {
			Image(systemName: "exclamationmark.circle")
				.foregroundColor(.gray)
				.frame(height: 30)
				.padding(.top, 5)
		}
		.confirmationDialog(
			"This message was likely not delivered.",
			isPresented: $isShowingConfirmation,
			titleVisibility: .visible
		) {
			Button("Try Again") {
				guard accessoryManager.isConnected else {
					return
				}
				let messageID = message.messageId
				let payload = message.messagePayload ?? ""
				let userNum = message.toUser?.num ?? 0
				let channel = message.channel
				let isEmoji = message.isEmoji
				let replyID = message.replyID
				context.delete(message)
				do {
					try context.save()
				} catch {
					Logger.data.error("Failed to delete message \(messageID, privacy: .public): \(error.localizedDescription, privacy: .public)")
				}
				Task {
					do {
						try await accessoryManager.sendMessage(message: payload, toUserNum: userNum, channel: channel,
															   isEmoji: isEmoji, replyID: replyID)
						if case let .channel(channel) = destination {
							// We must refresh the channel to trigger a view update since its relationship
							// to messages is via a weak fetched property which is not updated by
							// `bleManager.sendMessage` unlike the user entity.
							Task { @MainActor in
								context.refresh(channel, mergeChanges: true)
							}
						}
					} catch {
						// Best effort
						Logger.services.warning("Failed to resend message \(messageID, privacy: .public)")
					}

				}
			}
			Button("Cancel", role: .cancel) {}
		}
	}
}
