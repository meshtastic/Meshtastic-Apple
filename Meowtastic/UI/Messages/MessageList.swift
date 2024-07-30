import CoreData
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct MessageList: View {
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
	private var channel: ChannelEntity?
	@State
	private var user: UserEntity?
	@State
	private var myInfo: MyInfoEntity
	@State
	private var replyMessageId: Int64 = 0
	@State
	private var nodeDetail: NodeInfoEntity?

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	private var messages: [MessageEntity]? {
		if let channel {
			return channel.allPrivateMessages
		}
		else if let user {
			return user.messageList
		}

		return nil
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
	private var connectedNode: Int64? {
		bleManager.connectedPeripheral?.num
	}

	var body: some View {
		ZStack(alignment: .bottom) {
			ScrollViewReader { scrollView in
				if let messages, !messages.isEmpty {
					messageList
						.scrollDismissesKeyboard(.interactively)
						.scrollIndicators(.hidden)
						.onAppear {
							scrollView.scrollTo(textFieldPlaceholderID)
						}
						.onChange(of: channel?.allPrivateMessages) {
							if let id = channel?.allPrivateMessages?.last?.messageId {
								scrollView.scrollTo(id)
							}
						}
						.onChange(of: user?.messageList) {
							if let id = user?.messageList?.last?.messageId {
								scrollView.scrollTo(id)
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
						ble: bleManager,
						mqttUplinkEnabled: channel.uplinkEnabled,
						mqttDownlinkEnabled: channel.downlinkEnabled
					)
				}
				else {
					ConnectedDevice(ble: bleManager)
				}
			}
		}
		.sheet(item: $nodeDetail) { detail in
			NodeDetail(isInSheet: true, node: detail)
				.presentationDetents([.medium])
		}
	}

	@ViewBuilder
	private var messageList: some View {
		List {
			if let messages {
				ForEach(messages, id: \.messageId) { message in
					messageView(for: message)
						.id(message.messageId)
						.frame(width: .infinity)
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
						.scrollContentBackground(.hidden)
				}
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
		myInfo: MyInfoEntity
	) {
		self.channel = channel
		self.user = nil
		self.myInfo = myInfo
	}

	init(
		user: UserEntity,
		myInfo: MyInfoEntity
	) {
		self.channel = nil
		self.user = user
		self.myInfo = myInfo
	}

	@ViewBuilder
	private func messageView(for message: MessageEntity) -> some View {
		let isCurrentUser = isCurrentUser(message: message, preferredNum: preferredPeripheralNum)
		let sourceNode = message.fromUser?.userNode

		HStack(alignment: isCurrentUser ? .bottom : .top, spacing: 8) {
			if isCurrentUser {
				Spacer()
			}
			else {
				VStack(alignment: .center) {
					Avatar(
						message.fromUser?.userNode,
						size: 64,
						corners: isCurrentUser ? (true, true, false, true) : nil
					)

					if let connectedNode, let sourceNode {
						NodeIconListView(
							connectedNode: connectedNode,
							small: true,
							node: sourceNode
						)
					}
				}
				.frame(width: 64)
				.onTapGesture {
					if sourceNode != nil {
						nodeDetail = sourceNode
					}
				}
			}

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
						.id(message.messageId)

						if isCurrentUser && message.canRetry {
							RetryButton(message: message, destination: destination)
						}
					}
				}

				TapbackResponses(message: message) {
					appState.unreadChannelMessages = myInfo.unreadMessages
					context.refresh(myInfo, mergeChanges: true)
				}
			}

			if isCurrentUser {
				Avatar(
					message.fromUser?.userNode,
					size: 64
				)
			}
			else {
				Spacer()
			}
		}
		.frame(maxWidth: .infinity)
		.onAppear {
			guard !message.read else {
				return
			}

			message.read = true
			try? context.save()

			appState.unreadChannelMessages = myInfo.unreadMessages
			context.refresh(myInfo, mergeChanges: true)
		}
	}

	private func getOriginalMessage(for message: MessageEntity) -> String? {
		if
			message.replyID > 0,
			let messages = channel?.allPrivateMessages,
			let messageReply = messages.first(where: { msg in
				msg.messageId == message.replyID
			}),
			let messagePayload = messageReply.messagePayload
		{
			return messagePayload
		}

		if
			message.replyID > 0,
			let messages = user?.messageList,
			let messageReply = messages.first(where: { msg in
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
