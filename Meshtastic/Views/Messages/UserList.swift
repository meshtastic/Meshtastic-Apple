//
//  UserList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import SwiftData
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
	@Environment(\.modelContext) private var context

	@Query(sort: [SortDescriptor(\UserEntity.lastMessage, order: .reverse),
				  SortDescriptor(\UserEntity.longName)])
	private var allUsers: [UserEntity]
	@Binding var userSelection: UserEntity?
	@Binding var node: NodeInfoEntity?

	@State private var isPresentingDeleteUserMessagesConfirm: Bool = false
	@State private var userToDeleteMessages: UserEntity?
	private var filters: NodeFilterParameters

	init(withFilters: NodeFilterParameters, node: Binding<NodeInfoEntity?>, userSelection: Binding<UserEntity?>) {
		self.filters = withFilters
		self._node = node
		self._userSelection = userSelection
	}

	private var users: [UserEntity] {
		allUsers.filter { filters.matches(user: $0) }
	}

	// MARK: - Precomputed message info cache

	/// Batch-fetch most recent messages and unread counts for all visible users in two queries
	/// instead of 2N individual queries (one per row).
	private var messageInfo: [Int64: (mostRecent: MessageEntity?, unreadCount: Int)] {
		let userNums = Set(users.map(\.num))
		guard !userNums.isEmpty else { return [:] }

		// Fetch all non-emoji, non-admin messages for visible users in one query
		let detectionSensorPortNum: Int32 = 10
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
			},
			sortBy: [SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse)]
		)
		let allMessages = (try? context.fetch(descriptor)) ?? []

		var result: [Int64: (mostRecent: MessageEntity?, unreadCount: Int)] = [:]
		for num in userNums {
			result[num] = (mostRecent: nil, unreadCount: 0)
		}
		for message in allMessages {
			let fromNum = message.fromUser?.num
			let toNum = message.toUser?.num
			// Check if this message belongs to any of the visible users
			for num in [fromNum, toNum].compactMap({ $0 }) where userNums.contains(num) {
				var entry = result[num]!
				if entry.mostRecent == nil {
					entry.mostRecent = message
				}
				if !message.read {
					entry.unreadCount += 1
				}
				result[num] = entry
			}
		}
		return result
	}

	var body: some View {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY")
		let cachedInfo = messageInfo

		List(users, selection: $userSelection) { user in
			let info = cachedInfo[user.num]
			let mostRecent = info?.mostRecent
			let hasMessages = mostRecent != nil
			let hasUnreadMessages = (info?.unreadCount ?? 0) > 0
			let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0 ))))
			let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
			let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0
			if user.num != accessoryManager.activeDeviceNum ?? 0 {
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
									/// Public Key on the User and the Public Key on the Last Message don't match
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
							if hasMessages {
								if lastMessageDay == currentDay {
									Text(lastMessageTime, style: .time )
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

						if hasMessages {
							HStack(alignment: .top) {
									Text(LocalizedStringKey(mostRecent?.messagePayload ?? " "))
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
		}
		.listStyle(.plain)
		.navigationTitle(String.localizedStringWithFormat("Contacts (%@)".localized, String(users.count)))
	}
}
fileprivate extension NodeFilterParameters {
	/// In-memory filter matching for use with @Query results
	func matches(user: UserEntity) -> Bool {
		// Search text
		if !searchText.isEmpty {
			let text = searchText.lowercased()
			let matchesSearch = [user.userId, user.numString, user.hwModel, user.hwDisplayName, user.longName, user.shortName]
				.compactMap { $0?.lowercased() }
				.contains { $0.contains(text) }
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
			let twoHoursAgo = Calendar.current.date(byAdding: .minute, value: -120, to: Date()) ?? Date.distantPast
			if let lastHeard = user.userNode?.lastHeard, lastHeard < twoHoursAgo { return false }
			if user.userNode?.lastHeard == nil { return false }
		}
		// Favorites
		if isFavorite {
			if user.userNode?.favorite != true { return false }
		}
		// Distance — only apply when we have a valid, precise phone GPS fix
		if distanceFilter {
		if let poi = LocationsHandler.currentPreciseLocation {
				let d = maxDistance * 1.1
				let r: Double = 6371009
				let meanLat = poi.latitude * .pi / 180
				let deltaLat = d / r * 180 / .pi
				let deltaLon = d / (r * cos(meanLat)) * 180 / .pi
				let minLatI = Int32((poi.latitude - deltaLat) * 1e7)
				let maxLatI = Int32((poi.latitude + deltaLat) * 1e7)
				let minLonI = Int32((poi.longitude - deltaLon) * 1e7)
				let maxLonI = Int32((poi.longitude + deltaLon) * 1e7)
				if let nodeNum = user.userNode?.num, let ctx = user.modelContext {
					let descriptor = FetchDescriptor<PositionEntity>(
						predicate: #Predicate<PositionEntity> {
							$0.nodePosition?.num == nodeNum && $0.latest == true
							&& $0.latitudeI >= minLatI && $0.latitudeI <= maxLatI
							&& $0.longitudeI >= minLonI && $0.longitudeI <= maxLonI
						}
					)
					let count = (try? ctx.fetchCount(descriptor)) ?? 0
					if count == 0 { return false }
				} else {
					return false
				}
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
