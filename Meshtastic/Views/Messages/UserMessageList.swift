//
//  UserMessageList.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import SwiftUI
import CoreData
import OSLog
import MeshtasticProtobufs // Added to ensure RoutingError is accessible if needed

struct UserMessageList: View {
	@EnvironmentObject var appState: AppState
	@EnvironmentObject var router: Router
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.scenePhase) var scenePhase
	@Environment(\.managedObjectContext) var context
	@FocusState var messageFieldFocused: Bool
	@ObservedObject var user: UserEntity
	@State private var replyMessageId: Int64 = 0
	@State private var messageToHighlight: Int64 = 0
	@State private var redrawTapbacksTrigger = UUID()
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
	@FetchRequest private var allPrivateMessages: FetchedResults<MessageEntity>
	@State private var scrollToBottomWorkItem: DispatchWorkItem?

	init(user: UserEntity) {
		self.user = user

		// Configure fetch request here
		let request: NSFetchRequest<MessageEntity> = user.messageFetchRequest
		_allPrivateMessages = FetchRequest(fetchRequest: request)
	}

	func handleInteractionComplete() {
		markMessagesAsRead()
		redrawTapbacksTrigger = UUID()
	}

	func markMessagesAsRead() {
		do {
			for unreadMessage in allPrivateMessages.filter({ !$0.read }) {
				unreadMessage.read = true
			}

			if context.hasChanges {
				try context.save()
				Logger.data.info("📖 [App] All unread direct messages marked as read for user \(user.num, privacy: .public).")
			}

			if let connectedPeripheralNum = accessoryManager.activeDeviceNum,
			   let connectedNode = getNodeInfo(id: connectedPeripheralNum, context: context),
			   let connectedUser = connectedNode.user {
				appState.unreadDirectMessages = connectedUser.unreadMessages(context: context, skipLastMessageCheck: true) // skipLastMessageCheck=true because we don't update lastMessage on our own connected node
			}

			context.refresh(user, mergeChanges: true)
		} catch {
			Logger.data.error("Failed to read direct messages: \(error.localizedDescription, privacy: .public)")
		}
	}

	func debouncedScrollToBottom(scrollView: ScrollViewProxy, lastMessageId: Int64?, delay: TimeInterval = 0.1) {
		scrollToBottomWorkItem?.cancel()

		let scrollTarget: AnyHashable = lastMessageId != nil ? lastMessageId : "bottomAnchor"
		let work = DispatchWorkItem {
			scrollView.scrollTo(scrollTarget, anchor: .bottom)
		}
		scrollToBottomWorkItem = work
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
	}

	private func routerIsShowingThisUser() -> Bool {
		guard router.navigationState.selectedTab == .messages else { return false }
		return scenePhase == .active
	}

	var body: some View {
		// Cast user.messageList to an array for easier indexing and ForEach.
		let messages: [MessageEntity] = Array(allPrivateMessages)

		// Precompute previous message
		let previousByID: [Int64: MessageEntity?] = {
			var dict = [Int64: MessageEntity?]()
			var prev: MessageEntity?
			for m in messages { dict[m.messageId] = prev; prev = m }
			return dict
		}()

		let lastMessageId: Int64? = messages.last?.messageId

		VStack {
			ScrollViewReader { scrollView in
				ScrollView {
					LazyVStack {
						ForEach(messages, id: \.messageId) { message in
							let previousMessage: MessageEntity? = previousByID[message.messageId] ?? nil
							
							UserMessageRow(
								message: message,
								allMessages: messages,
								previousMessage: previousMessage,
								preferredPeripheralNum: preferredPeripheralNum,
								user: user,
								replyMessageId: $replyMessageId,
								messageFieldFocused: $messageFieldFocused,
								messageToHighlight: $messageToHighlight,
								scrollView: scrollView,
								onInteractionComplete: handleInteractionComplete
							)
							.onAppear {
								// Only mark as read if the app is in the foreground
								if !message.read && UIApplication.shared.applicationState == .active {
									message.read = true
									LocalNotificationManager().cancelNotificationForMessageId(message.messageId)
									// Race condition, sometimes the app doesn't update unread count if we run this too early
									// So, run it in the main queue after everything saves and stabilizes
									DispatchQueue.main.async {
										markMessagesAsRead()
										scrollView.scrollTo("bottomAnchor", anchor: .bottom)
									}
								}
							}
						}
						// Invisible spacer to detect reaching bottom
						Color.clear
							.frame(height: 1)
							.id("bottomAnchor")
					}
				}
				.defaultScrollAnchor(.bottom)
				.defaultScrollAnchorTopAlignment()
				.defaultScrollAnchorBottomSizeChanges()
				.scrollDismissesKeyboard(.immediately)
				.onFirstAppear {
					debouncedScrollToBottom(scrollView: scrollView, lastMessageId: lastMessageId, delay: 0.1)
				}
				.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
					// Keyboard is about to appear: keyboard show animation hasn't quite started yet.
					// Schedule an immediate scroll to the bottom message by its messageId, in order to force LazyVStack to render that cell if it isn't rendered already
					debouncedScrollToBottom(scrollView: scrollView, lastMessageId: lastMessageId, delay: 0.0)
				}
				.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
					// Keyboard is fully visible.
					// Scroll after the keyboard is fully showing, with a short delay to allow things to settle (TextMessageField height update, for example)
					debouncedScrollToBottom(scrollView: scrollView, lastMessageId: lastMessageId, delay: 0.1)
				}
				.onChange(of: messageFieldFocused) {
					if messageFieldFocused {
						// macOS doesn't have keyboard show animation, but we still want to scroll to the bottom.
						debouncedScrollToBottom(scrollView: scrollView, lastMessageId: lastMessageId, delay: 0.0)
					 }
				}
			}
			TextMessageField(
				destination: .user(user),
				replyMessageId: $replyMessageId,
				isFocused: $messageFieldFocused
			)
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			if !user.keyMatch {
				ToolbarItem(placement: .bottomBar) {
					VStack {
						HStack {
							Image(systemName: "key.slash.fill")
								.symbolRenderingMode(.multicolor)
								.foregroundStyle(.red)
								.font(.caption2)
							Text("There is an issue with this contact's public key.")
								.foregroundStyle(.secondary)
								.font(.caption2)
						}
						Link(destination: URL(string: "meshtastic:///nodes?nodenum=\(user.num)")!) {
							Text("Details...")
								.font(.caption2)
								.offset(y: -15)
						}
					}
					.offset(y: -15)
				}
			}
			ToolbarItem(placement: .principal) {
				HStack {
					CircleText(text: user.shortName ?? "?", color: Color(UIColor(hex: UInt32(user.num))), circleSize: 44)
					Text(user.longName ?? "Unknown").font(.headline)
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {
					ConnectedDevice(
						deviceConnected: accessoryManager.isConnected,
						name: accessoryManager.activeConnection?.device.shortName ?? "?")
				}
			}
		}
	}
}
