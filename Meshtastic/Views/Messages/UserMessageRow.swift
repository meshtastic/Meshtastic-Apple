//
//  UserMessageRow.swift
//  MeshtasticApple
//
//  Copyright(c) Garth Vander Houwen 10/1/2025
//

import CoreData
import MeshtasticProtobufs
import SwiftUI

struct UserMessageRow: View {
	
	@EnvironmentObject var appState: AppState
	@ObservedObject var message: MessageEntity
	let allMessages: [MessageEntity]
	let previousMessage: MessageEntity?
	let preferredPeripheralNum: Int
	let user: UserEntity // The direct message user
	@Binding var replyMessageId: Int64
	@FocusState.Binding var messageFieldFocused: Bool
	@Binding var messageToHighlight: Int64
	let scrollView: ScrollViewProxy
	let onInteractionComplete: () -> Void
	
	@State private var retryStatus: (current: Int, max: Int, state: RetryState)?
	@State private var isRetrying: Bool = false
	
	private var isCurrentUser: Bool {
		Int64(preferredPeripheralNum) == message.fromUser?.num
	}
	
	private var canShowRetryButton: Bool {
		guard isCurrentUser else { return false }
		
		if message.receivedACK && !message.realACK {
			return true
		}
		
		if let (_, _, state) = retryStatus {
			return state == .pending || state == .waitingForAck || state == .sending
		}
		
		let re = RoutingError(rawValue: Int(message.ackError))
		return re?.canRetry ?? false
	}
	
	init(message: MessageEntity,
		 allMessages: [MessageEntity],
		 previousMessage: MessageEntity?,
		 preferredPeripheralNum: Int,
		 user: UserEntity,
		 replyMessageId: Binding<Int64>,
		 messageFieldFocused: FocusState<Bool>.Binding,
		 messageToHighlight: Binding<Int64>,
		 scrollView: ScrollViewProxy,
		 onInteractionComplete: @escaping () -> Void) {
		// Initialize ObservedObject with the concrete instance
		self._message = ObservedObject(initialValue: message)
		self.allMessages = allMessages
		self.previousMessage = previousMessage
		self.preferredPeripheralNum = preferredPeripheralNum
		self.user = user
		self._replyMessageId = replyMessageId
		self._messageFieldFocused = messageFieldFocused
		self._messageToHighlight = messageToHighlight
		self.scrollView = scrollView
		self.onInteractionComplete = onInteractionComplete
	}
	
	var body: some View {
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
				let messageReply = allMessages.first(where: { $0.messageId == message.replyID })
				
				HStack {
					Spacer(minLength: isCurrentUser ? 50 : 0)
					
					Button {
						if let messageNum = messageReply?.messageId {
							withAnimation(.easeInOut(duration: 0.5)) {
								messageToHighlight = messageNum
							}
							scrollView.scrollTo(messageNum, anchor: .center)
							Task {
								DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
									withAnimation(.easeInOut(duration: 0.5)) {
										messageToHighlight = -1
									}
								}
							}
						}
					} label: {
						HStack {
							Image(systemName: "arrowshape.turn.up.left.fill")
								.symbolRenderingMode(.hierarchical).imageScale(.large)
								.foregroundColor(.accentColor).padding(.leading)
							Text(messageReply?.messagePayload ?? "EMPTY MESSAGE").foregroundColor(.accentColor).font(.caption2)
						}
						.padding(10)
						.overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue, lineWidth: 0.5))
					}
					if !isCurrentUser { Spacer(minLength: 50) }
				}
			}
			
			HStack(alignment: .bottom) {
				if isCurrentUser { Spacer(minLength: 50) }
				
				// Node Detail Tap
				if !isCurrentUser {
					CircleText(text: message.fromUser?.shortName ?? "?", color: Color(UIColor(hex: UInt32(message.fromUser?.num ?? 0))), circleSize: 50)
						.onTapGesture(count: 2) {
							if let nodeNum = message.fromUser?.num {
								appState.router.navigateToNodeDetail(nodeNum: Int64(nodeNum))
							}
						}
						.padding(.all, 5).offset(y: -7)
				}
				
				VStack(alignment: isCurrentUser ? .trailing : .leading) {
					
					// Sender Name Header
					if !isCurrentUser && message.fromUser != nil {
						Text("\(message.fromUser?.longName ?? "Unknown".localized ) (\(message.fromUser?.userId ?? "?"))")
							.font(.caption).foregroundColor(.gray).offset(y: 8)
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
						}
						
						if isCurrentUser && canShowRetryButton {
							RetryButton(message: message, destination: .user(user))
						}
					}
					
					// Tapback Responses - Pass the closure to trigger the parent redraw
					TapbackResponses(message: message, onRead: onInteractionComplete)
					
					// ACK Error & Retry Status
					HStack {
						let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
						
						// Status line (retry queue takes precedence over ack error)
						if isCurrentUser {
							if let (current, max, state) = retryStatus, state != .completed && state != .cancelled {
								if state == .waitingForAck {
									Text("Waiting for acknowledgment")
										.font(.caption2)
										.foregroundColor(.orange)
									AnimatedEllipsis()
										.font(.caption2)
										.foregroundColor(.orange)
								} else if state == .sending {
									Text("Sending")
										.font(.caption2)
										.foregroundColor(.orange)
									AnimatedEllipsis()
										.font(.caption2)
										.foregroundColor(.orange)
								} else if state == .pending {
									Text("Attempting to send (\(current)/\(max))")
										.font(.caption2)
										.foregroundColor(.orange)
									AnimatedEllipsis()
										.font(.caption2)
										.foregroundColor(.orange)
								}
							}
						}
						
						if isCurrentUser && message.receivedACK {
							// Ack Received
							if message.realACK {
								Text("\(ackErrorVal?.display ?? "Empty Ack Error")")
									.font(.caption2)
									.foregroundStyle(ackErrorVal?.color ?? Color.secondary)
							} else {
								Text("Acknowledged by another node").font(.caption2).foregroundColor(.orange)
							}
						} else if isCurrentUser && message.ackError == 0 && !message.receivedACK {
							// Empty Error and not received ACK
							if !isRetrying {
								Text("Waiting for acknowledgment")
									.font(.caption2)
									.foregroundColor(.yellow)
								AnimatedEllipsis()
									.font(.caption2)
									.foregroundColor(.yellow)
							}
						} else if isCurrentUser && message.ackError > 0 && !message.receivedACK {
							if !isRetrying {
								Text("\(ackErrorVal?.display ?? "Empty Ack Error")").fixedSize(horizontal: false, vertical: true)
									.foregroundStyle(ackErrorVal?.color ?? Color.red)
									.font(.caption2)
							}
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
		.task { await refreshRetryState() }
		.onReceive(NotificationCenter.default.publisher(for: MessageRetryQueueManager.didUpdateNotification)) { _ in
			Task { await refreshRetryState() }
		}
	}
	
	private func refreshRetryState() async {
		let messageId = message.messageId
		let status = await MessageRetryQueueManager.shared.getRetryStatus(for: messageId)
		let retrying = await MessageRetryQueueManager.shared.canRetry(messageId)
		await MainActor.run {
			retryStatus = status
			isRetrying = retrying
		}
	}
}
