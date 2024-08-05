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
	private var nodeDetail: NodeInfoEntity?
	@State
	private var channel: ChannelEntity?
	@State
	private var user: UserEntity?
	@State
	private var myInfo: MyInfoEntity
	@State
	private var replyMessageId: Int64 = 0
	@State
	private var scrolledToId: Int64?
	@State
	private var filteredMessages = [MessageEntity]()
	@State
	private var filteredMessagesTimestamp = Double.nan

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
							if let firstUnreadMessage {
								scrollView.scrollTo(firstUnreadMessage)
							}
							else {
								scrollView.scrollTo(textFieldPlaceholderID)
							}
						}
						.onChange(of: filteredMessages) {
							if let id = filteredMessages.last?.messageId, id != scrolledToId {
								scrollView.scrollTo(id)
								scrolledToId = id
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
		.onAppear {
			Task {
				await filterMessages()
			}
		}
		.onReceive(messages.publisher.count(), perform: { _ in
			Task {
				await filterMessages()
			}
		})
	}

	@ViewBuilder
	private var messageList: some View {
		List {
			ForEach(filteredMessages, id: \.messageId) { message in
				messageView(for: message)
					.id(message.messageId)
					.frame(maxWidth: .infinity)
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

					if let connectedNodeNum, let sourceNode {
						NodeIconListView(
							connectedNode: connectedNodeNum,
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

	private func filterMessages() async {
		let threshold = Date.now.timeIntervalSince1970 - 1
		guard filteredMessagesTimestamp.isNaN || filteredMessagesTimestamp < threshold else {
			// workaround for endless changing of message data
			// when fixed, it may be possible to use original solution
			return
		}

		if let channel {
			let filtered = messages.filter { message in
				message.channel == channel.index && message.toUser == nil
			} as [MessageEntity]

			if filtered.count != filteredMessages.count {
				filteredMessages = filtered
				filteredMessagesTimestamp = Date.now.timeIntervalSince1970
			}
		}
		else if let user {
			let filtered = messages.filter { message in
				message.toUser != nil && message.fromUser != nil
				&& (message.toUser?.num == user.num || message.fromUser?.num == user.num)
				&& !message.admin
				&& message.portNum != 10
			} as [MessageEntity]

			if filtered.count != filteredMessages.count {
				filteredMessages = filtered
				filteredMessagesTimestamp = Date.now.timeIntervalSince1970
			}
		}
		else {
			filteredMessages.removeAll()
			filteredMessagesTimestamp = Date.now.timeIntervalSince1970
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
