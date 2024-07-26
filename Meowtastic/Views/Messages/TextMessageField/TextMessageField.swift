import MeshtasticProtobufs
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

	private var backgroundColor: Color {
		let opacity: Double
		if totalBytes == 0 {
			opacity = 0.85
		}
		else {
			opacity = 1.00
		}

		if colorScheme == .dark {
			return Color.black.opacity(opacity)
		}
		else {
			return Color.white.opacity(opacity)
		}
	}

	var body: some View {
		HStack(alignment: .top, spacing: 8) {
			TextField("", text: $typingMessage, axis: .vertical)
				.font(.body)
				.multilineTextAlignment(.leading)
				.keyboardType(.default)
				.keyboardShortcut(.defaultAction)
				.focused($isFocused, equals: true)
				.padding(.leading, 8)
				.padding(.vertical, 4)
				.onSubmit {
					if typingMessage.isEmpty || totalBytes > maxBytes {
						return
					}

					sendMessage()
				}
				.onChange(of: typingMessage, initial: true) {
					totalBytes = typingMessage.utf8.count
				}

			VStack(alignment: .center, spacing: 0) {
				let remaining = maxBytes - totalBytes

				Button(action: sendMessage) {
					Image(systemName: "paperplane.circle")
						.resizable()
						.scaledToFit()
						.foregroundColor(.accentColor)
						.frame(width: 32, height: 32)
				}
				.disabled(typingMessage.isEmpty || remaining <= 0)

				Text(String(remaining))
					.font(.system(size: 8, design: .rounded))
					.fontWeight(remaining < 24 ? .bold : .regular)
					.foregroundColor(remaining < 24 ? .red : .gray)
					.padding(.top, 4)
			}
		}
		.padding(.all, 2)
		.background(backgroundColor)
		.overlay(
			overallShape
				.stroke(.tertiary, lineWidth: 1)
		)
		.clipShape(
			overallShape
		)
		.onTapGesture {
			isFocused = true
		}
	}

	@ViewBuilder
	private var overallShape: UnevenRoundedRectangle {
		let radii = RectangleCornerRadii(
			topLeading: 18,
			bottomLeading: 18,
			bottomTrailing: 0,
			topTrailing: 18
		)

		UnevenRoundedRectangle(cornerRadii: radii, style: .circular)
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
		case .channel: return Int64(Constants.maximumNodeNum)
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
