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
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.managedObjectContext) var context
	@FocusState var messageFieldFocused: Bool
	@ObservedObject var user: UserEntity
	@State private var replyMessageId: Int64 = 0
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
								if user.num != accessoryManager.activeDeviceNum ?? -1 {
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
									.padding([.leading, .trailing])
									.frame(maxWidth: .infinity)
									.id(message.messageId)
									.onAppear {
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
									}
								}
							}
							// Invisible spacer to detect reaching bottom
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
