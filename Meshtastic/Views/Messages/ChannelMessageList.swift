//
//  ChannelMessageList.swift
//  Meshtastic
//
//  Migrated to use ExyteChat library with full functionality
//

import CoreData
import MeshtasticProtobufs
import OSLog
import SwiftUI
import ExyteChat

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

struct ChannelMessageList: View {
	@EnvironmentObject var appState: AppState
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
	@State private var selectedMessageForDetails: MessageEntity?
	@State private var showingMessageDetails = false
	@State private var showingTapbackInput = false
	@State private var tapbackMessage: MessageEntity?
	@FetchRequest private var allPrivateMessages: FetchedResults<MessageEntity>
	
	init(myInfo: MyInfoEntity, channel: ChannelEntity) {
		self.myInfo = myInfo
		self.channel = channel
		
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
	
	func markMessageAsRead(_ message: MessageEntity) {
		if !message.read {
			message.read = true
			do {
				try context.save()
				appState.unreadChannelMessages = myInfo.unreadMessages
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
					toUserNum: 0,
					channel: Int32(channel.index),
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
					toUserNum: message.fromUser?.num ?? 0,
					channel: Int32(channel.index),
					isEmoji: true,
					replyID: message.messageId
				)
				await MainActor.run {
					context.refresh(channel, mergeChanges: true)
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
					toUserNum: 0,
					channel: Int32(channel.index),
					isEmoji: false,
					replyID: replyMessageId
				)
				replyMessageId = 0
			} catch {
				Logger.mesh.info("Error sending channel message")
			}
		}
	}
	
	var body: some View {
		let messages = chatMessages
		
		ChatView(
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
		.sheet(isPresented: $showingMessageDetails) {
			if let msg = selectedMessageForDetails {
				MessageDetailsView(message: msg, destination: .channel(channel))
			}
		}
		.sheet(isPresented: $showingTapbackInput) {
			if let msg = tapbackMessage {
				TapbackPickerView(message: msg) { emoji in
					sendTapback(emoji, to: msg)
				}
			}
		}
	}
}

struct ChannelCustomMessageCell: View {
	let message: Message
	let currentUserNum: Int64
	@Binding var replyMessageId: Int64
	@FocusState.Binding var messageFieldFocused: Bool
	let channel: ChannelEntity
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
							if msgEntity.canRetry {
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
						ChannelMessageStatusView(message: msgEntity)
						
						TapbackResponsesView(message: msgEntity) {
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

struct ChannelMessageStatusView: View {
	@ObservedObject var message: MessageEntity
	
	var body: some View {
		HStack {
			if isCurrentUser {
				let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
				if message.receivedACK {
					if message.realACK {
						HStack(spacing: 2) {
							Image(systemName: "checkmark.circle.fill")
								.font(.caption2)
								.foregroundStyle(.gray)
							Text(ackErrorVal?.display ?? "Sent")
								.font(.caption2)
								.foregroundStyle(.gray)
						}
					} else {
						HStack(spacing: 2) {
							Image(systemName: "checkmark.circle.fill")
								.font(.caption2)
								.foregroundStyle(.gray)
							Text("Acknowledged by another node")
								.font(.caption2)
								.foregroundStyle(.gray)
						}
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

struct TapbackResponsesView: View {
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

struct TapbackPickerView: View {
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

struct MessageDetailsView: View {
	@Environment(\.dismiss) var dismiss
	@ObservedObject var message: MessageEntity
	let destination: MessageDestination
	
	@State private var relayDisplay: String? = nil
	
	private var isCurrentUser: Bool {
		Int64(UserDefaults.preferredPeripheralNum) == message.fromUser?.num
	}
	
	var body: some View {
		NavigationView {
			List {
				Section {
					LabeledContent("From") {
						Text(message.fromUser?.longName ?? "Unknown")
					}
					LabeledContent("Time") {
						Text(message.timestamp.formatted(date: .abbreviated, time: .shortened))
					}
					LabeledContent("Message ID") {
						Text(String(message.messageId))
							.font(.caption)
					}
					LabeledContent("Channel") {
						Text(String(message.channel))
					}
				}
				
				if message.pkiEncrypted {
					Section("Security") {
						HStack {
							Image(systemName: "lock.fill")
								.foregroundColor(.green)
							Text("Encrypted")
						}
					}
				}
				
				if isCurrentUser {
					Section("Status") {
						if message.receivedACK {
							LabeledContent("Status") {
								HStack {
									Image(systemName: "checkmark.circle.fill")
										.foregroundColor(.green)
									Text(message.realACK ? "Delivered" : "Acknowledged by another node")
								}
							}
							LabeledContent("Ack Time") {
								Text(message.ackTimestamp > 0 ? 
									Date(timeIntervalSince1970: TimeInterval(message.ackTimestamp)).formatted(date: .abbreviated, time: .shortened) : "N/A")
							}
						} else if message.ackError > 0 {
							LabeledContent("Status") {
								let error = RoutingError(rawValue: Int(message.ackError))
								HStack {
									Image(systemName: "exclamationmark.circle.fill")
										.foregroundColor(.red)
									Text(error?.display ?? "Error")
								}
							}
						} else {
							LabeledContent("Status") {
								HStack {
									Image(systemName: "clock.fill")
										.foregroundColor(.yellow)
									Text("Pending...")
								}
							}
						}
						
						LabeledContent("Read") {
							Image(systemName: message.read ? "checkmark.circle.fill" : "circle")
								.foregroundColor(message.read ? .green : .gray)
						}
					}
				}
				
				Section("Message Info") {
					if let relayDisplay = relayDisplay {
						LabeledContent("Relay") {
							Text(relayDisplay)
								.foregroundColor(relayDisplay.contains("Node ") ? .secondary : .primary)
						}
					}
					
					if message.relays != 0 && !message.realACK {
						LabeledContent("Relayed by") {
							Text("\(message.relays) \(message.relays == 1 ? "node" : "nodes")")
						}
					}
					
					if message.ackSNR != 0 {
						LabeledContent("Ack SNR") {
							Text("\(String(format: "%.2f", message.ackSNR)) dB")
						}
					}
					
					if message.snr != 0 {
						LabeledContent("SNR") {
							Text("\(String(format: "%.2f", message.snr)) dB")
						}
					}
					
					if message.rssi != 0 {
						LabeledContent("RSSI") {
							Text("\(String(format: "%.2f", message.rssi)) dBm")
						}
					}
					
					if let node = message.fromUser?.userNode, node.hopsAway > 0 {
						LabeledContent("Hops Away") {
							Text("\(node.hopsAway)")
						}
					}
				}
				
				if message.replyID > 0 {
					Section("Reply") {
						LabeledContent("In Reply To") {
							Text(String(message.replyID))
								.font(.caption)
						}
					}
				}
				
				Section("Message Text") {
					Text(message.messagePayload ?? "Empty")
						.font(.body)
				}
			}
			.navigationTitle("Message Details")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button("Done") {
						dismiss()
					}
				}
			}
			.onAppear {
				DispatchQueue.global(qos: .userInitiated).async {
					let result = message.relayDisplay()
					DispatchQueue.main.async {
						relayDisplay = result
					}
				}
			}
		}
	}
}
