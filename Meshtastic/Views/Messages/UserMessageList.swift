//
//  UserMessageList.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import SwiftUI
@preconcurrency import SwiftData
import OSLog
import MeshtasticProtobufs // Added to ensure RoutingError is accessible if needed

private struct UserMessageTimelineCursor: Comparable {
	let timestamp: Int32
	let messageId: Int64

	static func < (lhs: UserMessageTimelineCursor, rhs: UserMessageTimelineCursor) -> Bool {
		if lhs.timestamp == rhs.timestamp {
			return lhs.messageId < rhs.messageId
		}
		return lhs.timestamp < rhs.timestamp
	}
}

private struct UserMessageListChangeToken: Equatable {
	let latest: UserMessageTimelineCursor?
	let count: Int
}

struct UserMessageList: View {
	@EnvironmentObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.scenePhase) var scenePhase
	@Environment(\.modelContext) private var context
	@FocusState var messageFieldFocused: Bool
	@Bindable var user: UserEntity
	@State private var replyMessageId: Int64 = 0
	@State private var messageToHighlight: Int64 = 0
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
	@State private var messageLimit: Int = 100
	@State private var messages: [MessageEntity] = []
	@State private var previousByID: [Int64: MessageEntity] = [:]
	@State private var repliesByID: [Int64: MessageEntity] = [:]
	@State private var tapbacksByReplyID: [Int64: [MessageEntity]] = [:]
	@State private var hasEarlierMessages = false
	@State private var latestKnownMessageToken: UserMessageListChangeToken?
	@State private var latestVisibleTapbackCursor: UserMessageTimelineCursor?
	@State private var latestKnownConversationTapbackCursor: UserMessageTimelineCursor?
	@State private var visibleTapbackCount = 0
	@State private var tapbackTargetMessage: MessageEntity?
	@State private var tapbackText = ""
	@FocusState var tapbackFocused: Bool

	init(user: UserEntity) {
		self.user = user
	}

	func markMessagesAsRead() {
		do {
			let unreadMessages = try fetchUnreadMessages()
			let notificationManager = LocalNotificationManager()
			var readMessageIDs = [Int64]()
			for unreadMessage in unreadMessages {
				unreadMessage.read = true
				readMessageIDs.append(unreadMessage.messageId)
			}
			for unreadTapback in tapbacksByReplyID.values.flatMap({ $0 }) where !unreadTapback.read {
				unreadTapback.read = true
				readMessageIDs.append(unreadTapback.messageId)
			}
			notificationManager.cancelNotificationsForMessageIds(readMessageIDs)
			if context.hasChanges {
				try context.save()
			}
			Logger.data.info("📖 [App] All unread direct messages marked as read for user \(user.num, privacy: .public).")

			if let connectedPeripheralNum = accessoryManager.activeDeviceNum,
			   let connectedNode = getNodeInfo(id: connectedPeripheralNum, context: context),
			   let connectedUser = connectedNode.user {
				appState.unreadDirectMessages = connectedUser.unreadMessages(context: context, skipLastMessageCheck: true) // skipLastMessageCheck=true because we don't update lastMessage on our own connected node
			}
		} catch {
			Logger.data.error("Failed to read direct messages: \(error.localizedDescription, privacy: .public)")
		}
	}

	@MainActor
	private func loadMessages(markReadAfterLoad: Bool = false) {
		do {
			let fetchedMessages = try fetchMessages(limit: messageLimit + 1)
			hasEarlierMessages = fetchedMessages.count > messageLimit

			let visibleMessages = Array(fetchedMessages.prefix(messageLimit).reversed())
			let previousMessage = hasEarlierMessages ? fetchedMessages[messageLimit] : nil

			messages = visibleMessages
			previousByID = buildPreviousByID(for: visibleMessages, previousMessage: previousMessage)
			repliesByID = try fetchReplies(for: visibleMessages)
			replaceTapbacks(try fetchTapbacks(for: visibleMessages))
			latestKnownMessageToken = try fetchMessageChangeToken(latestMessage: fetchedMessages.first)
			latestKnownConversationTapbackCursor = try fetchLatestTapbackCursor()

			if markReadAfterLoad {
				markMessagesAsRead()
			}
		} catch {
			Logger.data.error("Failed to fetch direct messages: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func fetchMessages(limit: Int) throws -> [MessageEntity] {
		let incoming = try fetchIncomingMessages(limit: limit, unreadOnly: false)
		let outgoing = try fetchOutgoingMessages(limit: limit, unreadOnly: false)

		return Array((incoming + outgoing)
			.sorted {
				if $0.messageTimestamp == $1.messageTimestamp {
					return $0.messageId > $1.messageId
				}
				return $0.messageTimestamp > $1.messageTimestamp
			}
			.prefix(limit))
	}

	private func fetchUnreadMessages() throws -> [MessageEntity] {
		try fetchIncomingMessages(unreadOnly: true) + fetchOutgoingMessages(unreadOnly: true)
	}

	private func fetchMessageChangeToken(latestMessage: MessageEntity? = nil) throws -> UserMessageListChangeToken {
		let latest = try latestMessage ?? fetchMessages(limit: 1).first
		return UserMessageListChangeToken(
			latest: latest.map(cursor(for:)),
			count: try fetchIncomingMessageCount() + fetchOutgoingMessageCount()
		)
	}

	private func fetchIncomingMessageCount() throws -> Int {
		let userNum = user.num
		let detectionSensorPortNum: Int32 = 10
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.fromUser?.num == userNum
				&& $0.toUser != nil
				&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
			}
		)
		return try context.fetchCount(descriptor)
	}

	private func fetchOutgoingMessageCount() throws -> Int {
		let userNum = user.num
		let detectionSensorPortNum: Int32 = 10
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.toUser?.num == userNum
				&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
			}
		)
		return try context.fetchCount(descriptor)
	}

	private func fetchIncomingMessages(limit: Int? = nil, unreadOnly: Bool) throws -> [MessageEntity] {
		let userNum = user.num
		let detectionSensorPortNum: Int32 = 10
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.fromUser?.num == userNum
				&& $0.toUser != nil
				&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
				&& (!unreadOnly || $0.read == false)
			},
			sortBy: [
				SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse),
				SortDescriptor(\MessageEntity.messageId, order: .reverse)
			]
		)
		if let limit {
			descriptor.fetchLimit = limit
		}
		return try context.fetch(descriptor)
	}

	private func fetchOutgoingMessages(limit: Int? = nil, unreadOnly: Bool) throws -> [MessageEntity] {
		let userNum = user.num
		let detectionSensorPortNum: Int32 = 10
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.toUser?.num == userNum
				&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
				&& (!unreadOnly || $0.read == false)
			},
			sortBy: [
				SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse),
				SortDescriptor(\MessageEntity.messageId, order: .reverse)
			]
		)
		if let limit {
			descriptor.fetchLimit = limit
		}
		return try context.fetch(descriptor)
	}

	private func fetchLatestTapbackCursor() throws -> UserMessageTimelineCursor? {
		try [fetchLatestIncomingTapbackCursor(), fetchLatestOutgoingTapbackCursor()].compactMap { $0 }.max()
	}

	private func fetchLatestIncomingTapbackCursor() throws -> UserMessageTimelineCursor? {
		let userNum = user.num
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.fromUser?.num == userNum && $0.toUser != nil && $0.isEmoji == true && $0.replyID > 0
			},
			sortBy: [
				SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse),
				SortDescriptor(\MessageEntity.messageId, order: .reverse)
			]
		)
		descriptor.fetchLimit = 1
		return try context.fetch(descriptor).first.map(cursor(for:))
	}

	private func fetchLatestOutgoingTapbackCursor() throws -> UserMessageTimelineCursor? {
		let userNum = user.num
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.toUser?.num == userNum && $0.isEmoji == true && $0.replyID > 0
			},
			sortBy: [
				SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse),
				SortDescriptor(\MessageEntity.messageId, order: .reverse)
			]
		)
		descriptor.fetchLimit = 1
		return try context.fetch(descriptor).first.map(cursor(for:))
	}

	private func cursor(for message: MessageEntity) -> UserMessageTimelineCursor {
		UserMessageTimelineCursor(timestamp: message.messageTimestamp, messageId: message.messageId)
	}

	private func buildPreviousByID(for visibleMessages: [MessageEntity], previousMessage: MessageEntity?) -> [Int64: MessageEntity] {
		var result: [Int64: MessageEntity] = [:]
		var previous = previousMessage
		for message in visibleMessages {
			if let previous {
				result[message.messageId] = previous
			}
			previous = message
		}
		return result
	}

	private func fetchReplies(for visibleMessages: [MessageEntity]) throws -> [Int64: MessageEntity] {
		var result = Dictionary(uniqueKeysWithValues: visibleMessages.map { ($0.messageId, $0) })
		let missingReplyIDs = Array(Set(visibleMessages.map(\.replyID).filter { $0 > 0 && result[$0] == nil }))
		guard !missingReplyIDs.isEmpty else {
			return result
		}

		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { message in
				missingReplyIDs.contains(message.messageId)
			}
		)
		for reply in try context.fetch(descriptor) {
			result[reply.messageId] = reply
		}
		return result
	}

	private func fetchTapbacks(for visibleMessages: [MessageEntity]) throws -> [MessageEntity] {
		let visibleMessageIDs = visibleMessages.map(\.messageId)
		guard !visibleMessageIDs.isEmpty else {
			return []
		}

		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { message in
				message.isEmoji == true && visibleMessageIDs.contains(message.replyID)
			},
			sortBy: [SortDescriptor(\MessageEntity.messageTimestamp, order: .forward)]
		)
		return try context.fetch(descriptor)
	}

	@MainActor
	@discardableResult
	private func refreshVisibleTapbacks(markReadAfterLoad: Bool) -> Bool {
		do {
			let tapbacks = try fetchTapbacks(for: messages)
			let latestTapbackCursor = tapbacks.map(cursor(for:)).max()
			guard latestTapbackCursor != latestVisibleTapbackCursor || tapbacks.count != visibleTapbackCount else {
				return true
			}
			replaceTapbacks(tapbacks)
			if markReadAfterLoad {
				markMessagesAsRead()
			}
			return true
		} catch {
			Logger.data.error("Failed to refresh direct message tapbacks: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	@MainActor
	private func refreshIfNeeded() {
		do {
			if try fetchMessageChangeToken() != latestKnownMessageToken {
				loadMessages(markReadAfterLoad: routerIsShowingThisUser())
			} else {
				let latestTapbackCursor = try fetchLatestTapbackCursor()
				if latestTapbackCursor != latestKnownConversationTapbackCursor {
					if refreshVisibleTapbacks(markReadAfterLoad: routerIsShowingThisUser()) {
						latestKnownConversationTapbackCursor = latestTapbackCursor
					}
				}
			}
		} catch {
			Logger.data.error("Failed to refresh direct messages: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func replaceTapbacks(_ tapbacks: [MessageEntity]) {
		latestVisibleTapbackCursor = tapbacks.map(cursor(for:)).max()
		visibleTapbackCount = tapbacks.count
		tapbacksByReplyID = Dictionary(grouping: tapbacks, by: \.replyID)
	}

	private func routerIsShowingThisUser() -> Bool {
		guard appState.router.selectedTab == .messages else { return false }
		return scenePhase == .active
	}

	private func processTapback() {
		guard !tapbackText.isEmpty, let target = tapbackTargetMessage else { return }
		let emojiToSend = tapbackText
		let destination = MessageDestination.user(user)

		Task {
			do {
				try await accessoryManager.sendMessage(
					message: emojiToSend,
					toUserNum: destination.userNum,
					channel: destination.channelNum,
					isEmoji: true,
					replyID: target.messageId
				)
				await MainActor.run { _ = refreshVisibleTapbacks(markReadAfterLoad: routerIsShowingThisUser()) }
			} catch {
				Logger.services.warning("Failed to send tapback.")
			}
		}

		tapbackText = ""
		tapbackFocused = false
		tapbackTargetMessage = nil
	}

	var body: some View {
		VStack {
			ScrollViewReader { scrollView in
				ScrollView {
					LazyVStack {
						if hasEarlierMessages {
							Button {
								messageLimit += 100
								loadMessages(markReadAfterLoad: routerIsShowingThisUser())
							} label: {
								Label("Load Earlier Messages", systemImage: "arrow.up.circle")
									.font(.caption)
									.foregroundColor(.accentColor)
							}
							.buttonStyle(.borderless)
							.padding(.vertical, 8)
						}
						ForEach(messages, id: \.messageId) { message in
							UserMessageRow(
								message: message,
								replyMessage: repliesByID[message.replyID],
								tapbacks: tapbacksByReplyID[message.messageId] ?? [],
								previousMessage: previousByID[message.messageId],
								preferredPeripheralNum: preferredPeripheralNum,
								user: user,
								replyMessageId: $replyMessageId,
								messageFieldFocused: $messageFieldFocused,
								messageToHighlight: $messageToHighlight,
								scrollView: scrollView,
								onTapback: { message in
									tapbackFocused = false
									tapbackTargetMessage = message
									DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
										tapbackFocused = true
										#if targetEnvironment(macCatalyst)
										DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
											if let nsApp = NSClassFromString("NSApplication")?.value(forKeyPath: "sharedApplication") as? NSObject {
												let selector = NSSelectorFromString("orderFrontCharacterPalette:")
												if nsApp.responds(to: selector) {
													nsApp.perform(selector, with: nil)
												}
											}
										}
										#endif
									}
								}
							)

						}
						// Invisible spacer to detect reaching bottom
						Color.clear
							.frame(height: 1)
							.id("bottomAnchor")
					}
				}
				.defaultScrollAnchor(.bottom)
				.defaultScrollAnchorBottomSizeChanges()
				.scrollDismissesKeyboard(.immediately)
				.onAppear {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
						scrollView.scrollTo("bottomAnchor", anchor: .bottom)
					}
				}
				.task(id: "\(routerIsShowingThisUser())-\(user.num)") {
					let isVisible = routerIsShowingThisUser()
					loadMessages(markReadAfterLoad: isVisible)
					guard isVisible else { return }
					while !Task.isCancelled {
						try? await Task.sleep(for: .seconds(5))
						guard !Task.isCancelled else { return }
						refreshIfNeeded()
					}
				}
				.onChange(of: messages.last?.messageId) {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
						scrollView.scrollTo("bottomAnchor", anchor: .bottom)
					}
				}
				.onChange(of: messageFieldFocused) {
					if messageFieldFocused {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
							scrollView.scrollTo("bottomAnchor", anchor: .bottom)
						}
					}
				}
				.onChange(of: tapbackFocused) {
					if tapbackFocused, let target = tapbackTargetMessage {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
							withAnimation {
								scrollView.scrollTo(target.messageId, anchor: .center)
							}
						}
					}
				}
				.background {
					TextField("", text: $tapbackText)
						.keyboardType(.emoji)
						.focused($tapbackFocused)
						.frame(width: 1, height: 1)
						.opacity(0.01)
						.allowsHitTesting(false)
						.onChange(of: tapbackText) {
							processTapback()
						}
				}
			}
			TextMessageField(
				destination: .user(user),
				replyMessageId: $replyMessageId,
				isFocused: $messageFieldFocused,
				onMessageSent: { loadMessages(markReadAfterLoad: routerIsShowingThisUser()) }
			)
			.fixedSize(horizontal: false, vertical: true)
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			if !user.keyMatch {
				ToolbarItem(placement: .bottomBar) {
					VStack {
						HStack {
							Image(systemName: "key.slash.fill")
								.symbolRenderingMode(.multicolor)
								.foregroundStyle(.red)
								.font(.caption2)
							Text("There is an issue with this contact's public key.")
								.foregroundStyle(.secondary)
								.font(.caption2)
						}
						Link(destination: URL(string: "meshtastic:///nodes?nodenum=\(user.num)")!) {
							Text("Details...")
								.font(.caption2)
								.offset(y: -15)
						}
					}
					.offset(y: -15)
				}
			}
			ToolbarItem(placement: .principal) {
				HStack {
					CircleText(text: user.shortName ?? "?", color: Color(UIColor(hex: UInt32(user.num))), circleSize: 44)
					Text(user.longName ?? "Unknown").font(.headline)
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {
					ConnectedDevice(
						deviceConnected: accessoryManager.isConnected,
						name: accessoryManager.activeConnection?.device.shortName ?? "?")
				}
			}
		}
	}
}
