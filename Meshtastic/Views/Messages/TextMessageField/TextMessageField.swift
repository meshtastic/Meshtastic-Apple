import SwiftUI

struct TextMessageField: View {
	static let maxbytes = 228
	@EnvironmentObject var bleManager: BLEManager
	
	let destination: Destination
	@Binding var replyMessageId: Int64
	@FocusState.Binding var isFocused: Bool
	let onSubmit: () -> Void

	enum Destination {
		case user(Int64)
		case channel(Int32)
	}
	
	@State private var typingMessage: String = ""
	@State private var totalBytes = 0
	@State private var sendPositionWithMessage = false

	var body: some View {
		#if targetEnvironment(macCatalyst)
		HStack {
			if destination.showAlertButton {
				Spacer()
				AlertButton { typingMessage += "🔔 Alert Bell Character! \u{7}" }
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
							let firstNBytes = Data(typingMessage.utf8.prefix(Self.maxbytes))
							if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
								// Set the message back to the last place where it was the right size
								typingMessage = maxBytesString
							} else {
								print("not a valid UTF-8 sequence")
							}
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
					print("Location Sent")
				}
			}
		}
	}
}

private extension TextMessageField.Destination {
	var positionShareMessage: String {
		switch self {
		case .user: return "has shared their position and requested a response with your position"
		case .channel: return "has shared their position with you"
		}
	}
	
	var userNum: Int64 {
		switch self {
		case let .user(num): return num
		case .channel: return 0
		}
	}
	
	var channelNum: Int32 {
		switch self {
		case .user: return 0
		case let .channel(num): return num
		}
	}
	
	var positionDestNum: Int64 {
		switch self {
		case let .user(num): return num
		case .channel: return Int64(BLEManager.emptyNodeNum)
		}
	}

	var showAlertButton: Bool {
		switch self {
		case .user: return false
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
