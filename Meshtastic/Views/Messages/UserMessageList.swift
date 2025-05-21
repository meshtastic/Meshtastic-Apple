//
//  UserMessageList.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import SwiftUI
import CoreData
import OSLog

struct UserMessageList: View {

	@EnvironmentObject var appState: AppState
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.managedObjectContext) var context
	// Keyboard State
	@FocusState var messageFieldFocused: Bool
	// View State Items
	@ObservedObject var user: UserEntity
	@State private var replyMessageId: Int64 = 0
	// Scroll state
	@State private var showScrollToBottomButton = false
	@State private var hasReachedBottom = false
	@State private var gotFirstUnreadMessage: Bool = false
	@State private var messageToHighlight: Int64 = 0

	var body: some View {
		VStack {
			ScrollViewReader { scrollView in
				ZStack(alignment: .bottomTrailing) {
					ScrollView {
						LazyVStack {
							ForEach( Array(user.messageList.enumerated()), id: \.element.id) { index, message in
								// Get the previous message, if it exists
								let previousMessage = index > 0 ? user.messageList[index - 1] : nil
								if message.displayTimestamp(aboveMessage: previousMessage) {
									Text(message.timestamp.formatted(date: .abbreviated, time: .shortened))
										.font(.caption)
										.foregroundColor(.gray)
								}
								if user.num != bleManager.connectedPeripheral?.num ?? -1 {
									let currentUser: Bool = (Int64(UserDefaults.preferredPeripheralNum) == message.fromUser?.num ?? -1 ? true : false)

									if message.replyID > 0 {
										let messageReply = user.messageList.first(where: { $0.messageId == message.replyID })
										HStack {
											Button {
												if let messageNum = messageReply?.messageId {
													withAnimation(.easeInOut(duration: 0.5)) {
														messageToHighlight = messageNum
													}
													scrollView.scrollTo(messageNum, anchor: .center)

													// Reset highlight after delay
													Task {
														try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
														withAnimation(.easeInOut(duration: 0.5)) {
															messageToHighlight = -1
														}
													}
												}
											} label: {
												Text(messageReply?.messagePayload ?? "EMPTY MESSAGE").foregroundColor(.accentColor).font(.caption2)
													.padding(10)
													.overlay(
														RoundedRectangle(cornerRadius: 18)
															.stroke(Color.blue, lineWidth: 0.5)
													)
												Image(systemName: "arrowshape.turn.up.left.fill")
													.symbolRenderingMode(.hierarchical)
													.imageScale(.large).foregroundColor(.accentColor)
													.padding(.trailing)
											}
										}
									}
									HStack(alignment: .top) {
										if currentUser { Spacer(minLength: 50) }
										VStack(alignment: currentUser ? .trailing : .leading) {
											HStack {
												MessageText(
													message: message,
													tapBackDestination: .user(user),
													isCurrentUser: currentUser
												) {
													self.replyMessageId = message.messageId
													self.messageFieldFocused = true
												}

												if currentUser && message.canRetry || (message.receivedACK && !message.realACK) {
													RetryButton(message: message, destination: .user(user))
												}
											}

											TapbackResponses(message: message) {
												appState.unreadDirectMessages = user.unreadMessages
											}

											HStack {
												let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
												if currentUser && message.receivedACK {
													// Ack Received
													if message.realACK {
														Text("\(ackErrorVal?.display ?? "Empty Ack Error")")
															.font(.caption2)
															.foregroundStyle(ackErrorVal?.color ?? Color.secondary)
													} else {
														Text("Acknowledged by another node").font(.caption2).foregroundColor(.orange)
													}
												} else if currentUser && message.ackError == 0 {
													// Empty Error
													Text("Waiting to be acknowledged. . .").font(.caption2).foregroundColor(.yellow)
												} else if currentUser && message.ackError > 0 {
													Text("\(ackErrorVal?.display ?? "Empty Ack Error")").fixedSize(horizontal: false, vertical: true)
														.foregroundStyle(ackErrorVal?.color ?? Color.red)
														.font(.caption2)
												}
											}
										}
										.padding(.bottom)
										.id(user.messageList.firstIndex(of: message))

										if !currentUser {
											Spacer(minLength: 50)
										}
									}
									.overlay {
										RoundedRectangle(cornerRadius: 10)
											.stroke(.blue, lineWidth: 2)
											.opacity(((messageToHighlight  == message.messageId) || (replyMessageId == message.messageId)) ? 1 : 0)
									}
									.padding([.leading, .trailing])
									.frame(maxWidth: .infinity)
									.id(message.messageId)
									.onAppear {
										if gotFirstUnreadMessage {
											if !message.read {
												message.read = true
												do {
													for unreadMessage in user.messageList.filter({ !$0.read }) {
														unreadMessage.read = true
													}
													try context.save()
													Logger.data.info("📖 [App] Read message \(message.messageId, privacy: .public) ")
													appState.unreadDirectMessages = user.unreadMessages
												} catch {
													Logger.data.error("Failed to read message \(message.messageId, privacy: .public): \(error.localizedDescription, privacy: .public)")
												}
											}
											// Check if we've reached the bottom message
											if message.messageId == user.messageList.last?.messageId {
												hasReachedBottom = true
												showScrollToBottomButton = false
											}
										}
									}
								}
							}
							// Invisible spacer to detect reaching bottom
							Color.clear
								.frame(height: 1)
								.id("bottomAnchor")
								.onAppear {
									hasReachedBottom = true
									showScrollToBottomButton = false
								}
						}
					}
					.scrollDismissesKeyboard(.interactively)
					.onFirstAppear {
						// Find first unread message
						if let firstUnreadMessageId = user.messageList.first(where: { !$0.read })?.messageId {
							withAnimation {
								scrollView.scrollTo(firstUnreadMessageId, anchor: .top)
								showScrollToBottomButton = true
							}
						} else {
							// If no unread messages, scroll to bottom
							withAnimation {
								scrollView.scrollTo(user.messageList.last?.messageId ?? 0, anchor: .bottom)
								hasReachedBottom = true
							}
						}
						gotFirstUnreadMessage = true
					}
					.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
						withAnimation {
							scrollView.scrollTo(user.messageList.last?.messageId ?? 0, anchor: .bottom)
							hasReachedBottom = true
							showScrollToBottomButton = false
						}
					}
					.onChange(of: user.messageList) {
						if hasReachedBottom {
							withAnimation {
								scrollView.scrollTo(user.messageList.last?.messageId ?? 0, anchor: .bottom)
							}
						} else {
							showScrollToBottomButton = true
						}
					}
					// Scroll to bottom button
					if showScrollToBottomButton {
						Button {
							withAnimation {
								scrollView.scrollTo("bottomAnchor", anchor: .bottom)
								hasReachedBottom = true
								showScrollToBottomButton = false
							}
						} label: {
							ScrollToBottomButtonView()
						}
						.padding(.bottom, 8)
						.padding(.trailing, 16)
						.transition(.opacity)
					}
				}
			}

			TextMessageField(
				destination: .user(user),
				replyMessageId: $replyMessageId,
				isFocused: $messageFieldFocused
			) {
				context.refresh(user, mergeChanges: true)
			}
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				HStack {
					CircleText(text: user.shortName ?? "?", color: Color(UIColor(hex: UInt32(user.num))), circleSize: 44)
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
				}
			}
		}
	}
}
