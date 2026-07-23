//
//  UserMessageRow.swift
//  MeshtasticApple
//
//  Copyright(c) Garth Vander Houwen 10/1/2025
//

import SwiftData
import MeshtasticProtobufs
import SwiftUI

struct UserMessageRow: View {
	
	@EnvironmentObject var appState: AppState
	@Environment(\.modelContext) private var context
	@Bindable var message: MessageEntity
	let replyMessage: MessageEntity?
	let tapbacks: [MessageEntity]
	let previousMessage: MessageEntity?
	let preferredPeripheralNum: Int
	let user: UserEntity // The direct message user
	@Binding var replyMessageId: Int64
	@FocusState.Binding var messageFieldFocused: Bool
	@Binding var messageToHighlight: Int64
	let scrollView: ScrollViewProxy
	let onTapback: (MessageEntity) -> Void
	
	private var isCurrentUser: Bool {
		Int64(preferredPeripheralNum) == message.fromUser?.num
	}

	/// A single, natural-language description of the message bubble so VoiceOver reads one element
	/// (sender + text + timestamp + security state) instead of separate fragments. Delivery/read
	/// status stays its own labeled element (MessageDeliveryStatusLabel) directly after.
	///
	/// The badge portion is built from `MessageEntity.activeStatusBadges`, the same source of truth
	/// MessageText's per-badge overlays read from, so this combined label can't silently drop a
	/// badge (encrypted, verified, store-and-forward, detection sensor, translated) that the bubble
	/// itself is showing (issue #016 T003).
	private var messageAccessibilityLabel: String {
		let text = message.displayedPayload
		let time = message.timestamp.formatted(date: .abbreviated, time: .shortened)
		var parts: [String]
		if isCurrentUser {
			parts = [String(localized: "You sent: \(text)", comment: "VoiceOver: label for a message you sent. %@ is the message text")]
		} else {
			let sender = message.fromUser?.longName ?? "Unknown".localized
			parts = [String(localized: "Message from \(sender): \(text)", comment: "VoiceOver: label for a received message. First value is the sender, second is the message text")]
		}
		parts.append(time)
		parts.append(contentsOf: message.activeStatusBadges(destination: .user(user), isCurrentUser: isCurrentUser).map(\.label))
		return parts.joined(separator: ", ")
	}

	init(
		message: MessageEntity,
		replyMessage: MessageEntity?,
		tapbacks: [MessageEntity],
		previousMessage: MessageEntity?,
		preferredPeripheralNum: Int,
		user: UserEntity,
		replyMessageId: Binding<Int64>,
		messageFieldFocused: FocusState<Bool>.Binding,
		messageToHighlight: Binding<Int64>,
		scrollView: ScrollViewProxy,
		onTapback: @escaping (MessageEntity) -> Void
	) {
		// Initialize ObservedObject with the concrete instance
		self.message = message
		self.replyMessage = replyMessage
		self.tapbacks = tapbacks
		self.previousMessage = previousMessage
		self.preferredPeripheralNum = preferredPeripheralNum
		self.user = user
		self._replyMessageId = replyMessageId
		self._messageFieldFocused = messageFieldFocused
		self._messageToHighlight = messageToHighlight
		self.scrollView = scrollView
		self.onTapback = onTapback
	}
	
	var body: some View {
		// A retained message row can re-evaluate its body after the underlying MessageEntity has been
		// deleted/invalidated (messages are pruned underneath the list). Reading any persisted property
		// of a deleted @Model — directly, via the `fromUser` relationship, or through the MessageEntity
		// computed-property extensions — fatally traps in SwiftData (SIGTRAP). Bail to an empty row when
		// the message is no longer live; the List drops it on its next rebuild. Mirrors the NodeListItem
		// guard.
		if message.modelContext != nil && !message.isDeleted {
			rowContent
		} else {
			EmptyView()
		}
	}

	@ViewBuilder private var rowContent: some View {
		VStack(alignment: .leading, spacing: 0) {
			
			// Timestamp Header
			if message.displayTimestamp(aboveMessage: previousMessage) {
				Text(message.timestamp.formatted(date: .abbreviated, time: .shortened))
					.font(.caption)
					.foregroundColor(.gray)
					.frame(maxWidth: .infinity, alignment: .center)
					.padding(.vertical, 5)
			}
			
			// Reply Message Block
			if message.replyID > 0 {
				HStack {
					Spacer(minLength: isCurrentUser ? 50 : 0)
					
					Button {
						if let messageNum = replyMessage?.messageId {
							withAnimation(.easeInOut(duration: 0.5)) {
								messageToHighlight = messageNum
							}
							scrollView.scrollTo(messageNum, anchor: .center)
							Task {
								DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
									// Only clear if this jump's highlight is still the active one — a search
									// (or later jump) may have moved the highlight elsewhere in the meantime.
									if messageToHighlight == messageNum {
										withAnimation(.easeInOut(duration: 0.5)) {
											messageToHighlight = -1
										}
									}
								}
							}
						}
					} label: {
						HStack {
							Image(systemName: "arrowshape.turn.up.left.fill")
								.symbolRenderingMode(.hierarchical).imageScale(.large)
								.foregroundColor(.accentColor).padding(.leading)
							Text(replyMessage?.displayedPayload ?? "EMPTY MESSAGE").foregroundColor(.accentColor).font(.caption2)
						}
						.padding(10)
						.overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue, lineWidth: 0.5))
					}
					.accessibilityLabel(String(localized: "Replying to: \(replyMessage?.displayedPayload ?? "EMPTY MESSAGE")", comment: "VoiceOver: button that jumps to the quoted message being replied to. %@ is the quoted text"))
					if !isCurrentUser { Spacer(minLength: 50) }
				}
			}
			
			HStack(alignment: .bottom) {
				if isCurrentUser { Spacer(minLength: 50) }
				
				// Node Detail Tap
				if !isCurrentUser {
					NavigationLink(value: Int64(message.fromUser?.num ?? 0)) {
						CircleText(text: message.fromUser?.shortName ?? "?", color: Color(UIColor(hex: UInt32(message.fromUser?.num ?? 0))), circleSize: 50)
					}
					.buttonStyle(.plain)
					.padding(.all, 5).offset(y: -7)
				}
				
				VStack(alignment: isCurrentUser ? .trailing : .leading) {
					let deliveryStatus = isCurrentUser ? message.deliveryStatus(isDirectMessage: true) : nil
					
					// Sender Name Header
					if !isCurrentUser && message.fromUser != nil {
						Text("\(message.fromUser?.longName ?? "Unknown".localized ) (\(message.fromUser?.userId ?? "?"))")
							.font(.caption).foregroundColor(.gray).offset(y: 8)
							.accessibilityHidden(true) // Folded into the message bubble's combined label
					}
					
					// Message Bubble
					HStack {
						MessageText(
							message: message,
							tapBackDestination: .user(user), // Destination is the user
							isCurrentUser: isCurrentUser
						) {
							self.replyMessageId = message.messageId
							self.messageFieldFocused = true
						} onTapback: {
							onTapback(message)
						}
						.accessibilityElement(children: .combine)
						.accessibilityLabel(messageAccessibilityLabel)
						
						if let deliveryStatus, deliveryStatus.canRetry {
							RetryButton(message: message, destination: .user(user), status: deliveryStatus)
						}
					}
					
					TapbackResponses(tapbacks: tapbacks)
					
					// ACK Error
					HStack {
						if let deliveryStatus {
							MessageDeliveryStatusLabel(status: deliveryStatus)
						}
					}
				}
				.padding(.bottom)
				
				if !isCurrentUser { Spacer(minLength: 50) }
			}
			.padding([.leading, .trailing])
			.frame(maxWidth: .infinity)
			
		}
		.id(message.messageId)
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(Color.yellow.opacity(messageToHighlight == message.messageId ? 0.18 : 0))
				.padding(.horizontal, 4)
		)
		.animation(.easeInOut(duration: 0.3), value: messageToHighlight)
	}
}
