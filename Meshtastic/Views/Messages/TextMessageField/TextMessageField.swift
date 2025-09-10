import SwiftUI
import OSLog
import DatadogSessionReplay

struct TextMessageField: View {
	static let maxbytes = 200
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.horizontalSizeClass) var horizontalSizeClass
	@Environment(\.dismiss) var dismiss

	let destination: MessageDestination
	@Binding var replyMessageId: Int64
	@FocusState.Binding var isFocused: Bool

	@State private var typingMessage: String = ""
	@State private var totalBytes = 0
	@State private var sendPositionWithMessage = false

	var body: some View {
		SessionReplayPrivacyView(textAndInputPrivacy: .maskAllInputs) {
			VStack(spacing: 0) {
				HStack(alignment: .bottom) {
					if replyMessageId != 0 || isFocused {
						Button {
							withAnimation(.easeInOut(duration: 0.2)) {
								replyMessageId = 0
							}
							isFocused = false
						} label: {
							Image(systemName: "x.circle.fill")
								.font(.largeTitle)
						}
						if replyMessageId != 0 {
							Text("Reply")
								.padding(.bottom, 10)
						}
					}
					TextField("Message", text: $typingMessage, axis: .vertical)
						.padding(10)
						.background(
							Capsule()
								.strokeBorder(.tertiary, lineWidth: 1)
								.background(Capsule().fill(Color(.secondarySystemBackground)))
						)
						.clipShape(Capsule())
						.onChange(of: typingMessage) { _, value in
							totalBytes = value.utf8.count
							while totalBytes > Self.maxbytes {
								typingMessage = String(typingMessage.dropLast())
								totalBytes = typingMessage.utf8.count
							}
						}
						.keyboardType(.default)
						.focused($isFocused)
						.multilineTextAlignment(.leading)
						.onSubmit {
#if targetEnvironment(macCatalyst)
							sendMessage()
#endif
						}
						.foregroundColor(.primary)
					if !typingMessage.isEmpty {
						Button(action: sendMessage) {
							Image(systemName: "arrow.up.circle.fill")
								.font(.largeTitle)
								.foregroundColor(.accentColor)
						}
					}
				}
				.padding(15)
				Divider()
				if isFocused {
					HStack {
						Spacer()
						AlertButton { typingMessage += "🔔 Alert Bell Character! \u{7}" }
						Spacer()
						RequestPositionButton(action: requestPosition)
						Spacer()
						TextMessageSize(maxbytes: Self.maxbytes, totalBytes: totalBytes)
					}
					.padding(.horizontal, 15)
					.padding(.vertical, 10)
					.background(.bar)
				}
			}
		}
	}

	private func requestPosition() {
		let userLongName = accessoryManager.activeConnection?.device.longName ?? "Unknown"
		sendPositionWithMessage = true
		typingMessage = "📍 " + userLongName + " \(destination.positionShareMessage)."
	}

	private func sendMessage() {
		Task {
			do {
				try await accessoryManager.sendMessage(
					message: typingMessage,
					toUserNum: destination.userNum,
					channel: destination.channelNum,
					isEmoji: false,
					replyID: replyMessageId)

				typingMessage = ""
				isFocused = false
				replyMessageId = 0

				if sendPositionWithMessage {
					try await accessoryManager.sendPosition(
						channel: destination.channelNum,
						destNum: destination.positionDestNum,
						wantResponse: destination.wantPositionResponse
					)
					Logger.mesh.info("Location Sent")
				}
			} catch {
				Logger.mesh.info("Error sending message")
			}
		}
	}
}

private extension MessageDestination {
	var positionShareMessage: String {
		switch self {
		case .user: return "has shared their position and requested a response with your position"
		case .channel: return "has shared their position with you"
		}
	}

	var positionDestNum: Int64 {
		switch self {
		case let .user(user): return user.num
		case .channel: return Int64(Constants.maximumNodeNum)
		}
	}

	var wantPositionResponse: Bool {
		switch self {
		case .user: return true
		case .channel: return false
		}
	}
}
