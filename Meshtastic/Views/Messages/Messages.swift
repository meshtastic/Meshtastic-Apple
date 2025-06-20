//
//  Messages.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import CoreData
import OSLog
import TipKit

struct Messages: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@ObservedObject
	var router: Router

	@Binding
	var unreadChannelMessages: Int

	@Binding
	var unreadDirectMessages: Int

	@State var node: NodeInfoEntity?
	@State private var userSelection: UserEntity? // Nothing selected by default.
	@State private var channelSelection: ChannelEntity? // Nothing selected by default.

	@State private var columnVisibility = NavigationSplitViewVisibility.all

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			List(selection: $router.navigationState.messages) {
				NavigationLink(value: MessagesNavigationState.channels()) {
					Label {
						Text("Channels")
							.badge(unreadChannelMessages)
							.font(.title2)
							.padding()
					} icon: {
						Image(systemName: "person.3")
							.symbolRenderingMode(.hierarchical)
							.foregroundColor(.accentColor)
							.font(.title2)
							.padding()
					}

				}
				NavigationLink(value: MessagesNavigationState.directMessages()) {
					Label {
						Text("Direct Messages")
							.badge(unreadDirectMessages)
							.font(.title2)
							.padding()
					} icon: {
						Image(systemName: "person.circle")
							.symbolRenderingMode(.hierarchical)
							.foregroundColor(.accentColor)
							.font(.title2)
							.padding()
					}
				}

				TipView(MessagesTip(), arrowEdge: .top)
					.tipViewStyle(PersistentTip())
			}
			.navigationTitle("Messages")
			.navigationBarTitleDisplayMode(.large)
			.navigationBarItems(leading: MeshtasticLogo())
		} content: {
			switch router.navigationState.messages {
			case .channels(let channelId, let messageId):
				ChannelList(node: $node, channelSelection: $channelSelection)
			case .directMessages(let userNum, let messageId):
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
		}.onChange(of: router.navigationState) {
			setupNavigationState()
		}
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
