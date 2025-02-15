import SwiftUI
import CoreData

struct MessageContextMenuItems: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	let message: MessageEntity
	let tapBackDestination: MessageDestination
	let isCurrentUser: Bool
	@Binding var isShowingDeleteConfirmation: Bool
	let onReply: () -> Void

	var body: some View {
		VStack {
			if message.pkiEncrypted {
				Label("Encrypted", systemImage: "lock")
			}
			Text("Channel") + Text(": \(message.channel)")
		}

		Menu("Tapback") {
			ForEach(Tapbacks.allCases) { tb in
				Button {
					let sentMessage = bleManager.sendMessage(
						message: tb.emojiString,
						toUserNum: tapBackDestination.userNum,
						channel: tapBackDestination.channelNum,
						isEmoji: true,
						replyID: message.messageId
					)
					if sentMessage {
						self.context.refresh(tapBackDestination.managedObject, mergeChanges: true)
					}
				} label: {
					Text(tb.description)
					Image(uiImage: tb.emojiString.image()!)
				}
			}
		}

		Button(action: onReply) {
			Text("Reply")
			Image(systemName: "arrowshape.turn.up.left")
		}

		Button {
			UIPasteboard.general.string = message.messagePayload
		} label: {
			Text("Copy")
			Image(systemName: "doc.on.doc")
		}

		Menu("message.details") {
			VStack {
				let messageDate = Date(timeIntervalSince1970: TimeInterval(message.messageTimestamp))
				Text("\(messageDate.formattedDate(format: MessageText.dateFormatString))").foregroundColor(.gray)
			}

			if !isCurrentUser && !(message.fromUser?.userNode?.viaMqtt ?? false) &&  message.fromUser?.userNode?.hopsAway ?? -1 == 0 {
				VStack {
					Text("SNR \(String(format: "%.2f", message.snr)) dB")
					Text("RSSI \(String(format: "%.2f", message.rssi)) dBm")
				}
			} else if !isCurrentUser && !(message.fromUser?.userNode?.viaMqtt ?? false) {
				VStack {
					Text("Hops Away \(message.fromUser?.userNode?.hopsAway ?? 0)")
				}
			}
			if isCurrentUser && message.receivedACK {
				VStack {
					Text("received.ack") + Text(": \(message.receivedACK ? "✔️" : "")")
					Text("received.ack.real") + Text(": \(message.realACK ? "✔️" : "")")
				}
			} else if isCurrentUser && message.ackError == 0 {
				// Empty Error
				Text("Waiting")
			} else if isCurrentUser && message.ackError > 0 {
				let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
				Text("\(ackErrorVal?.display ?? "Empty Ack Error")")
					.fixedSize(horizontal: false, vertical: true)
			}
			if isCurrentUser {
				VStack {
					let ackDate = Date(timeIntervalSince1970: TimeInterval(message.ackTimestamp))
					let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())
					if ackDate >= sixMonthsAgo! {
						Text("Ack Time: \(ackDate.formattedDate(format: "h:mm:ss.SSSS a"))")
							.foregroundColor(.gray)
					}
				}
			}
			if message.ackSNR != 0 {
				VStack {
					Text("Ack SNR: \(String(format: "%.2f", message.ackSNR)) dB")
						.font(.caption2)
						.foregroundColor(.gray)
				}
			}
		}

		Divider()

		Button(role: .destructive) {
			isShowingDeleteConfirmation = true
		} label: {
			Text("delete")
			Image(systemName: "trash")
		}
	}
}

private extension MessageDestination {
	var managedObject: NSManagedObject {
		switch self {
		case let .user(user): return user
		case let .channel(channel): return channel
		}
	}
}
