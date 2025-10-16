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
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.managedObjectContext) var context
	@FocusState var messageFieldFocused: Bool
	@ObservedObject var user: UserEntity
	@State private var replyMessageId: Int64 = 0
	@State private var messageToHighlight: Int64 = 0
	@State private var redrawTapbacksTrigger = UUID()
	@State private var scrollPosition: Int64?
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
	
	private var allPrivateMessages: [MessageEntity] {
		// Cast user.messageList to an array for easier indexing and ForEach.
		return user.messageList.compactMap { $0 as MessageEntity }
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
			Logger.data.info("📖 [App] All unread direct messages marked as read for user \(user.num, privacy: .public).")
			appState.unreadDirectMessages = user.unreadMessages
			context.refresh(user, mergeChanges: true)
		} catch {
			Logger.data.error("Failed to read direct messages: \(error.localizedDescription, privacy: .public)")
		}
	}
	
	var body: some View {
		VStack {
			ScrollViewReader { scrollView in
				ScrollView {
					LazyVStack {
						ForEach(allPrivateMessages.indices, id: \.self) { index in
							let message = allPrivateMessages[index]
							let previousMessage = index > 0 ? allPrivateMessages[index - 1] : nil
							
							UserMessageRow(
								message: message,
								allMessages: allPrivateMessages,
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
									markMessagesAsRead()
								}
							}
							.id(redrawTapbacksTrigger)
						}
						// Invisible spacer to detect reaching bottom
						Color.clear
							.frame(height: 1)
							.id("bottomAnchor")
					}
				}
				.scrollPosition(id: $scrollPosition, anchor: .bottom)
				.defaultScrollAnchor(.bottom)
				.scrollDismissesKeyboard(.immediately)
				.onChange(of: messageFieldFocused) {
					if messageFieldFocused {
						withAnimation {
							scrollPosition = nil
						}
					}
				}
				.onChange(of: allPrivateMessages.count) {
					withAnimation {
						scrollPosition = nil
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
