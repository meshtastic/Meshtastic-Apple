import SwiftUI
import OSLog

struct TextMessageField: View {
	static let maxbytes = 200
	@EnvironmentObject var bleManager: BLEManager

	let destination: MessageDestination
	@Binding var replyMessageId: Int64
	@FocusState.Binding var isFocused: Bool
	let onSubmit: () -> Void

	@State private var typingMessage: String = ""
	@State private var totalBytes = 0
	@State private var sendPositionWithMessage = false

	var body: some View {
		#if targetEnvironment(macCatalyst)
		HStack {
			if destination.showAlertButton {
				Spacer()
				AlertButton { typingMessage += "🔔 Alert Bell! \u{7}" }
			}
			Spacer()
			RequestPositionButton(action: requestPosition)
			TextMessageSize(maxbytes: Self.maxbytes, totalBytes: totalBytes).padding(.trailing)
		}
		#endif

		HStack(alignment: .top) {
			ZStack {
				TextField("message", text: $typingMessage, axis: .vertical)
					.onChange(of: typingMessage, perform: { value in
						totalBytes = value.utf8.count
						// Only mess with the value if it is too big
						if totalBytes > Self.maxbytes {
							typingMessage = String(typingMessage.dropLast())
						}
					})
					.keyboardType(.default)
					.toolbar {
						ToolbarItemGroup(placement: .keyboard) {
							Button("dismiss.keyboard") {
								isFocused = false
							}
							.font(.subheadline)

							if destination.showAlertButton {
								Spacer()
								AlertButton { typingMessage += "🔔 Alert Bell Character! \u{7}" }
							}

							Spacer()
							RequestPositionButton(action: requestPosition)
							TextMessageSize(maxbytes: Self.maxbytes, totalBytes: totalBytes)
						}
					}
					.padding(.horizontal, 8)
					.focused($isFocused)
					.multilineTextAlignment(.leading)
					.frame(minHeight: 50)
					.keyboardShortcut(.defaultAction)
					.onSubmit {
					#if targetEnvironment(macCatalyst)
						sendMessage()
					#endif
					}

				Text(typingMessage)
					.opacity(0)
					.padding(.all, 0)
			}
			.overlay(RoundedRectangle(cornerRadius: 20).stroke(.tertiary, lineWidth: 1))
			.padding(.bottom, 15)

			Button(action: sendMessage) {
				Image(systemName: "arrow.up.circle.fill")
					.font(.largeTitle)
					.foregroundColor(.accentColor)
			}
		}
		.padding(.all, 15)
	}

	private func requestPosition() {
		let userLongName = bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown"
		sendPositionWithMessage = true
		typingMessage =  "📍 " + userLongName + " \(destination.positionShareMessage)."
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
