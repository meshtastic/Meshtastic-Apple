import CoreData
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct ChannelMessageList: View {
	@StateObject
	var appState = AppState.shared
	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager
	@FocusState
	var messageFieldFocused: Bool
	@ObservedObject
	var myInfo: MyInfoEntity
	@ObservedObject
	var channel: ChannelEntity

	private let textFieldPlaceholderID = "text_field_placeholder"

	@AppStorage("preferredPeripheralNum")
	private var preferredPeripheralNum = -1
	@State
	private var replyMessageId: Int64 = 0
	@State
	private var nodeDetail: NodeInfoEntity?

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true),
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	private var screenTitle: String {
		if let name = channel.name, !name.isEmpty {
			name.camelCaseToWords()
		}
		else {
			if channel.role == 1 {
				"Primary Channel"
			}
			else {
				"Channel #\(channel.index)"
			}
		}
	}

	private var connectedNode: Int64? {
		bleManager.connectedPeripheral?.num
	}

	var body: some View {
		ZStack(alignment: .bottom) {
			ScrollViewReader { scrollView in
				messageList
					.scrollDismissesKeyboard(.interactively)
					.scrollIndicators(.hidden)
					.onAppear {
						if bleManager.context == nil {
							bleManager.context = context
						}

						scrollView.scrollTo(textFieldPlaceholderID)
					}
					.onChange(of: channel.allPrivateMessages, initial: true) {
						if !channel.allPrivateMessages.isEmpty {
							scrollView.scrollTo(channel.allPrivateMessages.last!.messageId)
						}
					}
			}

			TextMessageField(
				destination: .channel(channel),
				onSubmit: {
					context.refresh(channel, mergeChanges: true)
				},
				replyMessageId: $replyMessageId,
				isFocused: $messageFieldFocused
			)
			.frame(alignment: .bottom)
			.padding(.horizontal, 16)
			.padding(.bottom, 8)
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				Text(screenTitle)
					.font(.headline)
			}

			ToolbarItem(placement: .navigationBarTrailing) {
				ConnectedDevice(
					ble: bleManager,
					mqttUplinkEnabled: channel.uplinkEnabled,
					mqttDownlinkEnabled: channel.downlinkEnabled
				)
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
			ForEach(channel.allPrivateMessages, id: \.messageId) { message in
				messageView(for: message)
					.id(message.messageId)
					.frame(width: .infinity)
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

	@ViewBuilder
	private func messageView(for message: MessageEntity) -> some View {
		let isCurrentUser = isCurrentUser(message: message, preferredNum: preferredPeripheralNum)
		let sourceNode = message.fromUser?.userNode

		HStack(alignment: .top, spacing: 8) {
			if isCurrentUser {
				Spacer()
					.frame(minWidth: 64)
			}
			else {
				VStack(alignment: .center) {
					Avatar(
						getSenderName(message: message, short: true),
						background: getSenderColor(message: message),
						size: 64
					)

					if let connectedNode, let sourceNode {
						NodeIconListView(connectedNode: connectedNode, small: true, node: sourceNode)
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

				HStack {
					MessageView(
						message: message,
						originalMessage: getOriginalMessage(for: message),
						tapBackDestination: .channel(channel),
						isCurrentUser: isCurrentUser
					) {
						replyMessageId = message.messageId
						messageFieldFocused = true
					}

					if isCurrentUser && message.canRetry {
						RetryButton(message: message, destination: .channel(channel))
					}
				}

				TapbackResponses(message: message) {
					appState.unreadChannelMessages = myInfo.unreadMessages

					let badge = appState.unreadChannelMessages + appState.unreadDirectMessages
					UNUserNotificationCenter.current().setBadgeCount(badge)

					context.refresh(myInfo, mergeChanges: true)
				}
			}
			.id(message.messageId)

			if !isCurrentUser {
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

			let badge = appState.unreadChannelMessages + appState.unreadDirectMessages
			UNUserNotificationCenter.current().setBadgeCount(badge)

			context.refresh(myInfo, mergeChanges: true)
		}
	}

	private func getOriginalMessage(for message: MessageEntity) -> String? {
		if message.replyID > 0,
		   let messageReply = channel.allPrivateMessages.first(where: {
			   $0.messageId == message.replyID
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

	private func getSenderColor(message: MessageEntity) -> Color {
		if
			let num = message.fromUser?.num,
			message.fromUser?.userNode?.isOnline ?? false
		{
			return Color(
				UIColor(hex: UInt32(num))
			)
		}

		return Color.gray.opacity(0.7)
	}
}
