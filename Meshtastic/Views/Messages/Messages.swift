//
//  Messages.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import NavigationBackport
import CoreData
import OSLog
#if canImport(TipKit)
import TipKit
#endif

private enum MessagesRoute: Hashable {
	case channelsList
	case channel(channelId: Int32, messageId: Int64?)
	case directMessagesList
	case user(userNum: Int64, messageId: Int64?)
}

struct Messages: View {

	@Environment(\.managedObjectContext) var context
	@Environment(\.colorScheme) private var colorScheme
	@ObservedObject	var router: Router
	@Binding var unreadChannelMessages: Int
	@Binding var unreadDirectMessages: Int
	@State var node: NodeInfoEntity?
	@State private var userSelection: UserEntity? // Nothing selected by default.
	@State private var channelSelection: ChannelEntity? // Nothing selected by default.
	@State private var navigationPath: [MessagesRoute] = []

	var body: some View {
		NBNavigationStack(path: $navigationPath) {
			listWithoutSelection
				.listStyle(.plain)
				.navigationTitle("Messages")
				.navigationBarTitleDisplayMode(.large)
				.navigationBarItems(leading: MeshtasticLogo())
				.nbNavigationDestination(for: MessagesRoute.self) { destination in
					switch destination {
					case .channelsList:
						ChannelList(
							node: $node,
							channelSelection: $channelSelection,
							onChannelSelected: handleChannelSelection
						)
					case .channel(channelId: let channelId, messageId: _):
						if let myInfo = node?.myInfo, let channel = channel(for: channelId) {
							ChannelMessageList(myInfo: myInfo, channel: channel)
						} else {
							Text("Select a channel")
						}
					case .directMessagesList:
						UserList(
							node: $node,
							userSelection: $userSelection,
							onUserSelected: handleUserSelection
						)
					case .user(userNum: let userNum, messageId: _):
						if let userSelection, userSelection.num == userNum {
							UserMessageList(user: userSelection)
						} else {
							Text("Select a conversation")
						}
					}
				}
		}
		.onAppear {
			setupNavigationState()
			syncNavigationPathWithRouter()
		}
		.onChange(of: router.navigationState.messages) { _ in
			syncNavigationPathWithRouter()
		}
		.onChange(of: navigationPath) { newPath in
			let targetState = navigationState(for: newPath)
			if router.navigationState.messages != targetState {
				router.navigationState.messages = targetState
			}
		}
		.backport.onChange(of: router.navigationState) { _, _ in
			setupNavigationState()
		}
	}

	private var listWithoutSelection: some View {
		List {
			conversationRows
		}
	}

	@ViewBuilder
	private var conversationRows: some View {
		NBNavigationLink(value: MessagesRoute.channelsList) {
			Spacer()
			Label {
				Text("Channels")
					.badge(unreadChannelMessages)
					.font(.title2)
					.padding()
			} icon: {
				Image(systemName: "person.2")
					.symbolRenderingMode(.hierarchical)
					.foregroundColor(.accentColor)
					.font(.title2)
					.padding()
			}
		}
		.backport.leadingListRowSeparatorAligned()
		NBNavigationLink(value: MessagesRoute.directMessagesList) {
			Spacer()
			Label {
				Text("Direct Messages")
					.badge(unreadDirectMessages)
					.font(.title2)
					.padding()
			} icon: {
				Image(systemName: "person")
					.symbolRenderingMode(.hierarchical)
					.foregroundColor(.accentColor)
					.font(.title2)
					.padding()
			}
		}
		.backport.leadingListRowSeparatorAligned()
		Spacer()
		if #available(iOS 17, *) {
			TipView(MessagesTip(), arrowEdge: .top)
				.tipViewStyle(PersistentTip())
				.listRowSeparator(.hidden)
		}
		Spacer()
			.listRowSeparator(.hidden)
	}

	private func setupNavigationState() {
		let nodeId = Int64(UserDefaults.preferredPeripheralNum)
		if nodeId > 0 {
			node = getNodeInfo(id: nodeId, context: context)
		}

		guard let state = router.navigationState.messages else {
			channelSelection = nil
			userSelection = nil
			return
		}

		switch state {
		case .channels(channelId: let channelId, messageId: _):
			if let channelId {
				channelSelection = node?.myInfo?.channels?.first(where: { channel in
					guard let channel = channel as? ChannelEntity else { return false }
					return channel.id == channelId
				}) as? ChannelEntity
			} else {
				channelSelection = nil
				userSelection = nil
			}
		case .directMessages(userNum: let userNum, messageId: _):
			if let userNum {
				userSelection = getUser(id: userNum, context: context)
			} else {
				channelSelection = nil
				userSelection = nil
			}
		}

		syncNavigationPathWithRouter()
	}

	private func handleChannelSelection(_ channel: ChannelEntity) {
		let channelId = channel.id
		channelSelection = channel
		let newPath: [MessagesRoute] = [
			.channelsList,
			.channel(channelId: channelId, messageId: nil)
		]
		if navigationPath != newPath {
			navigationPath = newPath
		}
	}

	private func handleUserSelection(_ user: UserEntity) {
		let userNum = user.num
		userSelection = user
		let newPath: [MessagesRoute] = [
			.directMessagesList,
			.user(userNum: userNum, messageId: nil)
		]
		if navigationPath != newPath {
			navigationPath = newPath
		}
	}

	private func syncNavigationPathWithRouter() {
		let targetPath = navigationPath(for: router.navigationState.messages)
		if navigationPath != targetPath {
			navigationPath = targetPath
		}
	}

	private func navigationPath(for state: MessagesNavigationState?) -> [MessagesRoute] {
		guard let state else { return [] }
		switch state {
		case .channels(channelId: let channelId, messageId: let messageId):
			if let channelId {
				return [.channelsList, .channel(channelId: channelId, messageId: messageId)]
			} else {
				return [.channelsList]
			}
		case .directMessages(userNum: let userNum, messageId: let messageId):
			if let userNum {
				return [.directMessagesList, .user(userNum: userNum, messageId: messageId)]
			} else {
				return [.directMessagesList]
			}
		}
	}

	private func navigationState(for path: [MessagesRoute]) -> MessagesNavigationState? {
		guard let last = path.last else { return nil }
		switch last {
		case .channelsList:
			return .channels()
		case .channel(channelId: let channelId, messageId: let messageId):
			return .channels(channelId: channelId, messageId: messageId)
		case .directMessagesList:
			return .directMessages()
		case .user(userNum: let userNum, messageId: let messageId):
			return .directMessages(userNum: userNum, messageId: messageId)
		}
	}

	private func channel(for channelId: Int32) -> ChannelEntity? {
		if let channelSelection, channelSelection.id == channelId {
			return channelSelection
		}
		if let channels = node?.myInfo?.channels as? Set<ChannelEntity> {
			return channels.first { $0.id == channelId }
		}
		if let orderedChannels = node?.myInfo?.channels as? NSOrderedSet {
			return orderedChannels.array.compactMap { $0 as? ChannelEntity }.first { $0.id == channelId }
		}
		return nil
	}
}
