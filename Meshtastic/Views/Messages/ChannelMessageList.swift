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
	// Tallies of messages whose ACK has resolved, kept as separate delivered/errored counts
	// rather than a single sum: an errored→delivered transition leaves the sum unchanged
	// (delivered +1, errored −1) but moves both tallies, so the token still changes and the list
	// reloads. Together with `latest`/`count` these cover every ACK transition the app produces:
	// in-place mutations only ever move a message *into* delivered/errored (a tally changes), and
	// the sole route back to "waiting" is RetryButton, which deletes the message and inserts a
	// fresh one — moving `latest`/`count`. (There is deliberately no `max(ackTimestamp)` signal:
	// `ackTimestamp` is stamped from the remote `packet.rxTime`, so it isn't reliably monotonic
	// and would add an unindexed sort to the 5s poll for a net-zero case that can't occur.) An
	// incoming ACK changes neither `latest` nor `count`, so without these tallies the poll-based
	// refresh would never reload and the row would stay on "Waiting to be acknowledged" until the
	// view is rebuilt.
	let deliveredAckCount: Int
	let erroredAckCount: Int
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
	@State private var searchQuery = ""
	@State private var searchMatches: [MessageSearchMatch] = []
	@State private var currentMatchIndex = -1
	@State private var searchActor: MessageSearchActor?
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
		let acks = try Self.resolvedAckCounts(in: context, channelIndex: channel.index)
		return ChannelMessageListChangeToken(
			latest: latest.map(cursor(for:)),
			count: try fetchMessageCount(),
			deliveredAckCount: acks.delivered,
			erroredAckCount: acks.errored
		)
	}

	/// Resolved-ACK tallies for this channel: delivered (`receivedACK`) and failed
	/// (`ackError != 0`) counted separately. A message is shown as "Waiting to be acknowledged"
	/// until it resolves; folding both tallies into the change token makes the poll reload on any
	/// ACK state change. Keeping them distinct means errored→delivered (which keeps the sum
	/// constant) still moves a tally. Exposed `static` so the regression tests exercise these
	/// exact predicates.
	///
	/// Two single-term `fetchCount`s rather than one `||` predicate: a compound `||` (and a fourth
	/// `&&` term such as an `isEmoji` filter) exceeds the `#Predicate` macro's type-check budget.
	/// Not filtering `isEmoji` only means an acked tapback triggers one extra benign reload.
	static func resolvedAckCounts(in context: ModelContext, channelIndex: Int32) throws -> (delivered: Int, errored: Int) {
		let deliveredDescriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.channel == channelIndex && $0.toUser == nil && $0.receivedACK
			}
		)
		let erroredDescriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.channel == channelIndex && $0.toUser == nil && $0.ackError != 0
			}
		)
		return (try context.fetchCount(deliveredDescriptor), try context.fetchCount(erroredDescriptor))
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
		VStack(spacing: 0) {
		if !searchQuery.isEmpty { searchBar }
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
							  },
							  onMessageRetried: {
								  loadMessages(markReadAfterLoad: routerIsShowingThisChannel())
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
			.onChange(of: messageToHighlight) { scrollToHighlighted(scrollView) }
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
		}
		.navigationBarTitleDisplayMode(.inline)
		.searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find in conversation")
		.autocorrectionDisabled()
		.task(id: searchQuery) { await debouncedSearch() }
		.toolbar {
			ToolbarItem(placement: .principal) {
				HStack {
					CircleText(text: String(channel.index), color: .accentColor, circleSize: 44).fixedSize()
					Text(String(channel.name ?? "Unknown")).font(.headline)
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
						mqttTopic: {
								let name = channel.name ?? ""
								if name.isEmpty {
									return accessoryManager.mqttManager.topics.first ?? ""
								}
								return accessoryManager.mqttManager.topics.first(where: { $0.contains("/2/e/\(name)/") }) ?? accessoryManager.mqttManager.topics.first ?? ""
							}()
					)
				}
			}
		}
	}
}

// MARK: - Find in conversation
// Kept in an extension so the search/navigation helpers don't inflate the primary
// struct body (SwiftLint type_body_length).
private extension ChannelMessageList {
	@ViewBuilder var searchBar: some View {
		MessageSearchBar(
			matchCount: searchMatches.count,
			currentIndex: currentMatchIndex,
			onPrevious: goToPreviousMatch,
			onNext: goToNextMatch
		)
	}

	/// Centers the currently-highlighted message once the list has had a moment to render
	/// any newly-loaded rows (e.g. after the search window expanded).
	func scrollToHighlighted(_ proxy: ScrollViewProxy) {
		guard messageToHighlight > 0 else { return }
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
			withAnimation { proxy.scrollTo(messageToHighlight, anchor: .center) }
		}
	}

	/// Debounces search so a full-store scan doesn't run on every keystroke. Cancelled and
	/// restarted by `.task(id: searchQuery)` whenever the query changes.
	@MainActor
	func debouncedSearch() async {
		// Clearing the field should empty the results immediately, not after the debounce.
		guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			await runSearch()
			return
		}
		try? await Task.sleep(for: .milliseconds(250))
		guard !Task.isCancelled else { return }
		await runSearch()
	}

	@MainActor
	func runSearch() async {
		let query = searchQuery
		guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			searchMatches = []
			currentMatchIndex = -1
			messageToHighlight = -1
			return
		}
		let actor = searchActor ?? MessageSearchActor(modelContainer: context.container)
		searchActor = actor
		do {
			let matches = try await actor.channelMatches(channelIndex: channel.index, query: query)
			// Drop stale results if the query moved on while the background fetch ran.
			guard query == searchQuery else { return }
			searchMatches = matches
			if matches.isEmpty {
				currentMatchIndex = -1
				messageToHighlight = -1
			} else {
				// Focus the most recent match first.
				focusMatch(at: matches.count - 1)
			}
		} catch {
			Logger.data.error("Failed to search channel messages: \(error.localizedDescription, privacy: .public)")
		}
	}

	@MainActor
	func focusMatch(at index: Int) {
		guard searchMatches.indices.contains(index) else { return }
		currentMatchIndex = index
		let match = searchMatches[index]
		ensureLoaded(match: match)
		withAnimation { messageToHighlight = match.messageId }
	}

	/// Expand the (newest-first) window until the match is loaded, so it can be scrolled to.
	@MainActor
	func ensureLoaded(match: MessageSearchMatch) {
		if messages.contains(where: { $0.messageId == match.messageId }) { return }
		do {
			let needed = try MessageSearch.channelNewerCount(in: context, channelIndex: channel.index, than: match) + 1
			if needed > messageLimit {
				messageLimit = ((needed / 100) + 1) * 100
			}
			// The match isn't in the current window; reload so it's present to scroll to,
			// whether or not the window needed expanding.
			loadMessages(markReadAfterLoad: false)
		} catch {
			Logger.data.error("Failed to expand channel window for search: \(error.localizedDescription, privacy: .public)")
		}
	}

	func goToNextMatch() {
		guard !searchMatches.isEmpty else { return }
		focusMatch(at: currentMatchIndex + 1 >= searchMatches.count ? 0 : currentMatchIndex + 1)
	}

	func goToPreviousMatch() {
		guard !searchMatches.isEmpty else { return }
		focusMatch(at: currentMatchIndex - 1 < 0 ? searchMatches.count - 1 : currentMatchIndex - 1)
	}
}
