//
//  Messages.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import CoreData
import OSLog
#if canImport(TipKit)
import TipKit
#endif

struct Messages: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@ObservedObject
	var router: Router

	@Binding
	var unreadChannelMessages: Int

	@Binding
	var unreadDirectMessages: Int

	// Aliases the navigation state for the NavigationSplitView sidebar selection
	private var messagesSelection: Binding<MessagesNavigationState?> {
		Binding(
			get: {
				guard case .messages(let state) = router.navigationState else {
					return nil
				}
				return state
			},
			set: { newValue in
				router.navigationState = .messages(newValue)
			}
		)
	}

	@State var node: NodeInfoEntity?
	@State private var userSelection: UserEntity? // Nothing selected by default.
	@State private var channelSelection: ChannelEntity? // Nothing selected by default.

	@State private var columnVisibility = NavigationSplitViewVisibility.all

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			List(selection: messagesSelection) {
				NavigationLink(value: MessagesNavigationState.channels()) {
					Label {
						Text("channels")
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
						Text("direct.messages")
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

				if #available(iOS 17.0, macOS 14.0, *) {
					TipView(MessagesTip(), arrowEdge: .top)
				}
			}
			.navigationTitle("messages")
			.navigationBarTitleDisplayMode(.large)
			.navigationBarItems(leading: MeshtasticLogo())
		} content: {
			if case .messages(.channels) = router.navigationState {
				ChannelList(node: $node, channelSelection: $channelSelection)
			} else if case .messages(.directMessages) = router.navigationState {
				UserList(node: $node, userSelection: $userSelection)
			} else if case .messages(nil) = router.navigationState {
				Text("Select a conversation type")
			}
		} detail: {
			if let myInfo = node?.myInfo, let channelSelection {
				ChannelMessageList(myInfo: myInfo, channel: channelSelection)
			} else if let userSelection {
				UserMessageList(user: userSelection)
			} else if case .messages(.channels) = router.navigationState {
				Text("Select a channel")
			} else if case .messages(.directMessages) = router.navigationState {
				Text("Select a conversation")
			}
		}.onChange(of: router.navigationState) { _ in
			setupNavigationState()
		}
	}

	private func setupNavigationState() {
		let nodeId = Int64(UserDefaults.preferredPeripheralNum)
		if nodeId > 0 {
			node = getNodeInfo(id: nodeId, context: context)
		}

		guard case .messages(let state) = router.navigationState else {
			return
		}

		guard let state else {
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
