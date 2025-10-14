//
//  ChannelMessageList.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import CoreData
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct ChannelMessageList: View {
	@EnvironmentObject var appState: AppState
	@EnvironmentObject var router: Router
	@Environment(\.scenePhase) var scenePhase
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@FocusState var messageFieldFocused: Bool
	@ObservedObject var myInfo: MyInfoEntity
	@ObservedObject var channel: ChannelEntity
	@State private var replyMessageId: Int64 = 0
	@State private var redrawTapbacksTrigger = UUID()
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
	@State private var messageToHighlight: Int64 = 0
	@FetchRequest private var allPrivateMessages: FetchedResults<MessageEntity>
	@State private var scrollToBottomWorkItem: DispatchWorkItem?

	init(myInfo: MyInfoEntity, channel: ChannelEntity) {
		self.myInfo = myInfo
		self.channel = channel
		
		// Configure fetch request here
		let request: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
		request.sortDescriptors = [
			NSSortDescriptor(keyPath: \MessageEntity.messageTimestamp, ascending: true)
		]
		request.predicate = NSPredicate(
			format: "channel == %ld AND toUser == nil AND isEmoji == false",
			channel.index
		)
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
				Logger.data.info("📖 [App] All unread messages marked as read.")
			}

			appState.unreadChannelMessages = myInfo.unreadMessages
			context.refresh(myInfo, mergeChanges: true)
		} catch {
			Logger.data.error("Failed to read messages: \(error.localizedDescription, privacy: .public)")
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

	private func routerIsShowingThisChannel() -> Bool {
		guard router.navigationState.selectedTab == .messages else { return false }
		return scenePhase == .active
	}

	var body: some View {
		// Cast allPrivateMessages to an array for easier indexing and ForEach.
		let messages: [MessageEntity] = Array(allPrivateMessages)

		// Precompute previous message
		let previousByID: [Int64: MessageEntity?] = {
			var dict = [Int64: MessageEntity?]()
			var prev: MessageEntity?
			for m in messages { dict[m.messageId] = prev; prev = m }
			return dict
		}()

		let lastMessageId: Int64? = messages.last?.messageId

		ScrollViewReader { scrollView in
			ScrollView {
				LazyVStack {
					ForEach(messages, id: \.messageId) { message in
						  let previousMessage: MessageEntity? = previousByID[message.messageId] ?? nil
						  
						  ChannelMessageRow(
							  message: message,
							  allMessages: allPrivateMessages,
							  previousMessage: previousMessage,
							  preferredPeripheralNum: preferredPeripheralNum,
							  channel: channel,
							  replyMessageId: $replyMessageId,
							  messageFieldFocused: $messageFieldFocused,
							  messageToHighlight: $messageToHighlight,
							  scrollView: scrollView,
							  onInteractionComplete: handleInteractionComplete
						  )
						  .onAppear {
							  // Only mark as read if the app is in the foreground
							  let appInForeground = UIApplication.shared.applicationState == .active
							  Logger.data.info("onAppear with read=\(message.read) appInForeground=\(appInForeground)")
							  if !message.read && appInForeground && routerIsShowingThisChannel() {
								  message.read = true
								  LocalNotificationManager().cancelNotificationForMessageId(message.messageId)
								  // Race condition, sometimes the app doesn't update unread count if we run this too early
								  // So, run it in the main queue after everything saves and stabilizes
								  DispatchQueue.main.async {
									  markMessagesAsRead()
								  }
								  debouncedScrollToBottom(scrollView: scrollView, lastMessageId: lastMessageId, delay: 0.1)
							  }
						  }
					}
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
			TextMessageField(
				destination: .channel(channel),
				replyMessageId: $replyMessageId,
				isFocused: $messageFieldFocused
			)
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				HStack {
					CircleText(text: String(channel.index), color: .accentColor, circleSize: 44).fixedSize()
					Text(String(channel.name ?? "Unknown").camelCaseToWords()).font(.headline)
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {
					ConnectedDevice(
						deviceConnected: accessoryManager.isConnected,
						name: accessoryManager.activeConnection?.device.shortName ?? "?",
						mqttProxyConnected: accessoryManager.mqttProxyConnected && (channel.uplinkEnabled || channel.downlinkEnabled),
						mqttUplinkEnabled: channel.uplinkEnabled,
						mqttDownlinkEnabled: channel.downlinkEnabled,
						mqttTopic: accessoryManager.mqttManager.topic
					)
				}
			}
		}
	}
}
