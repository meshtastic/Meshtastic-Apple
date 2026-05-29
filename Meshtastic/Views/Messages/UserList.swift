//
//  UserList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
@preconcurrency import SwiftData
import OSLog
import TipKit

struct UserList: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var editingFilters = false
	@State private var showingHelp = false
	@State private var showingTrustConfirm: Bool = false
	@StateObject private var filters: NodeFilterParameters = NodeFilterParameters()
	@Binding var node: NodeInfoEntity?
	@Binding var userSelection: UserEntity?

	var body: some View {
		VStack {
			FilteredUserList(withFilters: filters, node: $node, userSelection: $userSelection)
			.sheet(isPresented: $editingFilters) {
				NodeListFilter(filterTitle: "Contact Filters", filters: filters)
			}
			.sheet(isPresented: $showingHelp) {
				DirectMessagesHelp()
			}
			.safeAreaInset(edge: .bottom, alignment: .leading) {
				HStack {
					Button(action: {
						withAnimation {
							showingHelp = !showingHelp
						}
					}) {
						Image(systemName: !editingFilters ? "questionmark.circle" : "questionmark.circle.fill")
							.padding(.vertical, 5)
					}
					.tint(Color(UIColor.secondarySystemBackground))
					.foregroundColor(.accentColor)
					.buttonStyle(.borderedProminent)
					Spacer()
					Button(action: {
						withAnimation {
							editingFilters = !editingFilters
						}
					}) {
						Image(systemName: !editingFilters ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
							.padding(.vertical, 5)
					}
					.tint(Color(UIColor.secondarySystemBackground))
					.foregroundColor(.accentColor)
					.buttonStyle(.borderedProminent)
				}
				.controlSize(.regular)
				.padding(5)
			}
			.padding(.bottom, 5)
			.searchable(text: $filters.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a contact")
			.autocorrectionDisabled(true)
			.scrollDismissesKeyboard(.immediately)
		}
	}
}

private struct FilteredUserList: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var appState: AppState
	@Environment(\.modelContext) private var context

	@Query(sort: [SortDescriptor(\UserEntity.lastMessage, order: .reverse),
				  SortDescriptor(\UserEntity.longName)])
	private var allUsers: [UserEntity]
	@Binding var userSelection: UserEntity?
	@Binding var node: NodeInfoEntity?

	@State private var isPresentingDeleteUserMessagesConfirm: Bool = false
	@State private var userToDeleteMessages: UserEntity?
	@State private var directMessageSummaries: [Int64: DirectMessageSummary] = [:]
	private var filters: NodeFilterParameters

	init(withFilters: NodeFilterParameters, node: Binding<NodeInfoEntity?>, userSelection: Binding<UserEntity?>) {
		self.filters = withFilters
		self._node = node
		self._userSelection = userSelection
	}

	private var users: [UserEntity] {
		let searchText = filters.searchText.lowercased()
		let onlineThreshold = filters.isOnline ? Date().addingTimeInterval(-7_200) : nil
		let distanceBounds = filters.currentPreciseDistanceBounds
		let filterLookup = UserListFilterLookup(
			users: allUsers,
			distanceBounds: filters.distanceFilter ? distanceBounds : nil,
			context: context
		)
		return allUsers.filter {
			filters.matches(
				user: $0,
				normalizedSearchText: searchText,
				onlineThreshold: onlineThreshold,
				distanceBounds: distanceBounds,
				lookup: filterLookup
			)
		}
	}

	var body: some View {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY")
		let activeDeviceNum = Int64(accessoryManager.activeDeviceNum ?? 0)
		let visibleUsers = users.filter { $0.num != activeDeviceNum }
		let summaryUsers = allUsers.filter { $0.num != activeDeviceNum && $0.lastMessage != nil }
		let summaryRefreshKey = directMessageSummaryRefreshKey(for: summaryUsers)
		let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0

		List(visibleUsers, selection: $userSelection) { user in
			DirectMessageUserRow(
				user: user,
				node: node,
				summary: directMessageSummaries[user.num],
				dateFormatString: dateFormatString,
				currentDay: currentDay,
				isPresentingDeleteUserMessagesConfirm: $isPresentingDeleteUserMessagesConfirm,
				userToDeleteMessages: $userToDeleteMessages
			)
		}
		.listStyle(.plain)
		.navigationTitle(String.localizedStringWithFormat("Contacts (%@)".localized, String(visibleUsers.count)))
		.onAppear {
			refreshDirectMessageSummaries(for: summaryUsers)
		}
		.onChange(of: summaryRefreshKey) {
			refreshDirectMessageSummaries(for: summaryUsers)
		}
		.onChange(of: appState.unreadDirectMessages) {
			refreshDirectMessageSummaries(for: summaryUsers)
		}
	}

	private func directMessageSummaryRefreshKey(for users: [UserEntity]) -> Int64 {
		var key = Int64(users.count)
		for user in users {
			key = key &* 31 &+ user.num
			if let lastMessage = user.lastMessage {
				key = key &* 31 &+ Int64(lastMessage.timeIntervalSince1970)
			}
		}
		return key
	}

	private func refreshDirectMessageSummaries(for users: [UserEntity]) {
		let userNums = Set(users.map(\.num))
		guard !userNums.isEmpty else {
			directMessageSummaries = [:]
			return
		}

		do {
			let detectionSensorPortNum: Int32 = 10
			let descriptor = FetchDescriptor<MessageEntity>(
				predicate: #Predicate<MessageEntity> {
					$0.toUser != nil
					&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
				},
				sortBy: [
					SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse),
					SortDescriptor(\MessageEntity.messageId, order: .reverse)
				]
			)
			let messages = try context.fetch(descriptor)
			var accumulators = [Int64: DirectMessageSummaryAccumulator](minimumCapacity: userNums.count)
			for message in messages {
				let fromNum = message.fromUser?.num
				record(message, peerNum: fromNum, userNums: userNums, accumulators: &accumulators)
				let toNum = message.toUser?.num
				if toNum != fromNum {
					record(message, peerNum: toNum, userNums: userNums, accumulators: &accumulators)
				}
			}
			directMessageSummaries = accumulators.compactMapValues(\.summary)
		} catch {
			Logger.data.error("Failed to load direct message summaries: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func record(
		_ message: MessageEntity,
		peerNum: Int64?,
		userNums: Set<Int64>,
		accumulators: inout [Int64: DirectMessageSummaryAccumulator]
	) {
		guard let peerNum, userNums.contains(peerNum) else { return }
		accumulators[peerNum, default: DirectMessageSummaryAccumulator()].record(message)
	}
}

private struct DirectMessageSummary: Equatable {
	let messageId: Int64
	let timestamp: Int32
	let payload: String
	let unreadCount: Int
}

private struct DirectMessageSummaryAccumulator {
	private var latestMessageId: Int64 = Int64.min
	private var latestTimestamp: Int32 = Int32.min
	private var latestPayload: String = " "
	private var unreadCount = 0

	var summary: DirectMessageSummary? {
		guard latestMessageId != Int64.min else { return nil }
		return DirectMessageSummary(
			messageId: latestMessageId,
			timestamp: latestTimestamp,
			payload: latestPayload,
			unreadCount: unreadCount
		)
	}

	mutating func record(_ message: MessageEntity) {
		if !message.read {
			unreadCount += 1
		}
		if message.messageTimestamp > latestTimestamp
			|| (message.messageTimestamp == latestTimestamp && message.messageId > latestMessageId) {
			latestMessageId = message.messageId
			latestTimestamp = message.messageTimestamp
			latestPayload = message.messagePayload ?? " "
		}
	}
}

private struct DirectMessageUserRow: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	@Bindable var user: UserEntity
	let node: NodeInfoEntity?
	let summary: DirectMessageSummary?
	let dateFormatString: String
	let currentDay: Int
	@Binding var isPresentingDeleteUserMessagesConfirm: Bool
	@Binding var userToDeleteMessages: UserEntity?

	private var hasMessages: Bool { summary != nil }
	private var hasUnreadMessages: Bool { (summary?.unreadCount ?? 0) > 0 }

	var body: some View {
		NavigationLink(value: user) {
			ZStack {
				Image(systemName: "circle.fill")
					.opacity(hasUnreadMessages ? 1 : 0)
					.font(.system(size: 10))
					.foregroundColor(.accentColor)
					.brightness(0.2)
			}

			CircleText(text: user.shortName ?? "?", color: Color(UIColor(hex: UInt32(user.num))))

			VStack(alignment: .leading) {
				HStack {
					if user.pkiEncrypted {
						if !user.keyMatch {
							Image(systemName: "key.slash")
								.foregroundColor(.red)
						} else {
							Image(systemName: "lock.fill")
								.foregroundColor(.green)
						}
					} else {
						Image(systemName: "lock.open.fill")
							.foregroundColor(.yellow)
					}
					Text(user.longName ?? "Unknown".localized)
						.font(.headline)
						.allowsTightening(true)
					Spacer()
					if user.userNode?.favorite ?? false {
						Image(systemName: "star.fill")
							.foregroundColor(.yellow)
					}
					if let summary {
						messageTimeText(summary)
					}
				}

				if let summary {
					HStack(alignment: .top) {
						Text(LocalizedStringKey(summary.payload))
							.font(.footnote)
							.foregroundColor(.onSurfaceVariant)
					}
				}
			}
		}
		.frame(height: 62)
		.alignmentGuide(.listRowSeparatorLeading) {
			$0[.leading]
		}
		.contextMenu {
			Button {
				guard let userNode = user.userNode, let node else { return }
				if !(userNode.favorite) {
					userNode.favorite = true
					Task {
						try await accessoryManager.setFavoriteNode(node: userNode, connectedNodeNum: Int64(node.num))
						Logger.data.info("Favorited a node")
					}
				} else {
					userNode.favorite = false
					Task {
						try await accessoryManager.removeFavoriteNode(node: userNode, connectedNodeNum: Int64(node.num))
						Logger.data.info("Unfavorited a node")
					}
				}
				do {
					try context.save()
				} catch {
					Logger.data.error("Save Node Favorite Error")
				}
			} label: {
				Label((user.userNode?.favorite ?? false) ? "Un-Favorite" : "Favorite", systemImage: (user.userNode?.favorite ?? false) ? "star.slash.fill" : "star.fill")
			}
			Button {
				user.mute = !user.mute
				do {
					try context.save()
				} catch {
					Logger.data.error("Save User Mute Error")
				}
			} label: {
				Label(user.mute ? "Show Alerts" : "Hide Alerts", systemImage: user.mute ? "bell" : "bell.slash")
			}
			if hasMessages {
				Button(role: .destructive) {
					isPresentingDeleteUserMessagesConfirm = true
					userToDeleteMessages = user
				} label: {
					Label("Delete Messages", systemImage: "trash")
				}
			}
		}
		.confirmationDialog(
			"This conversation will be deleted.",
			isPresented: $isPresentingDeleteUserMessagesConfirm,
			titleVisibility: .visible
		) {
			Button(role: .destructive) {
				Task {
					if let userToDelete = userToDeleteMessages {
						await MeshPackets.shared.deleteUserMessages(user: userToDelete)
					}
				}
			} label: {
				Text("Delete")
			}
		}
	}

	@ViewBuilder
	private func messageTimeText(_ summary: DirectMessageSummary) -> some View {
		let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64(summary.timestamp)))
		let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
		if lastMessageDay == currentDay {
			Text(lastMessageTime, style: .time)
				.font(.footnote)
				.foregroundColor(.onSurfaceVariant)
		} else if lastMessageDay == (currentDay - 1) {
			Text("Yesterday")
				.font(.footnote)
				.foregroundColor(.onSurfaceVariant)
		} else if lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
			Text(lastMessageTime.formattedDate(format: dateFormatString))
				.font(.footnote)
				.foregroundColor(.onSurfaceVariant)
		} else if lastMessageDay < (currentDay - 1800) {
			Text(lastMessageTime.formattedDate(format: dateFormatString))
				.font(.footnote)
				.foregroundColor(.onSurfaceVariant)
		}
	}
}

private struct UserListFilterLookup {
	private let distanceNodeNums: Set<Int64>?

	init(users: [UserEntity], distanceBounds: NodeDistanceFilterBounds?, context: ModelContext) {
		guard let distanceBounds else {
			self.distanceNodeNums = nil
			return
		}
		let nodeNums = Array(Set(users.map(\.num)))
		self.distanceNodeNums = Self.fetchDistanceNodeNums(nodeNums: nodeNums, bounds: distanceBounds, context: context)
	}

	func isWithinDistance(_ user: UserEntity) -> Bool {
		distanceNodeNums?.contains(user.num) ?? false
	}

	private static func fetchDistanceNodeNums(
		nodeNums: [Int64],
		bounds: NodeDistanceFilterBounds,
		context: ModelContext
	) -> Set<Int64> {
		guard !nodeNums.isEmpty else { return [] }
		let descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> {
				$0.latest == true
				&& $0.nodePosition != nil
				&& ($0.nodePosition.flatMap { nodeNums.contains($0.num) } ?? false)
			}
		)
		let positions = (try? context.fetch(descriptor)) ?? []
		return Set(positions.compactMap { position in
			guard bounds.contains(position) else { return nil }
			return position.nodePosition?.num
		})
	}
}

fileprivate extension NodeFilterParameters {
	/// In-memory filter matching for use with @Query results
	func matches(
		user: UserEntity,
		normalizedSearchText: String,
		onlineThreshold: Date?,
		distanceBounds: NodeDistanceFilterBounds?,
		lookup: UserListFilterLookup
	) -> Bool {
		// Search text
		if !normalizedSearchText.isEmpty {
			let matchesSearch = [user.userId, user.numString, user.hwModel, user.hwDisplayName, user.longName, user.shortName]
				.compactMap { $0?.lowercased() }
				.contains { $0.contains(normalizedSearchText) }
			if !matchesSearch { return false }
		}
		// Mqtt and lora
		if !(viaLora && viaMqtt) {
			if viaLora {
				if user.userNode?.viaMqtt == true { return false }
			} else {
				if user.userNode?.viaMqtt != true { return false }
			}
		}
		// Roles
		if roleFilter && !deviceRoles.isEmpty {
			let userRole = Int(user.role)
			if !deviceRoles.contains(userRole) { return false }
		}
		// Hops Away
		if hopsAway == 0 {
			if user.userNode?.hopsAway != 0 { return false }
		} else if hopsAway > -1 {
			let nodeHops = user.userNode?.hopsAway ?? 0
			if nodeHops <= 0 || nodeHops > Int32(hopsAway) { return false }
		}
		// Online
		if isOnline {
			guard let lastHeard = user.userNode?.lastHeard,
				  let onlineThreshold else {
				return false
			}
			if lastHeard < onlineThreshold { return false }
		}
		// Favorites
		if isFavorite {
			if user.userNode?.favorite != true { return false }
		}
		// Distance — only apply when we have a valid, precise phone GPS fix
		if distanceFilter, distanceBounds != nil {
			guard lookup.isWithinDistance(user) else {
				return false
			}
		}
		// Unmessagable filter
		if user.unmessagable {
			if user.lastMessage == nil { return false }
		}
		// Ignored
		if user.userNode?.ignored == true { return false }
		// Encrypted
		if isPkiEncrypted {
			if !user.pkiEncrypted { return false }
		}
		// Connected node
		if user.numString == String(UserDefaults.preferredPeripheralNum) { return false }
		return true
	}
}
