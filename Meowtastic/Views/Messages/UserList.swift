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
	var node: NodeInfoEntity?
	@State
	var selectedUserNum: Int64?

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@State
	private var searchText = ""
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

	private let dateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short

		return formatter
	}()

	var body: some View {
		userList
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
			.onChange(of: searchText) {
				Task {
					await updateFilter()
				}
			}
			.onChange(of: selectedUserNum) {
				userSelection = users.first(where: {
					$0.num == selectedUserNum
				})
			}
			.searchable(
				text: $searchText,
				placement: users.count > 10 ? .navigationBarDrawer(displayMode: .always) : .automatic,
				prompt: "Find a contact"
			)
			.navigationTitle(
				String.localizedStringWithFormat(
					"contacts %@".localized,
					String(users.count == 0 ? 0 : users.count - 1)
				)
			)
			.navigationBarTitleDisplayMode(.large)
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ConnectedDevice(ble: bleManager)
			)
	}

	@ViewBuilder
	private var userList: some View {
		List(
			users.filter { user in
				guard user.userNode != nil else {
					return false
				}

				if let num = bleManager.connectedPeripheral?.num, user.num == num {
					return false
				}

				return true
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

			if user.num != bleManager.connectedPeripheral?.num ?? 0 {
				NavigationLink(destination: UserMessageList(user: user)) {
					HStack(spacing: 8) {
						avatar(for: user)

						VStack(alignment: .leading) {
							HStack(alignment: .top) {
								Text(user.longName ?? "Unknown user".localized)
									.lineLimit(1)
									.font(.headline)
									.minimumScaleFactor(0.5)

								Spacer()

								if user.messageList.count > 0 {
									if lastMessageDay == currentDay {
										Text(lastMessageTime, style: .time)
											.font(.footnote)
											.foregroundColor(.secondary)
									}
									else if lastMessageDay == (currentDay - 1) {
										Text("Yesterday")
											.font(.footnote)
											.foregroundColor(.secondary)
									}
									else if lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
										Text(dateFormatter.string(from: lastMessageTime))
											.font(.footnote)
											.foregroundColor(.secondary)
									}
									else if lastMessageDay < (currentDay - 1800) {
										Text(dateFormatter.string(from: lastMessageTime))
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
	}

	@ViewBuilder
	private func avatar(for user: UserEntity) -> some View {
		ZStack(alignment: .top) {
			Avatar(
				user.shortName,
				background: getUserColor(for: user),
				size: 64
			)
			.padding(.all, 8)

			if user.unreadMessages > 0 {
				HStack(spacing: 0) {
					Spacer()

					Text(String(user.unreadMessages))
						.font(.system(size: 24))
						.foregroundColor(.white)
						.background(
							Circle()
								.foregroundColor(.red)
						)
				}
			}
			else if user.userNode?.favorite ?? false {
				HStack(spacing: 0) {
					Spacer()

					Image(systemName: "star.circle.fill")
						.font(.system(size: 24))
						.foregroundColor(colorScheme == .dark ? .white : .gray)
						.background(
							Circle()
								.foregroundColor(colorScheme == .dark ? .black : .white)
						)
				}
			}
			else if !(user.userNode?.isOnline ?? false) {
				HStack(spacing: 0) {
					Spacer()

					Image(systemName: "network.slash")
						.font(.system(size: 24))
						.foregroundColor(colorScheme == .dark ? .white : .gray)
						.background(
							Circle()
								.foregroundColor(colorScheme == .dark ? .black : .white)
						)
				}
			}
		}
		.frame(width: 80, height: 80)
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

	private func getUserColor(for user: UserEntity) -> Color {
		if
			let num = user.userNode?.num,
			user.userNode?.isOnline ?? false
		{
			return Color(
				UIColor(hex: UInt32(num))
			)
		}

		return Color.gray.opacity(0.7)
	}
}
