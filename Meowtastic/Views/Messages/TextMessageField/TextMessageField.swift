import SwiftUI
import OSLog

struct TextMessageField: View {
	let destination: MessageDestination
	let onSubmit: () -> Void

	private let maxBytes = 228

	@Binding
	var replyMessageId: Int64
	@FocusState.Binding
	var isFocused: Bool

	@EnvironmentObject
	private var bleManager: BLEManager
	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@State
	private var typingMessage = ""
	@State
	private var sendPositionWithMessage = false
	@State
	private var totalBytes = 0

	var body: some View {
		HStack(alignment: .center, spacing: 8) {
			TextField("Message", text: $typingMessage, axis: .vertical)
				.font(.body)
				.padding(.leading, 4)
				.multilineTextAlignment(.leading)
				.keyboardType(.default)
				.keyboardShortcut(.defaultAction)
				.focused($isFocused)
				.onSubmit {
					if typingMessage.isEmpty || totalBytes > maxBytes {
						return
					}

					sendMessage()
				}
				.onChange(of: typingMessage, initial: true) {
					totalBytes = typingMessage.utf8.count
				}

			Button(action: sendMessage) {
				Image(systemName: "paperplane.circle")
					.resizable()
					.scaledToFit()
					.foregroundColor(.accentColor)
					.frame(width: 32, height: 32)
			}
			.disabled(typingMessage.isEmpty || totalBytes > maxBytes)
		}
		.padding(.all, 4)
		.background(colorScheme == .dark ? Color.black.opacity(0.85) : Color.white.opacity(0.85))
		.overlay(
			overallShape
				.stroke(.tertiary, lineWidth: 1)
		)
		.clipShape(
			overallShape
		)
	}

	@ViewBuilder
	private var overallShape: RoundedRectangle {
		RoundedRectangle(cornerRadius: 24)
	}

	private func sendMessage() {
		let messageSent = bleManager.sendMessage(
			message: typingMessage,
			toUserNum: destination.userNum,
			channel: destination.channelNum,
			isEmoji: false,
			replyID: replyMessageId
		)

		if messageSent {
			typingMessage = ""
			isFocused = false
			replyMessageId = 0

			onSubmit()

			if sendPositionWithMessage {
				let positionSent = bleManager.sendPosition(
					channel: destination.channelNum,
					destNum: destination.positionDestNum,
					wantResponse: destination.wantPositionResponse
				)

				if positionSent {
					Logger.mesh.info("Location Sent")
				}
			}
		}
	}
}

private extension MessageDestination {
	var positionDestNum: Int64 {
		switch self {
		case let .user(user): return user.num
		case .channel: return Int64(BLEManager.emptyNodeNum)
		}
	}

	var showAlertButton: Bool {
		switch self {
		case .user: return true
		case .channel: return true
		}
	}

	var wantPositionResponse: Bool {
		switch self {
		case .user: return true
		case .channel: return false
		}
	}
}
