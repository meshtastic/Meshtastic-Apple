import SwiftUI
import CoreData

struct MessageContextMenuItems: View {
	@Binding
	var isShowingDeleteConfirmation: Bool

	let message: MessageEntity
	let tapBackDestination: MessageDestination
	let isCurrentUser: Bool
	let onReply: () -> Void

	private let dateFormatString = {
		let format = DateFormatter.dateFormat(
			fromTemplate: "yyMMddjmmssa",
			options: 0,
			locale: Locale.current
		)

		return format ?? "MM/dd/YY j:mm:ss:a"
	}()

	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager

	var body: some View {
		Menu("tapback") {
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
			Text("Copy message text")
			Image(systemName: "doc.on.doc")
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
