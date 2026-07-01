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

	/// Sidebar selection binding. Reads/writes the durable, payload-free `router.messagesSection`,
	/// so the bound value always matches a `.channels()` / `.directMessages()` row and the
	/// collapsed `NavigationSplitView` back stack stays intact. The setter only fires on a user tap
	/// (selecting a different section), where we also reset the detail pane so the new section
	/// starts with nothing selected — matching the behavior of a fresh sidebar navigation.
	private var sidebarSelection: Binding<MessagesNavigationState?> {
		Binding(
			get: { self.router.messagesSection },
			set: { newValue in
				self.router.messagesSection = newValue
				self.channelSelection = nil
				self.userSelection = nil
			}
		)
	}

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			List(selection: sidebarSelection) {
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
			switch router.messagesSection {
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
					} else if case .channels = router.messagesSection {
						Text("Select a channel")
					} else if case .directMessages = router.messagesSection {
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
			// Handles the deep link set by `route(url:)` before this view began observing.
			consumeDeepLink(router.messagesState)
		}.onChange(of: router.messagesState) { _, newValue in
			consumeDeepLink(newValue)
		}.onChange(of: router.messagesSection) { _, newValue in
			// A reset (e.g. `popToRoot` on disconnect) nils the section; clear the detail pane to
			// match. Section *changes* between .channels/.directMessages are reset by the sidebar
			// setter and by `consumeDeepLink`, so only the nil case needs handling here.
			if newValue == nil {
				channelSelection = nil
				userSelection = nil
			}
		}
	}

	private func bootstrapNodeNum() {
		let nodeId = Int64(UserDefaults.preferredPeripheralNum)
		if nodeId > 0 && nodeNum == nil {
			nodeNum = nodeId
		}
	}

	/// Resolves a deep-link `messagesState` into the selected conversation, then clears the payload
	/// so it's consumed exactly once. Clearing `router.messagesState` re-fires the `onChange` above
	/// with `nil`, which this guard turns into a no-op — selections are never clobbered. If the
	/// target can't be resolved yet (e.g. channels not loaded on a cold launch) the payload is left
	/// in place so a later `onAppear` can retry instead of silently dropping the deep link.
	private func consumeDeepLink(_ state: MessagesNavigationState?) {
		bootstrapNodeNum()
		guard let state else { return }

		switch state {
		case .channels(channelId: let channelId, messageId: _):
			router.messagesSection = .channels()
			guard let channelId else {
				channelSelection = nil
				userSelection = nil
				break
			}
			guard let channel = node?.myInfo?.channels.first(where: { $0.id == channelId }) else {
				return // Not resolvable yet — keep the payload and retry on the next appear.
			}
			channelSelection = channel
			// Clear the sibling DM selection so the detail pane (which prioritizes
			// channelSelection) can't surface a stale conversation under the Channels section.
			userSelection = nil
		case .directMessages(userNum: let userNum, messageId: _):
			router.messagesSection = .directMessages()
			if let userNum {
				// getUser always resolves (creating a placeholder if needed), so a DM deep link
				// never needs the cold-launch retry that the channel branch does.
				userSelection = getUser(id: userNum, context: context)
			} else {
				userSelection = nil
			}
			// Clear the sibling channel selection: the detail pane prioritizes channelSelection,
			// so a previously-open channel would otherwise mask this DM and show the wrong thread.
			channelSelection = nil
		}

		router.messagesState = nil // Consumed — prevents a re-appear from re-resolving it.
	}
}
