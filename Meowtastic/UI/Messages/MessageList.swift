import CoreData
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct MessageList: View {
	private let channel: ChannelEntity?
	private let user: UserEntity?
	private let myInfo: MyInfoEntity?
	private let textFieldPlaceholderID = "text_field_placeholder"

	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager
	@AppStorage("preferredPeripheralNum")
	private var preferredPeripheralNum = -1
	@StateObject
	private var appState = AppState.shared
	@FocusState
	private var messageFieldFocused: Bool
	@State
	private var nodeDetail: NodeInfoEntity?
	@State
	private var replyMessageId: Int64 = 0

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		]
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "messageTimestamp", ascending: true)
		]
	)
	private var messages: FetchedResults<MessageEntity>

	private var filteredMessages: [MessageEntity] {
		if let channel {
			return messages.filter { message in
				message.channel == channel.index && message.toUser == nil
			} as [MessageEntity]
		}
		else if let user {
			return messages.filter { message in
				message.toUser != nil && message.fromUser != nil
				&& (message.toUser?.num == user.num || message.fromUser?.num == user.num)
				&& !message.admin
				&& message.portNum != 10
			} as [MessageEntity]
		}

		return [MessageEntity]()
	}
	private var firstUnreadMessage: MessageEntity? {
		filteredMessages.first(where: { message in
			!message.read
		})
	}
	private var destination: MessageDestination? {
		if let channel {
			return .channel(channel)
		}
		else if let user {
			return .user(user)
		}

		return nil
	}
	private var screenTitle: String {
		if let channel {
			if let name = channel.name, !name.isEmpty {
				return name.camelCaseToWords()
			}
			else {
				if channel.role == 1 {
					return "Primary Channel"
				}
				else {
					return "Channel #\(channel.index)"
				}
			}
		}
		else if let user {
			if let name = user.longName {
				return name
			}
			else {
				return "DM"
			}
		}

		return ""
	}
	private var connectedNodeNum: Int64? {
		bleManager.connectedPeripheral?.num
	}

	var body: some View {
		ZStack(alignment: .bottom) {
			ScrollViewReader { scrollView in
				if !filteredMessages.isEmpty {
					messageList
						.scrollDismissesKeyboard(.interactively)
						.scrollIndicators(.hidden)
						.onAppear {
						}
						.onChange(of: filteredMessages, initial: true) {
							if let firstUnreadMessage {
								scrollView.scrollTo(firstUnreadMessage)
							}
							else {
								scrollView.scrollTo(textFieldPlaceholderID)
							}
						}
				}
				else {
					ContentUnavailableView(
						"No Messages",
						systemImage: channel != nil ? "bubble.left.and.bubble.right" : "bubble"
					)
				}
			}

			if let destination {
				TextMessageField(
					destination: destination,
					onSubmit: {
						if let channel {
							context.refresh(channel, mergeChanges: true)
						}
						else if let user {
							context.refresh(user, mergeChanges: true)
						}
					},
					replyMessageId: $replyMessageId,
					isFocused: $messageFieldFocused
				)
				.frame(alignment: .bottom)
				.padding(.horizontal, 16)
				.padding(.bottom, 8)
			}
			else {
				EmptyView()
			}
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				Text(screenTitle)
					.font(.headline)
			}

			ToolbarItem(placement: .navigationBarTrailing) {
				if let channel {
					ConnectedDevice(
						mqttUplinkEnabled: channel.uplinkEnabled,
						mqttDownlinkEnabled: channel.downlinkEnabled
					)
				}
				else {
					ConnectedDevice()
				}
			}
		}
		.sheet(item: $nodeDetail) { detail in
			NodeDetail(isInSheet: true, node: detail)
				.presentationDragIndicator(.visible)
				.presentationDetents([.medium])
		}
	}

	@ViewBuilder
	private var messageList: some View {
		List {
			ForEach(filteredMessages, id: \.messageId) { message in
				messageView(for: message)
					.listRowSeparator(.hidden)
					.listRowBackground(Color.clear)
					.scrollContentBackground(.hidden)
			}

			Rectangle()
				.id(textFieldPlaceholderID)
				.foregroundColor(.clear)
				.frame(height: 48)
				.listRowSeparator(.hidden)
				.listRowBackground(Color.clear)
				.scrollContentBackground(.hidden)
		}
		.listStyle(.plain)
	}

	init(
		channel: ChannelEntity,
		myInfo: MyInfoEntity?
	) {
		self.channel = channel
		self.user = nil
		self.myInfo = myInfo

		Logger.app.warning("message list init'd")
	}

	init(
		user: UserEntity,
		myInfo: MyInfoEntity?
	) {
		self.channel = nil
		self.user = user
		self.myInfo = myInfo

		Logger.app.warning("message list init'd")
	}

	@ViewBuilder
	private func messageView(for message: MessageEntity) -> some View {
		let isCurrentUser = isCurrentUser(message: message, preferredNum: preferredPeripheralNum)

		HStack(alignment: isCurrentUser ? .bottom : .top, spacing: 8) {
			leadingAvatar(for: message)
			content(for: message)
			trailingAvatar(for: message)
		}
		.frame(maxWidth: .infinity)
		.onAppear {
			guard !message.read else {
				return
			}

			message.read = true
			try? context.save()

			if let myInfo {
				appState.unreadChannelMessages = myInfo.unreadMessages
				context.refresh(myInfo, mergeChanges: true)
			}
		}
	}

	@ViewBuilder
	private func leadingAvatar(for message: MessageEntity) -> some View {
		let isCurrentUser = isCurrentUser(message: message, preferredNum: preferredPeripheralNum)

		if isCurrentUser {
			Spacer()
		}
		else {
			VStack(alignment: .center) {
				if let node = message.fromUser?.userNode {
					AvatarNode(
						node,
						size: 64,
						corners: isCurrentUser ? (true, true, false, true) : nil
					)
				}
				else {
					AvatarAbstract(
						size: 64,
						corners: isCurrentUser ? (true, true, false, true) : nil
					)
				}
			}
			.frame(width: 64)
			.onTapGesture {
				if let sourceNode = message.fromUser?.userNode {
					nodeDetail = sourceNode
				}
			}
		}
	}

	@ViewBuilder
	private func trailingAvatar(for message: MessageEntity) -> some View {
		let isCurrentUser = isCurrentUser(message: message, preferredNum: preferredPeripheralNum)

		if isCurrentUser {
			if let node = message.fromUser?.userNode {
				AvatarNode(
					node,
					size: 64
				)
			}
			else {
				AvatarAbstract(
					size: 64
				)
			}
		}
		else {
			Spacer()
		}
	}

	@ViewBuilder
	private func content(for message: MessageEntity) -> some View {
		let isCurrentUser = isCurrentUser(message: message, preferredNum: preferredPeripheralNum)

		VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
			if !isCurrentUser {
				HStack(spacing: 4) {
					if message.fromUser != nil {
						Image(systemName: "person")
							.font(.caption)
							.foregroundColor(.gray)

						Text(getSenderName(message: message))
							.font(.caption)
							.lineLimit(1)
							.foregroundColor(.gray)

						if let node = message.fromUser?.userNode, let connectedNodeNum {
							NodeIconListView(
								connectedNode: connectedNodeNum,
								small: true,
								node: node
							)
						}
					}
					else {
						Image(systemName: "person.fill.questionmark")
							.font(.caption)
							.foregroundColor(.gray)
					}
				}
			}
			else {
				EmptyView()
			}

			if let destination {
				HStack(spacing: 0) {
					MessageView(
						message: message,
						originalMessage: getOriginalMessage(for: message),
						tapBackDestination: destination,
						isCurrentUser: isCurrentUser
					) {
						replyMessageId = message.messageId
						messageFieldFocused = true
					}

					if isCurrentUser && message.canRetry {
						RetryButton(message: message, destination: destination)
					}
				}
			}
		}
	}

	private func getOriginalMessage(for message: MessageEntity) -> String? {
		if
			message.replyID > 0,
			let messageReply = filteredMessages.first(where: { msg in
				msg.messageId == message.replyID
			}),
			let messagePayload = messageReply.messagePayload
		{
			return messagePayload
		}

		return nil
	}

	private func isCurrentUser(message: MessageEntity, preferredNum: Int) -> Bool {
		Int64(preferredNum) == message.fromUser?.num
	}

	private func getUserColor(for node: NodeInfoEntity?) -> Color {
		if let node, node.isOnline {
			return Color(
				UIColor(hex: UInt32(node.num))
			)
		}
		else {
			return Color.gray.opacity(0.7)
		}
	}

	private func getSenderName(message: MessageEntity, short: Bool = false) -> String {
		let shortName = message.fromUser?.shortName
		let longName = message.fromUser?.longName

		if short {
			if let shortName {
				return shortName
			}
			else {
				return ""
			}
		}
		else {
			if let longName {
				return longName
			}
			else {
				return "Unknown Name"
			}
		}
	}
}
