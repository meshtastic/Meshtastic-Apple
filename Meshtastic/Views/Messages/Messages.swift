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

struct Messages: View {

	@Environment(\.managedObjectContext) var context
	@Environment(\.colorScheme) private var colorScheme
	@ObservedObject	var router: Router
	@Binding var unreadChannelMessages: Int
	@Binding var unreadDirectMessages: Int
	@State var node: NodeInfoEntity?
	@State private var userSelection: UserEntity? // Nothing selected by default.
	@State private var channelSelection: ChannelEntity? // Nothing selected by default.

	var body: some View {
		Group {
			if #available(iOS 16, *) {
				splitViewBody
			} else {
				legacyBody
			}
		}
		.onChange(of: router.navigationState) {
			setupNavigationState()
		}
	}

	@available(iOS 16, *)
	private var splitViewBody: some View {
		NavigationSplitView {
			listWithSelection
				.listStyle(.plain)
				.navigationTitle("Messages")
				.navigationBarTitleDisplayMode(.large)
				.navigationBarItems(leading: MeshtasticLogo())
		} content: {
			switch router.navigationState.messages {
			case .channels:
				ChannelList(node: $node, channelSelection: $channelSelection)
			case .directMessages:
				UserList(node: $node, userSelection: $userSelection)
			case nil:
				Text("Select a conversation type")
			}
		} detail: {
			if let myInfo = node?.myInfo, let channelSelection {
				ChannelMessageList(myInfo: myInfo, channel: channelSelection)
			} else if let userSelection {
				UserMessageList(user: userSelection)
			} else if case .channels = router.navigationState.messages {
				Text("Select a channel")
			} else if case .directMessages = router.navigationState.messages {
				Text("Select a conversation")
			}
		}
	}

	private var legacyBody: some View {
		NBNavigationStack(
			path: Binding<[MessagesNavigationState]>(
				get: {
					if let state = router.navigationState.messages {
						return [state]
					}
					return []
				},
				set: { newPath in
					router.navigationState.messages = newPath.last
				}
			)
		) {
			listWithoutSelection
				.listStyle(.plain)
				.navigationTitle("Messages")
				.navigationBarTitleDisplayMode(.large)
				.navigationBarItems(leading: MeshtasticLogo())
		}
		.nbNavigationDestination(for: MessagesNavigationState.self) { destination in
			switch destination {
			case .channels:
				ChannelList(node: $node, channelSelection: $channelSelection)
			case .directMessages:
				UserList(node: $node, userSelection: $userSelection)
			}
		}
	}

	@available(iOS 16, *)
	private var listWithSelection: some View {
		List(selection: $router.navigationState.messages) {
			conversationRows
		}
	}

	private var listWithoutSelection: some View {
		List {
			conversationRows
		}
	}

	@ViewBuilder
	private var conversationRows: some View {
		NBNavigationLink(value: MessagesNavigationState.channels()) {
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
		.alignmentGuide(.listRowSeparatorLeading) {
			$0[.leading]
		}
		NBNavigationLink(value: MessagesNavigationState.directMessages()) {
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
		.alignmentGuide(.listRowSeparatorLeading) {
			$0[.leading]
		}
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
	}
}
