import CoreData
import MeshtasticProtobufs
import SwiftUI

struct ChannelMessageRow: View {
	@EnvironmentObject var appState: AppState
	
	// Core Data object observed for changes (like Tapbacks being received)
	@ObservedObject var message: MessageEntity
	
	let allMessages: FetchedResults<MessageEntity> // The full list for reply lookup
	let previousMessage: MessageEntity?
	let preferredPeripheralNum: Int
	let channel: ChannelEntity
	
	@Binding var replyMessageId: Int64
	@FocusState.Binding var messageFieldFocused: Bool
	@Binding var messageToHighlight: Int64
	let scrollView: ScrollViewProxy
	let onInteractionComplete: () -> Void

	private var isCurrentUser: Bool {
		Int64(preferredPeripheralNum) == message.fromUser?.num
	}
	
	init(message: MessageEntity, 
		 allMessages: FetchedResults<MessageEntity>,
		 previousMessage: MessageEntity?,
		 preferredPeripheralNum: Int,
		 channel: ChannelEntity,
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
		self.channel = channel
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
						Text(messageReply?.messagePayload ?? "EMPTY MESSAGE").foregroundColor(.accentColor).font(.caption2)
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
					CircleText(text: message.fromUser?.shortName ?? "?", color: Color(UIColor(hex: UInt32(message.fromUser?.num ?? 0))), circleSize: 50)
						.onTapGesture(count: 2) {
							if let nodeNum = message.fromUser?.num {
								appState.router.navigateToNodeDetail(nodeNum: Int64(nodeNum))
							}
						}
						.padding(.all, 5).offset(y: -7)
				}
				
				VStack(alignment: isCurrentUser ? .trailing : .leading) {
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
						}
						
						if isCurrentUser && message.canRetry {
							RetryButton(message: message, destination: .channel(channel))
						}
					}
					
					// Tapback Responses - Pass the closure to trigger the parent redraw
					TapbackResponses(message: message, onRead: onInteractionComplete)
					
					// ACK Status / Error
					HStack {
						let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
						if isCurrentUser && message.receivedACK {
							Text("\(ackErrorVal?.display ?? "Empty Ack Error")").fixedSize(horizontal: false, vertical: true)
								.foregroundStyle(ackErrorVal?.color ?? Color.red).font(.caption2)
						} else if isCurrentUser && message.ackError == 0 {
							Text("Waiting to be acknowledged. . .").font(.caption2).foregroundColor(.orange)
						} else if isCurrentUser && !isDetectionSensorMessage {
							Text("\(ackErrorVal?.display ?? "Empty Ack Error")").fixedSize(horizontal: false, vertical: true)
								.foregroundStyle(ackErrorVal?.color ?? Color.red).font(.caption2)
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
	}
}
