//
//  Messages.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import SwiftData
import OSLog
import TipKit

struct Messages: View {

	@Environment(\.modelContext) private var context
	@Environment(\.colorScheme) private var colorScheme
	@ObservedObject	var router: Router
	@Binding var unreadChannelMessages: Int
	@Binding var unreadDirectMessages: Int
	/// Store the connected node's `num`, NOT the `NodeInfoEntity` itself, and resolve the object
	/// from the live context every render (see `node`). Caching the SwiftData model here traps
	/// ("destroyed by ModelContext.reset") when the container is recreated (data clear / node
	/// switch) while this view still reads `node?.myInfo`; a fresh fetch returns nil safely.
	@State private var nodeNum: Int64?
	@State private var userSelection: UserEntity? // Nothing selected by default.
	@State private var channelSelection: ChannelEntity? // Nothing selected by default.

	@State private var columnVisibility = NavigationSplitViewVisibility.all

	/// Resolves the connected node from the current context on each access. Never cached, so it
	/// can't outlive a container recreation. `getNodeInfo` is a `try?` fetch and returns nil if
	/// the store is mid-reset.
	private var node: NodeInfoEntity? {
		guard let nodeNum else { return nil }
		return getNodeInfo(id: nodeNum, context: context)
	}

	/// Binding handed to ChannelList/UserList. The getter resolves `node` from the live context on
	/// every read (never a captured/cached object), so the retained closure can't read a reset
	/// NodeInfoEntity if a container recreation happens before this view re-renders.
	private var nodeBinding: Binding<NodeInfoEntity?> {
		Binding(get: { self.node }, set: { self.nodeNum = $0?.num })
	}

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			List(selection: $router.messagesState) {
				NavigationLink(value: MessagesNavigationState.channels()) {
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
				NavigationLink(value: MessagesNavigationState.directMessages()) {
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
				TipView(MessagesTip(), arrowEdge: .top)
					.tipViewStyle(PersistentTipStyle())
					.listRowSeparator(.hidden)
				Spacer()
					.listRowSeparator(.hidden)
			}
			.listStyle(.plain)
			.navigationTitle("Messages")
			.navigationBarTitleDisplayMode(.large)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					MeshtasticLogo()
				}
			}
		} content: {
			switch router.messagesState {
			case .channels:
				ChannelList(node: nodeBinding, channelSelection: $channelSelection)
					// Removed navigationTitle and navigationBarTitleDisplayMode here.
					// ChannelList.swift now handles this within its own NavigationStack.
			case .directMessages:
				UserList(node: nodeBinding, userSelection: $userSelection)
					// Removed navigationTitle here. UserList will handle this.
			case nil:
				Text("Select a conversation type")
			}
		} detail: {
			NavigationStack {
				Group {
					if let myInfo = node?.myInfo, let channelSelection {
						ChannelMessageList(myInfo: myInfo, channel: channelSelection)
					} else if let userSelection {
						UserMessageList(user: userSelection)
					} else if case .channels = router.messagesState {
						Text("Select a channel")
					} else if case .directMessages = router.messagesState {
						Text("Select a conversation")
					}
				}
				.navigationDestination(for: Int64.self) { nodeNum in
					if let node = getNodeInfo(id: nodeNum, context: context) {
						NodeDetail(node: node)
					}
				}
			}
		}.onAppear {
			setupNavigationState()
		}.onChange(of: router.messagesState) {
			setupNavigationState()
		}
	}

	private func setupNavigationState() {
		let nodeId = Int64(UserDefaults.preferredPeripheralNum)
		if nodeId > 0 && nodeNum == nil {
			nodeNum = nodeId
		}

		guard let state = router.messagesState else {
			channelSelection = nil
			userSelection = nil
			return
		}

		switch state {
		case .channels(channelId: let channelId, messageId: _):
			if let channelId {
				channelSelection = node?.myInfo?.channels.first { $0.id == channelId }
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
