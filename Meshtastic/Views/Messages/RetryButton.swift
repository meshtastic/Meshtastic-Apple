import SwiftUI
import OSLog

struct RetryButton: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	let message: MessageEntity
	let destination: MessageDestination
	let status: MessageDeliveryStatus
	let onMessageSent: (() -> Void)?
	@State private var isShowingDetails = false

	init(
		message: MessageEntity,
		destination: MessageDestination,
		status: MessageDeliveryStatus,
		onMessageSent: (() -> Void)? = nil
	) {
		self.message = message
		self.destination = destination
		self.status = status
		self.onMessageSent = onMessageSent
	}

	var body: some View {
		Button {
			isShowingDetails = true
		} label: {
			Image(systemName: "exclamationmark.circle")
				.foregroundColor(.gray)
				.frame(height: 30)
				.padding(.top, 5)
		}
		.accessibilityLabel("Message status")
		.accessibilityHint(status.detail)
		.alert(status.text, isPresented: $isShowingDetails) {
			if status.canRetry {
				Button("Try Again", action: retryMessage)
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text(status.detail)
		}
	}

	private func retryMessage() {
		guard status.canRetry, accessoryManager.isConnected else {
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
				if case .channel = destination {
					await MainActor.run { onMessageSent?() }
				}
			} catch {
				// Best effort
				Logger.services.warning("Failed to resend message \(messageID, privacy: .public)")
			}

		}
	}
}
