//
//  CarPlaySceneDelegate.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/16/26.
//
//  CarPlay Communication app scene delegate.
//  Uses a tab bar with Channels and Direct Messages tabs,
//  matching the main app's Messages navigation structure.
//

#if os(iOS) && canImport(CarPlay)
import CarPlay
import Combine
import Intents
import OSLog
import SwiftData
#if canImport(ActivityKit)
import ActivityKit
#endif

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate {

	var interfaceController: CPInterfaceController?
	private var cancellables = Set<AnyCancellable>()
	// Retained template references so we can call updateSections rather than replacing the whole tree.
	private var channelsTemplate: CPListTemplate?
	private var directMessagesTemplate: CPListTemplate?
	// Tracks which conversation identifiers have already had a contact intent donated
	// during this CarPlay session so we don't re-donate on every refresh.
	private var donatedConversationIds = Set<String>()

	private lazy var context: ModelContext = PersistenceController.shared.context

	/// Returns a human-readable "last heard" string.
	/// `now` is passed in so all rows in a single render share one `Date()` allocation.
	private func lastHeardText(_ date: Date?, now: Date) -> String {
		guard let date else { return "Never heard" }
		let interval = now.timeIntervalSince(date)
		if interval < 60 { return "Just now" }
		if interval < 3600 { return "\(Int(interval / 60))m ago" }
		if interval < 86400 { return "\(Int(interval / 3600))h ago" }
		return "\(Int(interval / 86400))d ago"
	}

	// MARK: - CPTemplateApplicationSceneDelegate

	func templateApplicationScene(
		_ templateApplicationScene: CPTemplateApplicationScene,
		didConnect interfaceController: CPInterfaceController
	) {
		Logger.services.info("🚗 [CarPlay] Connected")
		self.interfaceController = interfaceController
		interfaceController.delegate = self

		buildAndSetRootTemplate(animated: false)
		donateUnreadMessages()

		// Observe connection state changes and refresh sections (not the whole template tree).
		// Debounce absorbs reconnect spikes that would otherwise fire multiple expensive refreshes.
		AccessoryManager.shared.$isConnected
			.removeDuplicates()
			.dropFirst() // Skip initial value — we already built sections above
			.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
			.sink { [weak self] isConnected in
				self?.refreshSections()
				if isConnected {
					self?.donateUnreadMessages()
					self?.startLiveActivityIfNeeded()
				}
			}
			.store(in: &cancellables)

		// Start Live Activity immediately if already connected
		if AccessoryManager.shared.isConnected {
			startLiveActivityIfNeeded()
		}
	}

	func templateApplicationScene(
		_ templateApplicationScene: CPTemplateApplicationScene,
		didDisconnectInterfaceController interfaceController: CPInterfaceController
	) {
		Logger.services.info("🚗 [CarPlay] Disconnected")
		endLiveActivity()
		cancellables.removeAll()
		donatedConversationIds.removeAll()
		channelsTemplate = nil
		directMessagesTemplate = nil
		self.interfaceController = nil
	}

	// MARK: - CPInterfaceControllerDelegate

	func templateWillAppear(_ aTemplate: CPTemplate, animated: Bool) {}
	func templateDidAppear(_ aTemplate: CPTemplate, animated: Bool) {}
	func templateWillDisappear(_ aTemplate: CPTemplate, animated: Bool) {}
	func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {}

	// MARK: - Root Template

	/// Called once at connection time.  Builds and caches the two `CPListTemplate` tabs.
	private func buildAndSetRootTemplate(animated: Bool) {
		let connected = AccessoryManager.shared.isConnected

		let chTemplate = CPListTemplate(title: "Channels", sections: buildChannelSections(connected: connected))
		chTemplate.tabImage = UIImage(systemName: "bubble.left.and.bubble.right")
		channelsTemplate = chTemplate

		let dmTemplate = CPListTemplate(title: "Direct Messages", sections: buildDirectMessageSections(connected: connected))
		dmTemplate.tabImage = UIImage(systemName: "bubble.left.and.text.bubble.right")
		directMessagesTemplate = dmTemplate

		let tabBar = CPTabBarTemplate(templates: [chTemplate, dmTemplate])
		interfaceController?.setRootTemplate(tabBar, animated: animated, completion: nil)
	}

	/// Called on subsequent connection-state changes — updates sections in-place
	/// instead of tearing down and rebuilding the entire template hierarchy.
	private func refreshSections() {
		let connected = AccessoryManager.shared.isConnected
		channelsTemplate?.updateSections(buildChannelSections(connected: connected))
		directMessagesTemplate?.updateSections(buildDirectMessageSections(connected: connected))
	}

	// MARK: - Section Builders

	private func buildChannelSections(connected: Bool) -> [CPListSection] {
		guard connected else {
			let statusItem = CPListItem(
				text: "Not Connected",
				detailText: "Open Meshtastic to connect",
				image: UIImage(systemName: "antenna.radiowaves.left.and.right.slash")
			)
			statusItem.isEnabled = false
			return [CPListSection(items: [statusItem])]
		}

		let channelItems = fetchChannelItems()
		if channelItems.isEmpty {
			let emptyItem = CPListItem(text: "No Channels", detailText: nil)
			emptyItem.isEnabled = false
			return [CPListSection(items: [emptyItem])]
		}
		return [CPListSection(items: channelItems)]
	}

	private func buildDirectMessageSections(connected: Bool) -> [CPListSection] {
		guard connected else {
			let statusItem = CPListItem(
				text: "Not Connected",
				detailText: "Open Meshtastic to connect",
				image: UIImage(systemName: "antenna.radiowaves.left.and.right.slash")
			)
			statusItem.isEnabled = false
			return [CPListSection(items: [statusItem])]
		}

		var sections = [CPListSection]()

		let favoriteItems = fetchFavoriteContactItems()
		if !favoriteItems.isEmpty {
			sections.append(CPListSection(items: favoriteItems, header: "Favorites", sectionIndexTitle: nil))
		}

		let dmItems = fetchDirectMessageItems()
		if !dmItems.isEmpty {
			sections.append(CPListSection(items: dmItems, header: "Recent", sectionIndexTitle: nil))
		}

		if favoriteItems.isEmpty && dmItems.isEmpty {
			let emptyItem = CPListItem(text: "No Messages", detailText: "No direct message history")
			emptyItem.isEnabled = false
			sections.append(CPListSection(items: [emptyItem]))
		}

		return sections
	}

	// MARK: - Data Fetching

	private func fetchFavoriteContactItems() -> [CPMessageListItem] {
		do {
			let descriptor = FetchDescriptor<NodeInfoEntity>(
				sortBy: [SortDescriptor(\.lastHeard, order: .reverse)]
			)
			let activeNum = AccessoryManager.shared.activeDeviceNum ?? 0
			let nodes = try context.fetch(descriptor).filter { $0.favorite && $0.num != activeNum }
			let nodeNums = nodes.compactMap { $0.user != nil ? $0.num : nil as Int64? }
			let unreadCounts = fetchUnreadCountsForDMs(nodeNums: nodeNums)
			let now = Date()

			return nodes.compactMap { node -> CPMessageListItem? in
				guard let user = node.user else { return nil }
				let name = user.longName ?? user.shortName ?? "Unknown"
				let unreadCount = unreadCounts[node.num] ?? 0
				let hasUnread = unreadCount > 0
				let convId = "dm-\(node.num)"

				let leadingConfig = CPMessageListItemLeadingConfiguration(
					leadingItem: .star,
					leadingImage: UIImage(systemName: "person.circle.fill"),
					unread: hasUnread
				)

				let item = CPMessageListItem(
					fullName: name,
					phoneOrEmailAddress: "\(node.num)@meshtastic.local",
					leadingConfiguration: leadingConfig,
					trailingConfiguration: nil,
					detailText: hasUnread ? "\(unreadCount) unread" : nil,
					trailingText: lastHeardText(node.lastHeard, now: now)
				)
				item.conversationIdentifier = convId
				item.userInfo = node.num

				donateMessageIntentIfNeeded(conversationId: convId, toNodeNum: node.num, name: name)

				return item
			}
		} catch {
			Logger.services.error("🚗 [CarPlay] Failed to fetch favorites: \(error.localizedDescription, privacy: .public)")
			return []
		}
	}

	private func fetchChannelItems() -> [CPMessageListItem] {
		guard let connectedNum = AccessoryManager.shared.activeDeviceNum,
			  let connectedNode = getNodeInfo(id: connectedNum, context: context),
			  let myInfo = connectedNode.myInfo else {
			return []
		}

		let activeChannels = myInfo.channels
			.filter { $0.role > 0 }
			.sorted { $0.index < $1.index }
		let channelIndices = activeChannels.map { $0.index }
		let unreadCounts = fetchUnreadCountsForChannels(channelIndices: channelIndices)

		return activeChannels.compactMap { channel -> CPMessageListItem? in
			let name = (channel.name?.isEmpty ?? true)
				? (channel.index == 0 ? "Primary Channel" : "Channel \(channel.index)")
				: channel.name!
			let channelIndex = Int(channel.index)
			let unreadCount = unreadCounts[channel.index] ?? 0
			let hasUnread = unreadCount > 0
			let convId = "channel-\(channelIndex)"

			let leadingConfig = CPMessageListItemLeadingConfiguration(
				leadingItem: .none,
				leadingImage: UIImage(systemName: channel.index == 0 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right"),
				unread: hasUnread
			)

			let item = CPMessageListItem(
				conversationIdentifier: convId,
				text: name,
				leadingConfiguration: leadingConfig,
				trailingConfiguration: nil,
				detailText: hasUnread ? "\(unreadCount) unread" : (channel.index == 0 ? "Primary" : "Ch \(channel.index)"),
				trailingText: nil
			)
			item.phoneOrEmailAddress = "\(convId)@meshtastic.local"
			item.userInfo = channelIndex

			donateChannelIntentIfNeeded(conversationId: convId, channelIndex: channelIndex, channelName: name)

			return item
		}
	}

	private func fetchDirectMessageItems() -> [CPMessageListItem] {
		do {
			let users = try context.fetch(FetchDescriptor<UserEntity>())
			let connectedNum = AccessoryManager.shared.activeDeviceNum ?? 0
			let filteredUsers = users
				.filter { user in
					guard let node = user.userNode else { return false }
					let notSelf = node.num != connectedNum
					let notIgnored = !node.ignored
					let notFavorite = !node.favorite
					let hasMessagesOrMessagable = !user.unmessagable || user.lastMessage != nil
					return notSelf && notIgnored && notFavorite && hasMessagesOrMessagable
				}
				.sorted { lhs, rhs in
					let lhsHeard = lhs.userNode?.lastHeard ?? .distantPast
					let rhsHeard = rhs.userNode?.lastHeard ?? .distantPast
					if lhsHeard != rhsHeard {
						return lhsHeard > rhsHeard
					}
					let lhsLastMessage = lhs.lastMessage ?? .distantPast
					let rhsLastMessage = rhs.lastMessage ?? .distantPast
					if lhsLastMessage != rhsLastMessage {
						return lhsLastMessage > rhsLastMessage
					}
					return (lhs.longName ?? lhs.shortName ?? "") < (rhs.longName ?? rhs.shortName ?? "")
				}
				.prefix(24)
			let nodeNums = users.compactMap { $0.userNode?.num }
			let unreadCounts = fetchUnreadCountsForDMs(nodeNums: nodeNums)
			let now = Date()

			return filteredUsers.compactMap { user -> CPMessageListItem? in
				guard let node = user.userNode else { return nil }
				let name = user.longName ?? user.shortName ?? "Unknown"
				let nodeNum = node.num
				let unreadCount = unreadCounts[nodeNum] ?? 0
				let hasUnread = unreadCount > 0
				let convId = "dm-\(nodeNum)"

				let leadingConfig = CPMessageListItemLeadingConfiguration(
					leadingItem: .none,
					leadingImage: UIImage(systemName: "person.circle.fill"),
					unread: hasUnread
				)

				let item = CPMessageListItem(
					fullName: name,
					phoneOrEmailAddress: "\(nodeNum)@meshtastic.local",
					leadingConfiguration: leadingConfig,
					trailingConfiguration: nil,
					detailText: hasUnread ? "\(unreadCount) unread" : nil,
					trailingText: lastHeardText(node.lastHeard, now: now)
				)
				item.conversationIdentifier = convId
				item.userInfo = nodeNum

				donateMessageIntentIfNeeded(conversationId: convId, toNodeNum: nodeNum, name: name)

				return item
			}
		} catch {
			Logger.services.error("🚗 [CarPlay] Failed to fetch DM users: \(error.localizedDescription, privacy: .public)")
			return []
		}
	}

	// MARK: - Unread Count Batch Fetching

	/// Fetches unread message counts for multiple DM node numbers in a single query,
	/// then groups the results in-memory. This avoids the N+1 count-per-row pattern
	/// while staying compatible with Core Data's relationship keypath restrictions.
	private func fetchUnreadCountsForDMs(nodeNums: [Int64]) -> [Int64: Int] {
		guard !nodeNums.isEmpty else { return [:] }
		let nodeNumSet = Set(nodeNums)

		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate { message in
				message.read == false
			}
		)
		let results = (try? context.fetch(descriptor)) ?? []
		var counts = [Int64: Int]()
		for message in results {
			if let num = message.fromUser?.num, nodeNumSet.contains(num) {
				counts[num, default: 0] += 1
			}
		}
		return counts
	}

	/// Fetches unread message counts for multiple channel indices in a single query,
	/// then groups the results in-memory.
	private func fetchUnreadCountsForChannels(channelIndices: [Int32]) -> [Int32: Int] {
		guard !channelIndices.isEmpty else { return [:] }
		let channelSet = Set(channelIndices)

		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate { message in
				message.read == false && message.toUser == nil
			}
		)
		let results = (try? context.fetch(descriptor)) ?? []
		var counts = [Int32: Int]()
		for message in results {
			if channelSet.contains(message.channel) {
				counts[message.channel, default: 0] += 1
			}
		}
		return counts
	}

	// MARK: - Intent Donation

	/// Donates a contact intent for a DM conversation the first time it is seen this session.
	/// Subsequent renders are no-ops, avoiding repeated IPC calls to the intents daemon.
	private func donateMessageIntentIfNeeded(conversationId: String, toNodeNum: Int64, name: String) {
		guard donatedConversationIds.insert(conversationId).inserted else { return }

		let handleValue = "\(toNodeNum)@meshtastic.local"
		let person = INPerson(
			personHandle: INPersonHandle(value: handleValue, type: .emailAddress),
			nameComponents: nil,
			displayName: name,
			image: nil,
			contactIdentifier: "\(toNodeNum)",
			customIdentifier: "\(toNodeNum)"
		)
		let intent = INSendMessageIntent(
			recipients: [person],
			outgoingMessageType: .outgoingMessageText,
			content: nil,
			speakableGroupName: nil,
			conversationIdentifier: conversationId,
			serviceName: "Meshtastic",
			sender: nil,
			attachments: nil
		)
		let interaction = INInteraction(intent: intent, response: nil)
		interaction.direction = .outgoing
		interaction.donate { error in
			if let error {
				Logger.services.error("🚗 [CarPlay] DM intent donation error: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// Donates a contact intent for a channel conversation the first time it is seen this session.
	private func donateChannelIntentIfNeeded(conversationId: String, channelIndex: Int, channelName: String) {
		guard donatedConversationIds.insert(conversationId).inserted else { return }

		let channelHandle = "channel-\(channelIndex)@meshtastic.local"
		let recipient = INPerson(
			personHandle: INPersonHandle(value: channelHandle, type: .emailAddress),
			nameComponents: nil,
			displayName: channelName,
			image: nil,
			contactIdentifier: channelHandle,
			customIdentifier: channelHandle
		)
		let groupName = INSpeakableString(spokenPhrase: channelName)
		let intent = INSendMessageIntent(
			recipients: [recipient],
			outgoingMessageType: .outgoingMessageText,
			content: nil,
			speakableGroupName: groupName,
			conversationIdentifier: conversationId,
			serviceName: "Meshtastic",
			sender: nil,
			attachments: nil
		)
		let interaction = INInteraction(intent: intent, response: nil)
		interaction.direction = .outgoing
		interaction.donate { error in
			if let error {
				Logger.services.error("🚗 [CarPlay] Channel intent donation error: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	// MARK: - Unread Message Donation

	/// Donate all unread messages as incoming Siri intents so that tapping a
	/// conversation in CarPlay triggers Siri to read them aloud — even for
	/// messages that arrived before the CarPlay session started.
	private func donateUnreadMessages() {
		Task { @MainActor in
			let context = PersistenceController.shared.context
			var descriptor = FetchDescriptor<MessageEntity>(
				predicate: #Predicate<MessageEntity> { message in
					message.read == false && message.admin == false && message.isEmoji == false
				},
				sortBy: [SortDescriptor(\.messageTimestamp, order: .reverse)]
			)
			descriptor.fetchLimit = 50

			guard let messages = try? context.fetch(descriptor) else { return }
			for message in messages {
				CarPlayIntentDonation.donateReceivedMessage(message)
			}
			if !messages.isEmpty {
				Logger.services.info("🚗 [CarPlay] Donated \(messages.count) unread message(s) for Siri read-back")
			}
		}
	}

	// MARK: - Live Activity

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
	private func startLiveActivityIfNeeded() {
		guard ActivityAuthorizationInfo().areActivitiesEnabled else {
			Logger.services.info("🚗 [CarPlay] Live Activities not enabled")
			return
		}

		// Don't start another if one is already running
		guard Activity<MeshActivityAttributes>.activities.isEmpty else {
			Logger.services.info("🚗 [CarPlay] Live Activity already active")
			return
		}

		guard let connectedNum = AccessoryManager.shared.activeDeviceNum else { return }
		let connectedNode = getNodeInfo(id: connectedNum, context: context)
		let nodeName = connectedNode?.user?.longName ?? "Meshtastic"
		let nodeShortName = connectedNode?.user?.shortName ?? "?"

		// Fetch latest local stats telemetry
		let localStats = connectedNode?.telemetries.filter { $0.metricsType == 4 }
		let mostRecent = localStats?.last

		let timerSeconds = 900 // 15 minute local stats interval
		let future = Date(timeIntervalSinceNow: Double(timerSeconds))
		let initialState = MeshActivityAttributes.ContentState(
			uptimeSeconds: UInt32(mostRecent?.uptimeSeconds ?? 0),
			channelUtilization: mostRecent?.channelUtilization ?? 0.0,
			airtime: mostRecent?.airUtilTx ?? 0.0,
			sentPackets: UInt32(mostRecent?.numPacketsTx ?? 0),
			receivedPackets: UInt32(mostRecent?.numPacketsRx ?? 0),
			badReceivedPackets: UInt32(mostRecent?.numPacketsRxBad ?? 0),
			dupeReceivedPackets: UInt32(mostRecent?.numRxDupe ?? 0),
			packetsSentRelay: UInt32(mostRecent?.numTxRelay ?? 0),
			packetsCanceledRelay: UInt32(mostRecent?.numTxRelayCanceled ?? 0),
			nodesOnline: UInt32(mostRecent?.numOnlineNodes ?? 0),
			totalNodes: UInt32(mostRecent?.numTotalNodes ?? 0),
			timerRange: Date.now...future
		)

		let attributes = MeshActivityAttributes(nodeNum: Int(connectedNum), name: nodeName, shortName: nodeShortName)
		let content = ActivityContent(state: initialState, staleDate: Calendar.current.date(byAdding: .minute, value: 15, to: Date())!)

		do {
			let activity = try Activity<MeshActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)
			Logger.services.info("🚗 [CarPlay] Started Live Activity: \(activity.id)")
		} catch {
			Logger.services.error("🚗 [CarPlay] Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func endLiveActivity() {
		Task {
			for activity in Activity<MeshActivityAttributes>.activities {
				await activity.end(nil, dismissalPolicy: .immediate)
				Logger.services.info("🚗 [CarPlay] Ended Live Activity: \(activity.id)")
			}
		}
	}
#else
	private func startLiveActivityIfNeeded() {}
	private func endLiveActivity() {}
#endif
}
#endif
