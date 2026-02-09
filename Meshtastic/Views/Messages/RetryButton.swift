import SwiftUI
import OSLog

struct RetryButton: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	
	let message: MessageEntity
	let destination: MessageDestination
	@State var isShowingConfirmation = false
	@State private var isRetrying: Bool = false
	@State private var retryCount: Int = 0
	
	var body: some View {
		Button {
			isShowingConfirmation = true
		} label: {
			Group {
				if isRetrying {
					ProgressView()
						.progressViewStyle(CircularProgressViewStyle(tint: .orange))
						.scaleEffect(0.8)
				} else {
					Image(systemName: "exclamationmark.circle")
						.foregroundColor(.orange)
				}
			}
			.frame(height: 30)
			.padding(.top, 5)
		}
		.onAppear {
			updateRetryStatus()
		}
		.confirmationDialog(
			getDialogTitle(),
			isPresented: $isShowingConfirmation,
			titleVisibility: .visible
		) {
			if isRetrying {
				Button("Cancel Retry", role: .destructive) {
					cancelRetry()
				}
			} else {
				Button("Try Again") {
					resendMessage()
				}
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			if isRetrying {
				Text("This message is currently being retried (\(retryCount > 0 ? "retry \(retryCount)" : "waiting to retry")). Would you like to cancel the retry?")
			} else {
				Text("This message was likely not delivered. Would you like to try again?")
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
			updateRetryStatus()
		}
		.onReceive(NotificationCenter.default.publisher(for: MessageRetryQueueManager.didUpdateNotification)) { _ in
			updateRetryStatus()
		}
	}
	
	private func getDialogTitle() -> String {
		if isRetrying {
			return "Cancel Retry?"
		} else {
			return "Retry Message?"
		}
	}
	
	private func updateRetryStatus() {
		let messageId = message.messageId
		Task {
			let status = await MessageRetryQueueManager.shared.getRetryStatus(for: messageId)
			await MainActor.run {
				if let (current, _, state) = status {
					isRetrying = state == .pending || state == .waitingForAck || state == .sending
					retryCount = current
				} else {
					isRetrying = false
					retryCount = 0
				}
			}
		}
	}
	
	private func cancelRetry() {
		Task {
			await MessageRetryQueueManager.shared.cancelRetry(for: message.messageId)
		}
	}
	
	private func resendMessage() {
		guard accessoryManager.isConnected else {
			return
		}
		
		Task {
			await MessageRetryQueueManager.shared.cancelRetry(for: message.messageId)
		}
		
		let messageID = message.messageId
		let payload = message.messagePayload ?? ""
		let userNum = message.toUser?.num ?? 0
		let channel = message.channel
		let isEmoji = message.isEmoji
		let replyID = message.replyID
		
		Task {
			do {
				try await accessoryManager.sendMessage(message: payload, toUserNum: userNum, channel: channel,
													   isEmoji: isEmoji, replyID: replyID)
				if case let .channel(channel) = destination {
					Task { @MainActor in
						context.refresh(channel, mergeChanges: true)
					}
				}
			} catch {
				Logger.services.warning("Failed to resend message \(messageID)")
			}
		}
	}
}
