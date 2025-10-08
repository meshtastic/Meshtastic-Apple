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
			try context.save()
			Logger.data.info("📖 [App] All unread messages marked as read.")
			appState.unreadChannelMessages = myInfo.unreadMessages
			context.refresh(myInfo, mergeChanges: true)
		} catch {
			Logger.data.error("Failed to read messages: \(error.localizedDescription, privacy: .public)")
		}
	}
	
	var body: some View {
		ScrollViewReader { scrollView in
			ScrollView {
				LazyVStack {
					ForEach(allPrivateMessages.indices, id: \.self) { index in
						  let message = allPrivateMessages[index]
						  let previousMessage = index > 0 ? allPrivateMessages[index - 1] : nil
						  
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
							  if !message.read {
								  message.read = true
								  // Race condition, sometimes the app doesn't update unread count if we run this too early
								  // So, run it in the main queue after everything saves and stabilizes
								  DispatchQueue.main.async {
									  markMessagesAsRead()
								  }
							  }
						  }
						  .id(redrawTapbacksTrigger)
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
			.onChange(of: messageFieldFocused) {
				if messageFieldFocused {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
						scrollView.scrollTo("bottomAnchor", anchor: .bottom)
					}
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
