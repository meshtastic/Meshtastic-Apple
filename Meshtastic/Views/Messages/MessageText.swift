import MeshtasticProtobufs
import OSLog
import SwiftUI

struct MessageText: View {
	static let linkBlue = Color(red: 0.4627, green: 0.8392, blue: 1) /* #76d6ff */
	static let localeDateFormat = DateFormatter.dateFormat(
		fromTemplate: "yyMMddjmmssa",
		options: 0,
		locale: Locale.current
	)
	static let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mm:ss:a")

	@Environment(\.managedObjectContext) var context

	let message: MessageEntity
	let tapBackDestination: MessageDestination
	let isCurrentUser: Bool
	let onReply: () -> Void

	@State private var isShowingDeleteConfirmation = false

	var body: some View {
		let markdownText = LocalizedStringKey(message.messagePayloadMarkdown ?? (message.messagePayload ?? "EMPTY MESSAGE"))
		return Text(markdownText)
			.tint(Self.linkBlue)
			.padding(.vertical, 10)
			.padding(.horizontal, 8)
			.foregroundColor(.white)
			.background(isCurrentUser ? .accentColor : Color(.gray))
			.cornerRadius(15)
			.overlay {
				/// Show the lock if the message is pki encrypted and has a real ack if sent by the current user, or is pki encrypted for incoming messages
				if message.pkiEncrypted && message.realACK || !isCurrentUser && message.pkiEncrypted {
					VStack(alignment: .trailing) {
						Spacer()
						HStack {
							Spacer()
							Image(systemName: "lock.circle.fill")
							.symbolRenderingMode(.palette)
							.foregroundStyle(.white, .green)
							.font(.system(size: 20))
							.offset(x: 8, y: 8)
						}
					}
				}
				let isStoreAndForward = message.portNum == Int32(PortNum.storeForwardApp.rawValue)
				let isDetectionSensorMessage = message.portNum == Int32(PortNum.detectionSensorApp.rawValue)
				if isStoreAndForward {
					VStack(alignment: .trailing) {
						Spacer()
						HStack {
							Spacer()
							Image(systemName: "envelope.circle.fill")
							.symbolRenderingMode(.palette)
							.foregroundStyle(.white, .gray)
							.font(.system(size: 20))
							.offset(x: 8, y: 8)
						}
					}
				}
				if tapBackDestination.overlaySensorMessage {
					VStack {
						isDetectionSensorMessage ? Image(systemName: "sensor.fill")
							.padding()
							.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
							.foregroundStyle(Color.orange)
							.symbolRenderingMode(.multicolor)
							.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
							.offset(x: 20, y: -20)
						: nil
					}
				} else {
					EmptyView()
				}
			}
			.contextMenu {
				MessageContextMenuItems(
					message: message,
					tapBackDestination: tapBackDestination,
					isCurrentUser: isCurrentUser,
					isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
					onReply: onReply
				)
			}
			.confirmationDialog(
				"Are you sure you want to delete this message?",
				isPresented: $isShowingDeleteConfirmation,
				titleVisibility: .visible
			) {
				Button("Delete Message", role: .destructive) {
					context.delete(message)
					do {
						try context.save()
					} catch {
						Logger.data.error("Failed to delete message \(message.messageId, privacy: .public): \(error.localizedDescription, privacy: .public)")
					}
				}
				Button("Cancel", role: .cancel) {}
			}
	}
}

private extension MessageDestination {
	var overlaySensorMessage: Bool {
		switch self {
		case .user: return false
		case .channel: return true
		}
	}
}
