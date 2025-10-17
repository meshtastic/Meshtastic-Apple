//
//  UserMessageListUnified.swift
//  Meshtastic
//
//  Alternative implementation using unified selectable text view
//

import SwiftUI
import CoreData
import OSLog
import MeshtasticProtobufs

struct UserMessageListUnified: View {
	
	@EnvironmentObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.managedObjectContext) var context
	@FocusState var messageFieldFocused: Bool
	@ObservedObject var user: UserEntity
	@State private var replyMessageId: Int64 = 0
	@State private var scrollToBottom = false
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
	
	private var allPrivateMessages: [MessageEntity] {
		return user.messageList.compactMap { $0 as MessageEntity }
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
			UnifiedMessageTextView(
				messages: allPrivateMessages,
				preferredPeripheralNum: preferredPeripheralNum,
				scrollToBottom: $scrollToBottom
			)
			.onAppear {
				markMessagesAsRead()
				scrollToBottom = true
			}
			.onChange(of: allPrivateMessages.count) {
				scrollToBottom = true
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
