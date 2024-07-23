import SwiftUI
import CoreData
import OSLog

struct Messages: View {
	var restrictedChannels = ["gpio", "mqtt", "serial"]

	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager
	@StateObject
	var appState = AppState.shared

	@State
	var node: NodeInfoEntity?

	private let dateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short

		return formatter
	}()

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
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

	var body: some View {
		NavigationStack {
			List(/* selection: $channelSelection */) {
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
				if bleManager.context == nil {
					bleManager.context = context
				}

				if UserDefaults.preferredPeripheralId.count > 0 {
					let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
					fetchNodeInfoRequest.predicate = NSPredicate(
						format: "num == %lld",
						Int64(UserDefaults.preferredPeripheralNum)
					)

					let fetchedNode = try? context.fetch(fetchNodeInfoRequest)
					if let fetchedNode, !fetchedNode.isEmpty {
						node = fetchedNode[0]
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
							.onAppear {
								if self.bleManager.context == nil {
									self.bleManager.context = context
								}
							}
							.contextMenu {
								if channel.allPrivateMessages.count > 0 {
									Button(role: .destructive) {
										isPresentingDeleteChannelMessagesConfirm = true
										channelSelection = channel
									} label: {
										Label("Delete Messages", systemImage: "trash")
									}
								}

								Button {
									channel.mute = !channel.mute

									let adminMessageId =  bleManager.saveChannel(
										channel: channel.protoBuf,
										fromUser: node.user!,
										toUser: node.user!
									)

									if adminMessageId > 0 {
										context.refresh(channel, mergeChanges: true)
									}

									do {
										try context.save()
									} catch {
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
								"This conversation will be deleted.",
								isPresented: $isPresentingDeleteChannelMessagesConfirm,
								titleVisibility: .visible
							) {
								Button(role: .destructive) {
									deleteChannelMessages(channel: channelSelection!, context: context)
									context.refresh(myInfo, mergeChanges: true)

									let badge = appState.unreadChannelMessages + appState.unreadDirectMessages
									UNUserNotificationCenter.current().setBadgeCount(badge)

									channelSelection = nil
								} label: {
									Text("delete")
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
					makeUserLink(for: user, lastMessage: lastMessage)
						.contextMenu {
							getContextMenu(for: user, hasMessages: lastMessage != nil)
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
		.headerProminence(.increased)
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
			ChannelMessageList(myInfo: myInfo, channel: channel)
		} label: {
			let mostRecent = channel.allPrivateMessages.last(where: {
				$0.channel == channel.index
			})
			let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0
			let lastMessageTime = Date(
				timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0)))
			)
			let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0

			avatar(for: channel)

			VStack(alignment: .leading) {
				HStack(spacing: 8) {
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

					if channel.allPrivateMessages.count > 0 {
						if lastMessageDay == currentDay {
							Text(lastMessageTime, style: .time )
								.font(.footnote)
								.foregroundColor(.secondary)
						} else if  lastMessageDay == (currentDay - 1) {
							Text("Yesterday")
								.font(.footnote)
								.foregroundColor(.secondary)
						} else if  lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
							Text(dateFormatter.string(from: lastMessageTime))
								.font(.footnote)
								.foregroundColor(.secondary)
						} else if lastMessageDay < (currentDay - 1800) {
							Text(dateFormatter.string(from: lastMessageTime))
								.font(.footnote)
								.foregroundColor(.secondary)
						}
					}
				}

				if channel.allPrivateMessages.count > 0 {
					HStack(alignment: .top) {
						Text("\(mostRecent != nil ? mostRecent!.messagePayload! : "")")
							.lineLimit(3)
							.font(.footnote)
							.foregroundColor(.secondary)
					}
				}
			}
		}
	}

	@ViewBuilder
	private func makeUserLink(for user: UserEntity, lastMessage: MessageEntity?) -> some View {
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
			UserMessageList(user: user)
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

						if let lastMessage {
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

					if let lastMessage {
						Text(lastMessage.messagePayload!)
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
				user.shortName,
				background: getUserColor(for: user),
				size: 64
			)
			.padding([.top, .bottom, .trailing], 12)
			
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
	private func avatar(for channel: ChannelEntity) -> some View {
		ZStack(alignment: .top) {
			Avatar(
				String(channel.index),
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
			return NSPredicate(format: "%K CONTAINS[c] %@", property, searchText)
		}
		
		if !searchText.isEmpty {
			users.nsPredicate = NSCompoundPredicate(type: .or, subpredicates: searchPredicates)
		}
		else {
			users.nsPredicate = nil
		}
	}
	
	private func getLastMessage(for user: UserEntity) -> MessageEntity? {
		return user.messageList?.last
	}
}
