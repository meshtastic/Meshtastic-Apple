import CoreData
import OSLog
import SwiftUI

struct Messages: View {
	private let restrictedChannels = ["gpio", "mqtt", "serial"]
	private let dateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short

		return formatter
	}()

	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager
	@StateObject
	private var appState = AppState.shared
	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@State
	private var node: NodeInfoEntity?
	@State
	private var searchText = ""
	@State
	private var channelSelection: ChannelEntity? // Nothing selected by default.
	@State
	private var userSelection: UserEntity? // Nothing selected by default.
	@State
	private var isPresentingDeleteChannelMessagesConfirm: Bool = false
	@State
	private var isPresentingTraceRouteSentAlert = false
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

	private var badgeBackground: Color {
		if colorScheme == .dark {
			Color(red: 28 / 256, green: 28 / 256, blue: 30 / 256)
		}
		else {
			.white
		}
	}

	var body: some View {
		NavigationStack {
			List {
				channelList
				userList
			}
			.listStyle(.automatic)
			.disableAutocorrection(true)
			.scrollDismissesKeyboard(.immediately)
			.searchable(
				text: $searchText,
				placement: users.count > 10 ? .navigationBarDrawer(displayMode: .always) : .automatic,
				prompt: "Find a contact"
			)
			.onAppear {
				if UserDefaults.preferredPeripheralId.count > 0 {
					let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
					fetchNodeInfoRequest.predicate = NSPredicate(
						format: "num == %lld",
						Int64(UserDefaults.preferredPeripheralNum)
					)

					let fetchedNode = try? context.fetch(fetchNodeInfoRequest)
					if let fetchedNode, !fetchedNode.isEmpty {
						node = fetchedNode.first
					}
				}
			}
			.onChange(of: searchText, initial: true) {
				Task {
					await updateFilter()
				}
			}
			.navigationTitle("Messages")
			.navigationBarTitleDisplayMode(.large)
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ConnectedDevice(ble: bleManager)
			)
		}
	}

	@ViewBuilder
	private var channelList: some View {
		if
			let node,
			let myInfo = node.myInfo,
			let channels = myInfo.channels?.array as? [ChannelEntity]
		{
			Section(
				header: listHeader(
					title: "Channels",
					nodesCount: channels.count
				)
			) {
				ForEach(channels, id: \.index) { channel in
					if !restrictedChannels.contains(channel.name?.lowercased() ?? "") {
						makeChannelLink(for: channel, myInfo: myInfo)
							.contextMenu {
								if
									let allPrivateMessages = channel.allPrivateMessages,
									!allPrivateMessages.isEmpty
								{
									Button(role: .destructive) {
										isPresentingDeleteChannelMessagesConfirm = true
										channelSelection = channel
									} label: {
										Label("Delete Messages", systemImage: "trash")
									}
								}

								Button {
									guard let user = node.user else {
										return
									}

									channel.mute.toggle()

									let adminMessageId = bleManager.saveChannel(
										channel: channel.protoBuf,
										fromUser: user,
										toUser: user
									)

									if adminMessageId > 0 {
										context.refresh(channel, mergeChanges: true)
									}

									do {
										try context.save()
									}
									catch {
										context.rollback()
										Logger.data.error("💥 Save Channel Mute Error")
									}
								} label: {
									Label(
										channel.mute ? "Show Alerts" : "Hide Alerts",
										systemImage: channel.mute ? "bell" : "bell.slash"
									)
								}
							}
							.confirmationDialog(
								"Messages in the channel will be deleted",
								isPresented: $isPresentingDeleteChannelMessagesConfirm,
								titleVisibility: .visible
							) {
								Button(role: .destructive) {
									guard let channelSelection else {
										return
									}

									deleteChannelMessages(channel: channelSelection, context: context)
									context.refresh(myInfo, mergeChanges: true)

									self.channelSelection = nil
								} label: {
									Text("Delete")
								}
							}
					}
				}
			}
			.headerProminence(.increased)
		}
	}

	@ViewBuilder
	private var userList: some View {
		if
			let node,
			let myInfo = node.myInfo
		{
			let userList = users.filter { user in
				guard user.userNode != nil else {
					return false
				}

				if let num = bleManager.connectedPeripheral?.num, user.num == num {
					return false
				}

				return true
			}

			Section(
				header: listHeader(
					title: "Users",
					nodesCount: userList.count
				)
			) {
				ForEach(userList, id: \.num) { user in
					let lastMessage = getLastMessage(for: user)

					if user.num != bleManager.connectedPeripheral?.num ?? 0 {
						makeUserLink(for: user, myInfo: myInfo, lastMessage: lastMessage)
							.contextMenu {
								getContextMenu(for: user, hasMessages: lastMessage != nil)
							}
							.confirmationDialog(
								"Conversation with \(user.longName ?? "user") be deleted",
								isPresented: $isPresentingDeleteUserMessagesConfirm,
								titleVisibility: .visible
							) {
								Button(role: .destructive) {
									guard let userSelection else {
										return
									}

									deleteUserMessages(user: userSelection, context: context)
									context.refresh(node.user!, mergeChanges: true)

									self.userSelection = nil
								} label: {
									Text("Delete")
								}
							}
					}
				}
			}
			.headerProminence(.increased)
		}
	}

	@ViewBuilder
	private func listHeader(title: String, nodesCount: Int) -> some View {
		HStack(alignment: .center) {
			Text(title)
				.fontDesign(.rounded)

			Spacer()

			Text(String(nodesCount))
				.fontDesign(.rounded)
		}
	}

	@ViewBuilder
	private func makeChannelLink(
		for channel: ChannelEntity,
		myInfo: MyInfoEntity
	) -> some View {
		NavigationLink {
			MessageList(channel: channel, myInfo: myInfo)
		} label: {
			let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0

			let hasMessages = channel.allPrivateMessages?.isEmpty ?? false
			let lastMessage = channel.allPrivateMessages?.last(where: { message in
				message.channel == channel.index
			})
			let lastMessageTime = Date(
				timeIntervalSince1970: TimeInterval(Int64(lastMessage?.messageTimestamp ?? 0))
			)
			let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0

			avatar(for: channel)

			VStack(alignment: .leading) {
				HStack(alignment: .top, spacing: 8) {
					if let name = channel.name, !name.isEmpty {
						Text(String(name).camelCaseToWords())
							.font(.headline)
					}
					else {
						if channel.role == 1 {
							Text("Primary Channel")
								.font(.headline)
						}
						else {
							Text("Channel #\(channel.index)")
								.font(.headline)
						}
					}

					Spacer()

					if hasMessages {
						if lastMessageDay == currentDay {
							Text(lastMessageTime, style: .time )
								.font(.footnote)
								.foregroundColor(.secondary)
						}
						else if  lastMessageDay == (currentDay - 1) {
							Text("Yesterday")
								.font(.footnote)
								.foregroundColor(.secondary)
						}
						else if  lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
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

				if hasMessages, let lastMessagePayload = lastMessage?.messagePayload {
					Text(lastMessagePayload)
						.lineLimit(3)
						.font(.footnote)
						.foregroundColor(.secondary)
				}
			}
		}
	}

	@ViewBuilder
	private func makeUserLink(
		for user: UserEntity,
		myInfo: MyInfoEntity,
		lastMessage: MessageEntity?
	) -> some View {
		let lastMessageTime = Date(
			timeIntervalSince1970: TimeInterval(Int64(lastMessage?.messageTimestamp ?? 0))
		)

		let lastMessageDay = Calendar.current.dateComponents(
			[.day],
			from: lastMessageTime
		).day ?? 0

		let currentDay = Calendar.current.dateComponents(
			[.day],
			from: Date()
		).day ?? 0

		NavigationLink {
			MessageList(user: user, myInfo: myInfo)
		} label: {
			HStack(spacing: 8) {
				avatar(for: user)

				VStack(alignment: .leading) {
					HStack(alignment: .top) {
						Text(user.longName ?? "Unknown user".localized)
							.lineLimit(1)
							.font(.headline)
							.minimumScaleFactor(0.5)

						Spacer()

						if lastMessage != nil {
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

					if let payload = lastMessage?.messagePayload {
						Text(payload)
							.font(.footnote)
							.foregroundColor(.secondary)
					}
				}
			}
		}
	}

	@ViewBuilder
	private func avatar(for user: UserEntity) -> some View {
		ZStack(alignment: .top) {
			Avatar(
				user.userNode,
				size: 64
			)
			.padding([.top, .bottom, .trailing], 12)

			if user.unreadMessages > 0 {
				HStack(spacing: 0) {
					Spacer()

					if user.unreadMessages <= 50 {
						Image(systemName: "\(user.unreadMessages).circle")
							.font(.system(size: 24))
							.foregroundColor(.red)
							.background(
								Circle()
									.foregroundColor(badgeBackground)
							)
					}
					else {
						Image(systemName: "book.closed.circle.fill")
							.font(.system(size: 24))
							.foregroundColor(.red)
							.background(
								Circle()
									.foregroundColor(badgeBackground)
							)
					}
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
								.foregroundColor(badgeBackground)
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
								.foregroundColor(badgeBackground)
						)
				}
			}
		}
		.frame(width: 80, height: 80)
	}

	@ViewBuilder
	private func avatar(for channel: ChannelEntity) -> some View {
		ZStack(alignment: .top) {
			Avatar(
				label: String(channel.index),
				background: .accentColor,
				size: 64
			)
			.padding([.top, .bottom, .trailing], 12)

			if channel.unreadMessages > 0 {
				HStack(spacing: 0) {
					Spacer()

					Image(systemName: "circle.fill")
						.font(.system(size: 24))
						.foregroundColor(.red)
				}
			}
		}
		.frame(width: 80, height: 80)
	}

	@ViewBuilder
	private func getContextMenu(for user: UserEntity, hasMessages: Bool) -> some View {
		Button {
			if let node, let userNode = user.userNode, !userNode.favorite {
				let success: Bool
				if userNode.favorite {
					success = bleManager.removeFavoriteNode(
						node: userNode,
						connectedNodeNum: Int64(node.num)
					)
				}
				else {
					success = bleManager.setFavoriteNode(
						node: userNode,
						connectedNodeNum: Int64(node.num)
					)
				}

				if success {
					userNode.favorite.toggle()
				}
			}

			context.refresh(user, mergeChanges: true)

			do {
				try context.save()
			}
			catch {
				context.rollback()
				Logger.data.error("Save Node Favorite Error")
			}
		} label: {
			Label(
				user.userNode?.favorite ?? false ? "Un-Favorite" : "Favorite",
				systemImage: user.userNode?.favorite ?? false ? "star.slash.fill" : "star.fill"
			)
		}

		Button {
			user.mute.toggle()

			do {
				try context.save()
			}
			catch {
				context.rollback()
				Logger.data.error("Save User Mute Error")
			}
		} label: {
			Label(
				user.mute ? "Show Alerts" : "Hide Alerts",
				systemImage: user.mute ? "bell" : "bell.slash"
			)
		}
		
		if hasMessages {
			Button(role: .destructive) {
				isPresentingDeleteUserMessagesConfirm = true
				userSelection = user
			} label: {
				Label("Delete Messages", systemImage: "trash")
			}
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

	private func updateFilter() async {
		let searchPredicates = [
			"userId",
			"numString",
			"hwModel",
			"longName",
			"shortName"
		].map { property in
			NSPredicate(format: "%K CONTAINS[c] %@", property, searchText)
		}

		if !searchText.isEmpty {
			users.nsPredicate = NSCompoundPredicate(type: .or, subpredicates: searchPredicates)
		}
		else {
			users.nsPredicate = nil
		}
	}

	private func getLastMessage(for user: UserEntity) -> MessageEntity? {
		user.messageList?.last
	}
}
