import SwiftData
import MeshtasticProtobufs
import SwiftUI

struct ChannelMessageRow: View {
	@EnvironmentObject var appState: AppState
	@Environment(\.modelContext) private var context
	
	// Core Data object observed for changes (like Tapbacks being received)
	@Bindable var message: MessageEntity
	
	let replyMessage: MessageEntity?
	let tapbacks: [MessageEntity]
	let previousMessage: MessageEntity?
	let preferredPeripheralNum: Int
	let channel: ChannelEntity
	
	@Binding var replyMessageId: Int64
	@FocusState.Binding var messageFieldFocused: Bool
	@Binding var messageToHighlight: Int64
	let scrollView: ScrollViewProxy
	let onTapback: (MessageEntity) -> Void
	let onMessageRetried: () -> Void

	private var isCurrentUser: Bool {
		Int64(preferredPeripheralNum) == message.fromUser?.num
	}
	
	init(message: MessageEntity,
	     replyMessage: MessageEntity?,
	     tapbacks: [MessageEntity],
	     previousMessage: MessageEntity?,
	     preferredPeripheralNum: Int,
	     channel: ChannelEntity,
	     replyMessageId: Binding<Int64>,
	     messageFieldFocused: FocusState<Bool>.Binding,
	     messageToHighlight: Binding<Int64>,
	     scrollView: ScrollViewProxy,
	     onTapback: @escaping (MessageEntity) -> Void,
	     onMessageRetried: @escaping () -> Void = {}) {
		// Initialize ObservedObject with the concrete instance
		self.message = message
		self.replyMessage = replyMessage
		self.tapbacks = tapbacks
		self.previousMessage = previousMessage
		self.preferredPeripheralNum = preferredPeripheralNum
		self.channel = channel
		self._replyMessageId = replyMessageId
		self._messageFieldFocused = messageFieldFocused
		self._messageToHighlight = messageToHighlight
		self.scrollView = scrollView
		self.onTapback = onTapback
		self.onMessageRetried = onMessageRetried
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
						Text(replyMessage?.displayedPayload ?? "EMPTY MESSAGE").foregroundColor(.accentColor).font(.caption2)
							.padding(10)
							.overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue, lineWidth: 0.5))
						Image(systemName: "arrowshape.turn.up.left.fill")
							.symbolRenderingMode(.hierarchical).imageScale(.large)
							.foregroundColor(.accentColor).padding(.trailing)
					}
					if !isCurrentUser { Spacer(minLength: 50) }
				}
			}
			// Main Message Row Content
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
					let deliveryStatus = isCurrentUser ? message.deliveryStatus(isDirectMessage: false) : nil
					let isDetectionSensorMessage = message.portNum == Int32(PortNum.detectionSensorApp.rawValue)
					
					// Sender Name Header
					if !isCurrentUser && message.fromUser != nil {
						Text("\(message.fromUser?.longName ?? "Unknown".localized ) (\(message.fromUser?.userId ?? "?"))")
							.font(.caption).foregroundColor(.gray).offset(y: 8)
					}
					
					// Message Bubble
					HStack {
						MessageText(
							message: message,
							tapBackDestination: .channel(channel),
							isCurrentUser: isCurrentUser
						) {
							self.replyMessageId = message.messageId
							self.messageFieldFocused = true
						} onTapback: {
							onTapback(message)
						}
						
						if let deliveryStatus, deliveryStatus.canRetry {
							RetryButton(
								message: message,
								destination: .channel(channel),
								status: deliveryStatus,
								onMessageSent: onMessageRetried
							)
						}
					}
					
					TapbackResponses(tapbacks: tapbacks)
					
					// ACK Status / Error
					HStack {
						if let deliveryStatus, !isDetectionSensorMessage {
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
		.id(message.messageId) // ID for scrolling/highlighting
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(Color.yellow.opacity(messageToHighlight == message.messageId ? 0.18 : 0))
				.padding(.horizontal, 4)
		)
		.animation(.easeInOut(duration: 0.3), value: messageToHighlight)
	}
}
