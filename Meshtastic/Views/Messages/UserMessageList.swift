//
//  UserMessageList.swift
//  MeshtasticApple
//
//  Migrated to use ExyteChat library with full functionality
//

import SwiftUI
import CoreData
import OSLog
import MeshtasticProtobufs
import ExyteChat
import LinkPresentation

private enum ChatMessageAction: MessageMenuAction {
	case reply
	case copy
	case info
	case tapback
	
	func title() -> String {
		switch self {
		case .reply: return "Reply"
		case .copy: return "Copy"
		case .info: return "Info"
		case .tapback: return "Tapback"
		}
	}
	
	func icon() -> Image {
		switch self {
		case .reply: return Image(systemName: "arrowshape.turn.up.left")
		case .copy: return Image(systemName: "doc.on.doc")
		case .info: return Image(systemName: "info.circle")
		case .tapback: return Image(systemName: "hand.thumbsup.fill")
		}
	}
}

private extension Array where Element == MessageEntity {
	func convertToChatMessages(currentUserNum: Int64, preferredPeripheralNum: Int) -> [ExyteChat.Message] {
		return self.map { entity in
			let messageId = String(entity.messageId)
			let fromUserEntity = entity.fromUser
			
			let isCurrentUser: Bool
			if let fromUser = fromUserEntity {
				isCurrentUser = fromUser.num == currentUserNum
			} else {
				isCurrentUser = false
			}
			
			let user: ExyteChat.User
			if let fromUser = fromUserEntity {
				user = ExyteChat.User(
					id: String(fromUser.num),
					name: fromUser.longName ?? fromUser.shortName ?? "Unknown",
					avatarURL: nil,
					isCurrentUser: isCurrentUser
				)
			} else {
				user = ExyteChat.User(
					id: "unknown",
					name: "Unknown",
					avatarURL: nil,
					isCurrentUser: isCurrentUser
				)
			}
			
			return ExyteChat.Message(
				id: messageId,
				user: user,
				status: nil,
				createdAt: entity.timestamp,
				text: entity.messagePayload ?? "",
				attachments: [],
				replyMessage: nil
			)
		}
	}
}

struct UserMessageList: View {
	@EnvironmentObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.scenePhase) var scenePhase
	@Environment(\.managedObjectContext) var context
	@FocusState var messageFieldFocused: Bool
	@ObservedObject var user: UserEntity
	@State private var replyMessageId: Int64 = 0
	@State private var messageToHighlight: Int64 = 0
	@State private var redrawTapbacksTrigger = UUID()
	@State private var selectedMessageForDetails: MessageEntity?
	@State private var showingMessageDetails = false
	@State private var showingTapbackInput = false
	@State private var tapbackMessage: MessageEntity?
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
	@FetchRequest private var allPrivateMessages: FetchedResults<MessageEntity>
	
	init(user: UserEntity) {
		self.user = user
		
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
			try context.save()
			Logger.data.info("📖 [App] All unread direct messages marked as read for user \(user.num, privacy: .public).")
			
			if let connectedPeripheralNum = accessoryManager.activeDeviceNum,
			   let connectedNode = getNodeInfo(id: connectedPeripheralNum, context: context),
			   let connectedUser = connectedNode.user {
				appState.unreadDirectMessages = connectedUser.unreadMessages(context: context, skipLastMessageCheck: true)
			}
			
			context.refresh(user, mergeChanges: true)
		} catch {
			Logger.data.error("Failed to read direct messages: \(error.localizedDescription, privacy: .public)")
		}
	}
	
	func markMessageAsRead(_ message: MessageEntity) {
		if !message.read {
			message.read = true
			do {
				try context.save()
				if let connectedPeripheralNum = accessoryManager.activeDeviceNum,
				   let connectedNode = getNodeInfo(id: connectedPeripheralNum, context: context),
				   let connectedUser = connectedNode.user {
					appState.unreadDirectMessages = connectedUser.unreadMessages(context: context, skipLastMessageCheck: true)
				}
			} catch {
				Logger.data.error("Failed to mark message as read: \(error.localizedDescription, privacy: .public)")
			}
		}
	}
	
	func retryMessage(_ message: MessageEntity) {
		Task {
			do {
				try await accessoryManager.sendMessage(
					message: message.messagePayload ?? "",
					toUserNum: user.num,
					channel: 0,
					isEmoji: false,
					replyID: message.replyID
				)
			} catch {
				Logger.mesh.error("Failed to retry message: \(error.localizedDescription, privacy: .public)")
			}
		}
	}
	
	func sendTapback(_ emoji: String, to message: MessageEntity) {
		Task {
			do {
				try await accessoryManager.sendMessage(
					message: emoji,
					toUserNum: message.fromUser?.num ?? user.num,
					channel: 0,
					isEmoji: true,
					replyID: message.messageId
				)
				await MainActor.run {
					context.refresh(user, mergeChanges: true)
				}
			} catch {
				Logger.services.warning("Failed to send tapback.")
			}
		}
	}
	
	func copyMessage(_ text: String) {
		UIPasteboard.general.string = text
	}
	
	private var currentUserNum: Int64 {
		Int64(preferredPeripheralNum)
	}
	
	private var chatMessages: [Message] {
		let entities = Array(allPrivateMessages)
		return entities.convertToChatMessages(
			currentUserNum: currentUserNum,
			preferredPeripheralNum: preferredPeripheralNum
		)
	}
	
	private func sendMessage(draft: DraftMessage) {
		guard !draft.text.isEmpty else { return }
		
		Task {
			do {
				try await accessoryManager.sendMessage(
					message: draft.text,
					toUserNum: user.num,
					channel: 0,
					isEmoji: false,
					replyID: replyMessageId
				)
				replyMessageId = 0
			} catch {
				Logger.mesh.info("Error sending message")
			}
		}
	}
	
	var body: some View {
		let messages = chatMessages
		
		return ChatView(
			messages: messages,
			chatType: .conversation,
			replyMode: .quote
		) { draft in
			sendMessage(draft: draft)
		}
		.messageUseMarkdown(true)
		.setAvailableInputs([.text])
		.showDateHeaders(true)
		.isScrollEnabled(true)
		.keyboardDismissMode(.interactive)
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
		.sheet(isPresented: $showingTapbackInput) {
			if let msg = tapbackMessage {
				TapbackPickerViewDM(message: msg) { emoji in
					sendTapback(emoji, to: msg)
				}
			}
		}
		.sheet(isPresented: $showingMessageDetails) {
			if let msg = selectedMessageForDetails {
				MessageDetailsView(message: msg, destination: .user(user))
			}
		}
	}
}

struct CustomMessageCell: View {
	let message: Message
	let currentUserNum: Int64
	@Binding var replyMessageId: Int64
	@FocusState.Binding var messageFieldFocused: Bool
	let destination: MessageDestination
	let allMessages: [MessageEntity]
	let onRead: (MessageEntity) -> Void
	let onRetry: (MessageEntity) -> Void
	
	@Environment(\.managedObjectContext) var context
	
	private var isCurrentUser: Bool {
		message.user.isCurrentUser
	}
	
	private var messageEntity: MessageEntity? {
		allMessages.first { String($0.messageId) == message.id }
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .bottom) {
				if isCurrentUser { Spacer(minLength: 50) }
				
				if !isCurrentUser {
					if let msgEntity = messageEntity {
						CircleText(
							text: msgEntity.fromUser?.shortName ?? "?",
							color: Color(UIColor(hex: UInt32(msgEntity.fromUser?.num ?? 0))),
							circleSize: 50
						)
						.onTapGesture(count: 2) {
							if let nodeNum = msgEntity.fromUser?.num {
								// Navigate to node detail
							}
						}
						.onAppear {
							onRead(msgEntity)
						}
						.padding(.all, 5)
						.offset(y: -7)
					} else {
						CircleText(text: "?", color: .gray, circleSize: 50)
							.padding(.all, 5)
							.offset(y: -7)
					}
				}
				
				VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 0) {
					if !isCurrentUser, let msgEntity = messageEntity {
						Text("\(msgEntity.fromUser?.longName ?? "Unknown") (\(msgEntity.fromUser?.userId ?? "?"))")
							.font(.caption).foregroundColor(.gray)
							.padding(.bottom, 2)
					}
					
					HStack(alignment: .bottom) {
						Text(LocalizedStringKey(message.text))
							.padding(.vertical, 10)
							.padding(.horizontal, 8)
							.foregroundColor(.white)
							.background(isCurrentUser ? Color.accentColor : Color.gray)
							.cornerRadius(15)
						
						if isCurrentUser, let msgEntity = messageEntity {
							if msgEntity.canRetry || (msgEntity.receivedACK && !msgEntity.realACK) {
								Button {
									onRetry(msgEntity)
								} label: {
									Image(systemName: "exclamationmark.circle.fill")
										.foregroundColor(.red)
								}
							}
						}
					}
					
					if let msgEntity = messageEntity {
						DMMessageStatusView(message: msgEntity)
						
						TapbackResponsesViewDM(message: msgEntity) {
							onRead(msgEntity)
						}
					}
				}
				.padding(.bottom)
				
				if !isCurrentUser { Spacer(minLength: 50) }
			}
			.padding([.leading, .trailing])
			.frame(maxWidth: .infinity)
		}
		.id(message.id)
	}
}

struct DMMessageStatusView: View {
	@ObservedObject var message: MessageEntity
	
	var body: some View {
		HStack {
			if isCurrentUser {
				let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
				if message.receivedACK {
					HStack(spacing: 2) {
						Image(systemName: "checkmark.circle.fill")
							.font(.caption2)
							.foregroundStyle(.gray)
						Text(ackErrorVal?.display ?? "Sent")
							.font(.caption2)
							.foregroundStyle(.gray)
					}
				} else if message.ackError == 0 {
					HStack(spacing: 2) {
						Image(systemName: "clock.fill")
							.font(.caption2)
							.foregroundColor(.yellow)
						Text("Waiting to be acknowledged. . .")
							.font(.caption2)
							.foregroundColor(.yellow)
					}
				} else if message.ackError > 0 {
					HStack(spacing: 2) {
						Image(systemName: "exclamationmark.circle.fill")
							.font(.caption2)
							.foregroundColor(.red)
						Text(ackErrorVal?.display ?? "Error")
							.font(.caption2)
							.foregroundColor(.red)
					}
				}
			}
		}
		.padding(.top, 2)
	}
	
	private var isCurrentUser: Bool {
		Int64(UserDefaults.preferredPeripheralNum) == message.fromUser?.num
	}
}

struct TapbackResponsesViewDM: View {
	@ObservedObject var message: MessageEntity
	let onRead: () -> Void
	
	@Environment(\.managedObjectContext) var context
	
	var body: some View {
		let tapbacks = message.tapbacks
		if !tapbacks.isEmpty {
			HStack(spacing: 4) {
				ForEach(tapbacks, id: \.messageId) { tapback in
					VStack {
						if let image = tapback.messagePayload?.image(fontSize: 16) {
							Image(uiImage: image)
								.font(.caption)
						}
						Text("\(tapback.fromUser?.shortName ?? "?")")
							.font(.caption2)
							.foregroundColor(.gray)
					}
					.onAppear {
						if !tapback.read {
							tapback.read = true
							onRead()
							try? context.save()
						}
					}
				}
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(
				RoundedRectangle(cornerRadius: 12)
					.fill(Color(.systemGray6)))
			.padding(.top, 2)
		}
	}
}

struct TapbackPickerViewDM: View {
	@Environment(\.dismiss) var dismiss
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	let message: MessageEntity
	let onTapbackSelected: (String) -> Void
	
	@State private var emojiText: String = ""
	
	var body: some View {
		NavigationView {
			VStack(spacing: 0) {
				TextField("Tap to enter emoji", text: $emojiText)
					.keyboardType(.emoji)
					.frame(height: 50)
					.padding(.horizontal)
					.background(
						RoundedRectangle(cornerRadius: 10)
							.strokeBorder(.tertiary, lineWidth: 1)
					)
					.background(
						RoundedRectangle(cornerRadius: 10)
							.fill(Color(.systemBackground))
					)
					.padding(.horizontal)
					.padding(.top, 8)
					.onChange(of: emojiText) { oldValue, newValue in
						if !newValue.isEmpty, let firstEmoji = extractFirstEmoji(from: newValue) {
							onTapbackSelected(firstEmoji)
							emojiText = ""
							dismiss()
						}
					}
				
				Text("Type an emoji to send as a tapback")
					.font(.caption)
					.foregroundColor(.secondary)
					.padding(.top, 8)
			}
			.navigationTitle("Tapback")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button("Cancel") {
						dismiss()
					}
				}
			}
		}
		.presentationDetents([.height(150)])
	}
	
	private func extractFirstEmoji(from string: String) -> String? {
		guard !string.isEmpty else { return nil }
		
		let firstChar = string[string.startIndex]
		
		if firstChar.isEmoji {
			var emojiEnd = string.index(after: string.startIndex)
			
			while emojiEnd < string.endIndex {
				let nextChar = string[emojiEnd]
				if let scalar = nextChar.unicodeScalars.first,
				   (scalar.properties.isVariationSelector ||
					scalar.value == 0xFE0F ||
					(scalar.value >= 0x1F3FB && scalar.value <= 0x1F3FF) ||
					scalar.value == 0x200D) {
					emojiEnd = string.index(after: emojiEnd)
				} else if nextChar.isEmoji {
					emojiEnd = string.index(after: emojiEnd)
				} else {
					break
				}
			}
			
			return String(string[string.startIndex..<emojiEnd])
		}
		
		return nil
	}
}
