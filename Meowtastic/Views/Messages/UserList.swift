import SwiftUI
import CoreData
import OSLog

struct UserList: View {
	@StateObject
	var appState = AppState.shared
	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager
	@State
	var isEditingFilters = false
	@State
	var node: NodeInfoEntity?
	@State
	var selectedUserNum: Int64?

	private let dateFormatString = DateFormatter.dateFormat(
		fromTemplate: "yyMMdd",
		options: 0,
		locale: Locale.current
	)!

	@State
	private var searchText = ""
	@State
	private var isFavorite = UserDefaults.filterFavorite
	@State
	private var isOnline = UserDefaults.filterOnline
	@State
	private var ignoreMQTT = UserDefaults.ignoreMQTT
	@State
	private var userSelection: UserEntity? // Nothing selected by default.
	@State
	private var isPresentingDeleteUserMessagesConfirm = false

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "lastMessage", ascending: false),
			NSSortDescriptor(key: "userNode.favorite", ascending: false),
			NSSortDescriptor(key: "longName", ascending: true)
		],
		animation: .default
	)
	private var users: FetchedResults<UserEntity>

	var body: some View {
		VStack {
			userList
				.navigationTitle(
					String.localizedStringWithFormat(
						"contacts %@".localized,
						String(users.count == 0 ? 0 : users.count - 1)
					)
				)
				.safeAreaInset(edge: .bottom, alignment: .trailing) {
					filterButton
				}
				.searchable(
					text: $searchText,
					placement: users.count > 10 ? .navigationBarDrawer(displayMode: .always) : .automatic,
					prompt: "Find a contact"
				)
				.disableAutocorrection(true)
				.scrollDismissesKeyboard(.immediately)
				.onAppear {
					if self.bleManager.context == nil {
						self.bleManager.context = context
					}

					Task {
						await updateFilter()
					}
				}
				.onChange(of: searchText, initial: true) {
					Task {
						await updateFilter()
					}
				}
				.onChange(of: isFavorite, initial: false) {
					Task {
						await updateFilter()
					}
				}
				.onChange(of: isOnline, initial: false) {
					Task {
						await updateFilter()
					}
				}
				.onChange(of: ignoreMQTT, initial: false) {
					Task {
						await updateFilter()
					}
				}
				.onChange(of: selectedUserNum) { newUserNum in
					userSelection = users.first(where: {
						$0.num == newUserNum
					})
				}
				.sheet(isPresented: $isEditingFilters) {
					NodeListFilter(
						filterTitle: "Contact Filters",
						isFavorite: $isFavorite,
						isOnline: $isOnline,
						ignoreMQTT: $ignoreMQTT
					)
				}
		}
	}

	@ViewBuilder
	private var userList: some View {
		List(
			users.filter { user in
				guard isFavorite || isOnline || ignoreMQTT else {
					return true
				}

				guard let userNode = user.userNode else {
					return false
				}

				if (isFavorite && userNode.favorite)
					|| (isOnline && userNode.isOnline)
					|| (ignoreMQTT && !userNode.viaMqtt)
				{
					return true
				}

				return false
			},
			id: \.self
		) { user in
			let mostRecent = user.messageList.last
			let lastMessageTime = Date(
				timeIntervalSince1970: TimeInterval(Int64(mostRecent?.messageTimestamp ?? 0))
			)

			let lastMessageDay = Calendar.current.dateComponents(
				[.day],
				from: lastMessageTime
			).day ?? 0

			let currentDay = Calendar.current.dateComponents(
				[.day],
				from: Date()
			).day ?? 0

			if  user.num != bleManager.connectedPeripheral?.num ?? 0 {
				NavigationLink(destination: UserMessageList(user: user)) {
					ZStack {
						Image(systemName: "circle.fill")
							.opacity(user.unreadMessages > 0 ? 1 : 0)
							.font(.system(size: 10))
							.foregroundColor(.accentColor)
							.brightness(0.2)
					}

					Avatar(
						user.shortName ?? "?",
						background: Color(UIColor(hex: UInt32(user.num)))
					)

					VStack(alignment: .leading) {
						HStack {
							Text(user.longName ?? "unknown".localized)
								.font(.headline)

							Spacer()

							if user.userNode?.favorite ?? false {
								Image(systemName: "star.fill")
									.foregroundColor(.yellow)
							}

							if user.messageList.count > 0 {
								if lastMessageDay == currentDay {
									Text(lastMessageTime, style: .time )
										.font(.footnote)
										.foregroundColor(.secondary)
								}
								else if lastMessageDay == (currentDay - 1) {
									Text("Yesterday")
										.font(.footnote)
										.foregroundColor(.secondary)
								}
								else if lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
									Text(lastMessageTime.formattedDate(format: dateFormatString))
										.font(.footnote)
										.foregroundColor(.secondary)
								}
								else if lastMessageDay < (currentDay - 1800) {
									Text(lastMessageTime.formattedDate(format: dateFormatString))
										.font(.footnote)
										.foregroundColor(.secondary)
								}
							}
						}

						if user.messageList.count > 0 {
							HStack(alignment: .top) {
								Text("\(mostRecent != nil ? mostRecent!.messagePayload! : " ")")
									.font(.footnote)
									.foregroundColor(.secondary)
							}
						}
					}
				}
				.frame(height: 62)
				.contextMenu {
					getContextMenu(for: user)
				}
				.confirmationDialog(
					"This conversation will be deleted.",
					isPresented: $isPresentingDeleteUserMessagesConfirm,
					titleVisibility: .visible
				) {
					Button(role: .destructive) {
						deleteUserMessages(user: userSelection!, context: context)
						context.refresh(node!.user!, mergeChanges: true)

						let badge = appState.unreadChannelMessages + appState.unreadDirectMessages
						UNUserNotificationCenter.current().setBadgeCount(badge)
					} label: {
						Text("delete")
					}
				}
			}
		}
		.listStyle(.plain)
	}

	private var filterIcon: String {
		if isEditingFilters {
			return "line.3.horizontal.decrease.circle.fill"
		}
		else {
			return "line.3.horizontal.decrease.circle"
		}
	}

	@ViewBuilder
	private var filterButton: some View {
		HStack {
			Button(action: {
				withAnimation {
					isEditingFilters = !isEditingFilters
				}
			}) {
				Image(systemName: filterIcon)
					.padding(.vertical, 5)
			}
			.tint(Color(UIColor.secondarySystemBackground))
			.foregroundColor(.accentColor)
			.buttonStyle(.borderedProminent)

		}
		.controlSize(.regular)
		.padding(5)
	}

	@ViewBuilder
	private func getContextMenu(for user: UserEntity) -> some View {
		Button {
			if node != nil && !(user.userNode?.favorite ?? false) {
				let success = bleManager.setFavoriteNode(
					node: user.userNode!,
					connectedNodeNum: Int64(node!.num)
				)

				if success {
					user.userNode?.favorite = !(user.userNode?.favorite ?? true)
					Logger.data.info("Favorited a node")
				}
			} else {
				let success = bleManager.removeFavoriteNode(
					node: user.userNode!,
					connectedNodeNum: Int64(node!.num)
				)

				if success {
					user.userNode?.favorite = !(user.userNode?.favorite ?? true)
					Logger.data.info("Un Favorited a node")
				}
			}

			context.refresh(user, mergeChanges: true)

			do {
				try context.save()
			} catch {
				context.rollback()
				Logger.data.error("Save Node Favorite Error")
			}
		} label: {
			Label(
				(user.userNode?.favorite ?? false)  ? "Un-Favorite" : "Favorite",
				systemImage: (user.userNode?.favorite ?? false) ? "star.slash.fill" : "star.fill"
			)
		}

		Button {
			user.mute = !user.mute

			do {
				try context.save()
			} catch {
				context.rollback()
				Logger.data.error("Save User Mute Error")
			}
		} label: {
			Label(
				user.mute ? "Show Alerts" : "Hide Alerts",
				systemImage: user.mute ? "bell" : "bell.slash"
			)
		}

		if user.messageList.count > 0 {
			Button(role: .destructive) {
				isPresentingDeleteUserMessagesConfirm = true
				userSelection = user
			} label: {
				Label("Delete Messages", systemImage: "trash")
			}
		}
	}

	private func updateFilter() async {
		UserDefaults.filterFavorite = isFavorite
		UserDefaults.filterOnline = isOnline
		UserDefaults.ignoreMQTT = ignoreMQTT

		let searchPredicates = [
			"userId",
			"numString",
			"hwModel",
			"longName",
			"shortName"
		].map { property in
			return NSPredicate(format: "%K CONTAINS[c] %@", property, searchText)
		}

		if !searchText.isEmpty {
			users.nsPredicate = NSCompoundPredicate(type: .or, subpredicates: searchPredicates)
		}
		else {
			users.nsPredicate = nil
		}
	}
}
