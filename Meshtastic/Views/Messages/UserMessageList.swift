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
	@State private var searchQuery = ""
	@State private var searchMatches: [MessageSearchMatch] = []
	@State private var currentMatchIndex = -1
	@State private var searchActor: MessageSearchActor?
	@State private var previousByID: [Int64: MessageEntity] = [:]
	@State private var repliesByID: [Int64: MessageEntity] = [:]
	@State private var tapbacksByReplyID: [Int64: [MessageEntity]] = [:]
	@State private var hasEarlierMessages = false
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
			// Refresh other unread surfaces (CarPlay templates) too. Only when something was
			// actually marked read: this view reloads on that notification, and an unconditional
			// post would have it marking read and reloading in a loop.
			if !readMessageIDs.isEmpty {
				NotificationCenter.default.post(name: .meshMessagesDidChange, object: nil)
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

			// The ForEach below keys on messageId. The store can transiently hold two
			// rows with the same messageId (a sent message and its mesh echo, racing
			// across contexts before the unique constraint merges them) — duplicate
			// ForEach ids corrupt the List's collection-view diff and crash. Keep the
			// first occurrence; the merge collapses the rows moments later.
			let visibleMessages = MessageEntity.deduplicatedByMessageId(
				Array(fetchedMessages.prefix(messageLimit).reversed())
			)
			let previousMessage = hasEarlierMessages ? fetchedMessages[messageLimit] : nil

			messages = visibleMessages
			previousByID = buildPreviousByID(for: visibleMessages, previousMessage: previousMessage)
			repliesByID = try fetchReplies(for: visibleMessages)
			replaceTapbacks(try fetchTapbacks(for: visibleMessages))

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



	private func replaceTapbacks(_ tapbacks: [MessageEntity]) {
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
				await MainActor.run { loadMessages(markReadAfterLoad: routerIsShowingThisUser()) }
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
			if !searchQuery.isEmpty { searchBar }
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
					// Reloads are driven by .meshMessagesDidChange below. This is only a safety
					// net for a change that somehow saved without one.
					while !Task.isCancelled {
						try? await Task.sleep(for: .seconds(30))
						guard !Task.isCancelled else { return }
						loadMessages(markReadAfterLoad: routerIsShowingThisUser())
					}
				}
				.onChange(of: messages.last?.messageId) {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
						scrollView.scrollTo("bottomAnchor", anchor: .bottom)
					}
				}
				// Message writes happen on the packet actor's own context, which SwiftData does
				// not propagate here, so the list reloads on the notification that actor posts
				// after a save. Debounced because a burst of packets saves several times.
				.onReceive(
					NotificationCenter.default.publisher(for: .meshMessagesDidChange)
						.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
				) { _ in
					loadMessages(markReadAfterLoad: routerIsShowingThisUser())
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
		.searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find in conversation")
		.autocorrectionDisabled()
		.task(id: searchQuery) { await debouncedSearch() }
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

// MARK: - Find in conversation
// Kept in an extension so the search/navigation helpers don't inflate the primary
// struct body (SwiftLint type_body_length).
private extension UserMessageList {
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
			let matches = try await actor.directMatches(userNum: user.num, query: query)
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
			Logger.data.error("Failed to search direct messages: \(error.localizedDescription, privacy: .public)")
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
			let needed = try MessageSearch.directNewerCount(in: context, userNum: user.num, than: match) + 1
			if needed > messageLimit {
				messageLimit = ((needed / 100) + 1) * 100
			}
			// The match isn't in the current window; reload so it's present to scroll to,
			// whether or not the window needed expanding.
			loadMessages(markReadAfterLoad: false)
		} catch {
			Logger.data.error("Failed to expand direct-message window for search: \(error.localizedDescription, privacy: .public)")
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
