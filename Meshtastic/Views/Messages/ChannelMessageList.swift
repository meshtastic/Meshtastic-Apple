//
//  ChannelMessageList.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/24/21.
//

@preconcurrency import SwiftData
import MeshtasticProtobufs
import OSLog
import SwiftUI

private struct ChannelMessageTimelineCursor: Comparable {
	let timestamp: Int32
	let messageId: Int64

	static func < (lhs: ChannelMessageTimelineCursor, rhs: ChannelMessageTimelineCursor) -> Bool {
		if lhs.timestamp == rhs.timestamp {
			return lhs.messageId < rhs.messageId
		}
		return lhs.timestamp < rhs.timestamp
	}
}

private struct ChannelMessageListChangeToken: Equatable {
	let latest: ChannelMessageTimelineCursor?
	let count: Int
}

struct ChannelMessageList: View {
	@EnvironmentObject var appState: AppState
	@Environment(\.scenePhase) var scenePhase
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@FocusState var messageFieldFocused: Bool
	@Bindable var myInfo: MyInfoEntity
	@Bindable var channel: ChannelEntity
	@State private var replyMessageId: Int64 = 0
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
	@State private var messageToHighlight: Int64 = 0
	@State private var messageLimit: Int = 100
	@State private var messages: [MessageEntity] = []
	@State private var previousByID: [Int64: MessageEntity] = [:]
	@State private var repliesByID: [Int64: MessageEntity] = [:]
	@State private var tapbacksByReplyID: [Int64: [MessageEntity]] = [:]
	@State private var hasEarlierMessages = false
	@State private var latestKnownMessageToken: ChannelMessageListChangeToken?
	@State private var latestVisibleTapbackCursor: ChannelMessageTimelineCursor?
	@State private var latestKnownChannelTapbackCursor: ChannelMessageTimelineCursor?
	@State private var visibleTapbackCount = 0
	@State private var tapbackTargetMessage: MessageEntity?
	@State private var tapbackText = ""
	@FocusState var tapbackFocused: Bool

	init(myInfo: MyInfoEntity, channel: ChannelEntity) {
		self.myInfo = myInfo
		self.channel = channel
	}

	func markMessagesAsRead() {
		do {
			let channelIndex = channel.index
			let descriptor = FetchDescriptor<MessageEntity>(
				predicate: #Predicate<MessageEntity> {
					$0.channel == channelIndex && $0.toUser == nil && $0.isEmoji == false && $0.read == false
				}
			)
			let unreadMessages = try context.fetch(descriptor)
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
			Logger.data.info("📖 [App] All unread messages marked as read.")
			appState.unreadChannelMessages = myInfo.unreadMessages
		} catch {
			Logger.data.error("Failed to read messages: \(error.localizedDescription, privacy: .public)")
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
			latestKnownChannelTapbackCursor = try fetchLatestTapbackCursor()

			if markReadAfterLoad {
				markMessagesAsRead()
			}
		} catch {
			Logger.data.error("Failed to fetch channel messages: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func fetchMessages(limit: Int) throws -> [MessageEntity] {
		let channelIndex = channel.index
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.channel == channelIndex && $0.toUser == nil && $0.isEmoji == false
			},
			sortBy: [
				SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse),
				SortDescriptor(\MessageEntity.messageId, order: .reverse)
			]
		)
		descriptor.fetchLimit = limit
		return try context.fetch(descriptor)
	}

	private func fetchMessageChangeToken(latestMessage: MessageEntity? = nil) throws -> ChannelMessageListChangeToken {
		let latest = try latestMessage ?? fetchMessages(limit: 1).first
		return ChannelMessageListChangeToken(
			latest: latest.map(cursor(for:)),
			count: try fetchMessageCount()
		)
	}

	private func fetchMessageCount() throws -> Int {
		let channelIndex = channel.index
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.channel == channelIndex && $0.toUser == nil && $0.isEmoji == false
			}
		)
		return try context.fetchCount(descriptor)
	}

	private func fetchLatestTapbackCursor() throws -> ChannelMessageTimelineCursor? {
		let channelIndex = channel.index
		let isEmoji = true
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { message in
				message.channel == channelIndex && message.toUser == nil && message.isEmoji == isEmoji && message.replyID > 0
			},
			sortBy: [
				SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse),
				SortDescriptor(\MessageEntity.messageId, order: .reverse)
			]
		)
		descriptor.fetchLimit = 1
		let fetched: [MessageEntity] = try context.fetch(descriptor)
		return fetched.first.map(cursor(for:))
	}

	private func cursor(for message: MessageEntity) -> ChannelMessageTimelineCursor {
		ChannelMessageTimelineCursor(timestamp: message.messageTimestamp, messageId: message.messageId)
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

		let channelIndex = channel.index
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { message in
				message.channel == channelIndex
				&& message.isEmoji == true
				&& visibleMessageIDs.contains(message.replyID)
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
			Logger.data.error("Failed to refresh channel message tapbacks: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	@MainActor
	private func refreshIfNeeded() {
		do {
			if try fetchMessageChangeToken() != latestKnownMessageToken {
				loadMessages(markReadAfterLoad: routerIsShowingThisChannel())
			} else {
				let latestTapbackCursor = try fetchLatestTapbackCursor()
				if latestTapbackCursor != latestKnownChannelTapbackCursor {
					if refreshVisibleTapbacks(markReadAfterLoad: routerIsShowingThisChannel()) {
						latestKnownChannelTapbackCursor = latestTapbackCursor
					}
				}
			}
		} catch {
			Logger.data.error("Failed to refresh channel messages: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func replaceTapbacks(_ tapbacks: [MessageEntity]) {
		latestVisibleTapbackCursor = tapbacks.map(cursor(for:)).max()
		visibleTapbackCount = tapbacks.count
		tapbacksByReplyID = Dictionary(grouping: tapbacks, by: \.replyID)
	}

	private func routerIsShowingThisChannel() -> Bool {
		guard appState.router.selectedTab == .messages else { return false }
		return scenePhase == .active
	}

	private func processTapback() {
		guard !tapbackText.isEmpty, let target = tapbackTargetMessage else { return }
		let emojiToSend = tapbackText
		let destination = MessageDestination.channel(channel)

		Task {
			do {
				try await accessoryManager.sendMessage(
					message: emojiToSend,
					toUserNum: destination.userNum,
					channel: destination.channelNum,
					isEmoji: true,
					replyID: target.messageId
				)
				await MainActor.run { _ = refreshVisibleTapbacks(markReadAfterLoad: routerIsShowingThisChannel()) }
			} catch {
				Logger.services.warning("Failed to send tapback.")
			}
		}

		tapbackText = ""
		tapbackFocused = false
		tapbackTargetMessage = nil
	}

	var body: some View {
		ScrollViewReader { scrollView in
			ScrollView {
				LazyVStack {
						if hasEarlierMessages {
							Button {
								messageLimit += 100
								loadMessages(markReadAfterLoad: routerIsShowingThisChannel())
							} label: {
							Label("Load Earlier Messages", systemImage: "arrow.up.circle")
								.font(.caption)
								.foregroundColor(.accentColor)
						}
						.buttonStyle(.borderless)
						.padding(.vertical, 8)
					}
					ForEach(messages, id: \.messageId) { message in
						  ChannelMessageRow(
							  message: message,
							  replyMessage: repliesByID[message.replyID],
							  tapbacks: tapbacksByReplyID[message.messageId] ?? [],
							  previousMessage: previousByID[message.messageId],
							  preferredPeripheralNum: preferredPeripheralNum,
							  channel: channel,
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
				.task(id: "\(routerIsShowingThisChannel())-\(channel.index)") {
					let isVisible = routerIsShowingThisChannel()
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
			// Incoming channel traffic bumps appState.unreadChannelMessages (set in
			// textMessageAppPacket); refresh on that signal so messages land live instead
			// of waiting up to 5s for the poll loop in .task above.
			.onChange(of: appState.unreadChannelMessages) {
				refreshIfNeeded()
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
			TextMessageField(
				destination: .channel(channel),
				replyMessageId: $replyMessageId,
				isFocused: $messageFieldFocused,
				onMessageSent: { loadMessages(markReadAfterLoad: routerIsShowingThisChannel()) }
			)
			.fixedSize(horizontal: false, vertical: true)
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				HStack {
					CircleText(text: String(channel.index), color: .accentColor, circleSize: 44).fixedSize()
					Text(String(channel.name ?? "Unknown").camelCaseToWords()).font(.headline)
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {
					ConnectedDevice(
						deviceConnected: accessoryManager.isConnected,
						name: accessoryManager.activeConnection?.device.shortName ?? "?",
						mqttProxyConnected: accessoryManager.mqttProxyConnected && (channel.uplinkEnabled || channel.downlinkEnabled),
						mqttUplinkEnabled: channel.uplinkEnabled,
						mqttDownlinkEnabled: channel.downlinkEnabled,
						mqttTopic: accessoryManager.mqttManager.topic
					)
				}
			}
		}
	}
}
