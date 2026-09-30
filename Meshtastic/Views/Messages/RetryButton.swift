import SwiftUI
import OSLog

struct RetryButton: View {
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
		.accessibilityLabel(String(localized: "Message status", comment: "VoiceOver label for the message delivery status button"))
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

	/// Sends the same message again rather than replacing it.
	///
	/// This used to delete the message and send a new one, which gave it a new id and a new
	/// timestamp: the row disappeared from the conversation and a different one appeared at the
	/// bottom. A send that threw left nothing behind at all, so the text was gone.
	private func retryMessage() {
		guard status.canRetry, accessoryManager.isConnected else {
			return
		}
		let messageID = message.messageId
		let message = self.message
		Task {
			do {
				try await accessoryManager.resendMessage(message)
				if case .channel = destination {
					await MainActor.run { onMessageSent?() }
				}
			} catch {
				// The message keeps its row and its failed status, so there is something to
				// try again on rather than a hole in the conversation.
				Logger.services.warning("Failed to resend message \(messageID, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
	}
}
