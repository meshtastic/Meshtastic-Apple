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

import CarPlay
import Combine
import CoreData
import Intents
import OSLog
#if canImport(ActivityKit)
import ActivityKit
#endif

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate {

	var interfaceController: CPInterfaceController?
	private var cancellables = Set<AnyCancellable>()
	private var context: NSManagedObjectContext {
		PersistenceController.shared.container.viewContext
	}

	private func lastHeardText(_ date: Date?) -> String {
		guard let date else { return "Never heard" }
		let interval = Date().timeIntervalSince(date)
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

		let rootTemplate = buildRootTemplate()
		interfaceController.setRootTemplate(rootTemplate, animated: false, completion: nil)

		// Observe connection state changes and refresh the template
		AccessoryManager.shared.$isConnected
			.removeDuplicates()
			.dropFirst() // Skip initial value — we already set the root template above
			.receive(on: DispatchQueue.main)
			.sink { [weak self] isConnected in
				self?.refreshRootTemplate()
				if isConnected {
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
		self.interfaceController = nil
	}

	// MARK: - CPInterfaceControllerDelegate

	func templateWillAppear(_ aTemplate: CPTemplate, animated: Bool) {}
	func templateDidAppear(_ aTemplate: CPTemplate, animated: Bool) {}
	func templateWillDisappear(_ aTemplate: CPTemplate, animated: Bool) {}
	func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {}

	// MARK: - Root Template

	private func refreshRootTemplate() {
		guard let interfaceController else { return }
		let rootTemplate = buildRootTemplate()
		interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
	}

	private func buildRootTemplate() -> CPTemplate {
		let connected = AccessoryManager.shared.isConnected

		// Channels tab
		let channelsTab = buildChannelsTab(connected: connected)

		// Direct Messages tab
		let directMessagesTab = buildDirectMessagesTab(connected: connected)

		let tabBar = CPTabBarTemplate(templates: [channelsTab, directMessagesTab])
		return tabBar
	}

	// MARK: - Channels Tab

	private func buildChannelsTab(connected: Bool) -> CPListTemplate {
		var sections = [CPListSection]()

		if connected {
			let channelItems = fetchChannelItems()
			if !channelItems.isEmpty {
				sections.append(CPListSection(items: channelItems))
			} else {
				let emptyItem = CPListItem(text: "No Channels", detailText: nil)
				emptyItem.isEnabled = false
				sections.append(CPListSection(items: [emptyItem]))
			}
		} else {
			let statusItem = CPListItem(
				text: "Not Connected",
				detailText: "Open Meshtastic to connect",
				image: UIImage(systemName: "antenna.radiowaves.left.and.right.slash")
			)
			statusItem.isEnabled = false
			sections.append(CPListSection(items: [statusItem]))
		}

		let template = CPListTemplate(title: "Channels", sections: sections)
		template.tabImage = UIImage(systemName: "bubble.left.and.bubble.right")
		return template
	}

	// MARK: - Direct Messages Tab

	private func buildDirectMessagesTab(connected: Bool) -> CPListTemplate {
		var sections = [CPListSection]()

		if connected {
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
		} else {
			let statusItem = CPListItem(
				text: "Not Connected",
				detailText: "Open Meshtastic to connect",
				image: UIImage(systemName: "antenna.radiowaves.left.and.right.slash")
			)
			statusItem.isEnabled = false
			sections.append(CPListSection(items: [statusItem]))
		}

		let template = CPListTemplate(title: "Direct Messages", sections: sections)
		template.tabImage = UIImage(systemName: "bubble.left.and.text.bubble.right")
		return template
	}

	// MARK: - Data Fetching

	private func fetchFavoriteContactItems() -> [CPMessageListItem] {
		let request: NSFetchRequest<NodeInfoEntity> = NodeInfoEntity.fetchRequest()
		request.predicate = NSPredicate(format: "favorite == YES AND num != %lld", AccessoryManager.shared.activeDeviceNum ?? 0)
		request.sortDescriptors = [NSSortDescriptor(key: "lastHeard", ascending: false)]
		request.relationshipKeyPathsForPrefetching = ["user"]

		do {
			let nodes = try context.fetch(request)
			return nodes.compactMap { node -> CPMessageListItem? in
				guard let user = node.user else { return nil }
				let name = user.longName ?? user.shortName ?? "Unknown"
				let unreadCount = user.unreadMessages(context: context)
				let hasUnread = unreadCount > 0

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
					trailingText: lastHeardText(node.lastHeard)
				)
				item.conversationIdentifier = "dm-\(node.num)"
				item.userInfo = node.num

				donateMessageIntent(toNodeNum: node.num, name: name)

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
			  let myInfo = connectedNode.myInfo,
			  let channels = myInfo.channels?.array as? [ChannelEntity] else {
			return []
		}

		return channels.compactMap { channel -> CPMessageListItem? in
			guard channel.role > 0 else { return nil }
			let name = (channel.name?.isEmpty ?? true)
				? (channel.index == 0 ? "Primary Channel" : "Channel \(channel.index)")
				: channel.name!
			let unreadCount = channel.unreadMessages(context: context)
			let hasUnread = unreadCount > 0
			let channelIndex = Int(channel.index)

			let leadingConfig = CPMessageListItemLeadingConfiguration(
				leadingItem: .none,
				leadingImage: UIImage(systemName: channel.index == 0 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right"),
				unread: hasUnread
			)

			let item = CPMessageListItem(
				conversationIdentifier: "channel-\(channelIndex)",
				text: name,
				leadingConfiguration: leadingConfig,
				trailingConfiguration: nil,
				detailText: hasUnread ? "\(unreadCount) unread" : (channel.index == 0 ? "Primary" : "Ch \(channel.index)"),
				trailingText: nil
			)
			item.phoneOrEmailAddress = "channel-\(channelIndex)@meshtastic.local"
			item.userInfo = channelIndex

			donateChannelIntent(channelIndex: channelIndex, channelName: name)

			return item
		}
	}

	private func fetchDirectMessageItems() -> [CPMessageListItem] {
		let request: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
		let connectedNum = AccessoryManager.shared.activeDeviceNum ?? 0

		// Match the app's UserList: exclude self, exclude ignored, exclude favorites (shown above), show unmessagable only if they have messages
		let notSelf = NSPredicate(format: "userNode.num != %lld", connectedNum)
		let notIgnored = NSPredicate(format: "userNode.ignored == NO")
		let notFavorite = NSPredicate(format: "userNode.favorite == NO")
		let unmessagableFilter = NSCompoundPredicate(type: .or, subpredicates: [
			NSPredicate(format: "unmessagable == NO"),
			NSPredicate(format: "receivedMessages.@count > 0 OR sentMessages.@count > 0")
		])
		request.predicate = NSCompoundPredicate(type: .and, subpredicates: [notSelf, notIgnored, notFavorite, unmessagableFilter])
		request.sortDescriptors = [
			NSSortDescriptor(key: "userNode.lastHeard", ascending: false),
			NSSortDescriptor(key: "lastMessage", ascending: false),
			NSSortDescriptor(key: "longName", ascending: true)
		]
		request.fetchLimit = 24 // CarPlay limits list items

		do {
			let users = try context.fetch(request)
			return users.compactMap { user -> CPMessageListItem? in
				guard let node = user.userNode else { return nil }
				let name = user.longName ?? user.shortName ?? "Unknown"
				let unreadCount = user.unreadMessages(context: context)
				let hasUnread = unreadCount > 0
				let nodeNum = node.num

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
					trailingText: lastHeardText(node.lastHeard)
				)
				item.conversationIdentifier = "dm-\(nodeNum)"
				item.userInfo = nodeNum

				donateMessageIntent(toNodeNum: nodeNum, name: name)

				return item
			}
		} catch {
			Logger.services.error("🚗 [CarPlay] Failed to fetch DM users: \(error.localizedDescription, privacy: .public)")
			return []
		}
	}

	// MARK: - Intent Donation

	private func donateMessageIntent(toNodeNum: Int64, name: String) {
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
			conversationIdentifier: "dm-\(toNodeNum)",
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

	private func donateChannelIntent(channelIndex: Int, channelName: String) {
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
			conversationIdentifier: "channel-\(channelIndex)",
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

	// MARK: - Live Activity

#if canImport(ActivityKit)
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
		let localStats = connectedNode?.telemetries?.filtered(using: NSPredicate(format: "metricsType == 4"))
		let mostRecent = localStats?.lastObject as? TelemetryEntity

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
