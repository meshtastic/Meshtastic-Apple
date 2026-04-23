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

fileprivate struct FilteredUserList: View {
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

	var body: some View {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY")

		List(users, selection: $userSelection) { user in
			let mostRecent = user.mostRecentMessage
			let hasMessages = mostRecent != nil
			let hasUnreadMessages = user.unreadMessages > 0
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
										.foregroundColor(.secondary)
								} else if lastMessageDay == (currentDay - 1) {
									Text("Yesterday")
										.font(.footnote)
										.foregroundColor(.secondary)
								} else if lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
									Text(lastMessageTime.formattedDate(format: dateFormatString))
										.font(.footnote)
										.foregroundColor(.secondary)
								} else if lastMessageDay < (currentDay - 1800) {
									Text(lastMessageTime.formattedDate(format: dateFormatString))
										.font(.footnote)
										.foregroundColor(.secondary)
								}
							}
						}

						if hasMessages {
							HStack(alignment: .top) {
								Text("\(mostRecent != nil ? mostRecent!.messagePayload! : " ")")
									.font(.footnote)
									.foregroundColor(.secondary)
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
						if node != nil && !(user.userNode?.favorite ?? false) {
							user.userNode?.favorite = !(user.userNode?.favorite ?? false)
							Task {
								try await accessoryManager.setFavoriteNode(node: user.userNode!, connectedNodeNum: Int64(node!.num))
								Logger.data.info("Favorited a node")
							}
						} else {
							user.userNode?.favorite = !(user.userNode?.favorite ?? false)
							Task {
								try await accessoryManager.removeFavoriteNode(node: user.userNode!, connectedNodeNum: Int64(node!.num))
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
							await MeshPackets.shared.deleteUserMessages(user: userToDeleteMessages!)
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
		// Encrypted
		if isPkiEncrypted {
			if !user.pkiEncrypted { return false }
		}
		// Favorites
		if isFavorite {
			if user.userNode?.favorite != true { return false }
		}
		// Distance
		if distanceFilter {
			if let poi = LocationsHandler.currentLocation,
			   poi.latitude != LocationsHandler.DefaultLocation.latitude,
			   poi.longitude != LocationsHandler.DefaultLocation.longitude {
				let d = maxDistance * 1.1
				let r: Double = 6371009
				let meanLat = poi.latitude * .pi / 180
				let deltaLat = d / r * 180 / .pi
				let deltaLon = d / (r * cos(meanLat)) * 180 / .pi
				let minLat = poi.latitude - deltaLat
				let maxLat = poi.latitude + deltaLat
				let minLon = poi.longitude - deltaLon
				let maxLon = poi.longitude + deltaLon
				let hasNearbyPosition = (user.userNode?.positions ?? []).contains { pos in
					guard pos.latest else { return false }
					let lon = Double(pos.longitudeI) / 1e7
					let lat = Double(pos.latitudeI) / 1e7
					return lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat
				}
				if !hasNearbyPosition { return false }
			}
		}
		// Unmessagable filter
		if user.unmessagable {
			let hasMessages = !(user.receivedMessages ?? []).isEmpty || !(user.sentMessages ?? []).isEmpty
			if !hasMessages { return false }
		}
		// Ignored
		if user.userNode?.ignored == true { return false }
		// Connected node
		if user.numString == String(UserDefaults.preferredPeripheralNum) { return false }
		return true
	}
}
