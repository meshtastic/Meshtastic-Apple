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

	var body: some View {
		VStack {
			ScrollViewReader { scrollView in
				ScrollView {
					LazyVStack {
						ForEach( user.messageList ) { (message: MessageEntity) in
							if user.num != bleManager.connectedPeripheral?.num ?? -1 {
								let currentUser: Bool = (Int64(UserDefaults.preferredPeripheralNum) == message.fromUser?.num ?? -1 ? true : false)

								if message.replyID > 0 {
									let messageReply = user.messageList.first(where: { $0.messageId == message.replyID })
									HStack {
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
													Text("\(ackErrorVal?.display ?? "Empty Ack Error")").font(.caption2).foregroundColor(.gray)
												} else {
													Text("Acknowledged by another node").font(.caption2).foregroundColor(.orange)
												}
											} else if currentUser && message.ackError == 0 {
												// Empty Error
												Text("Waiting to be acknowledged. . .").font(.caption2).foregroundColor(.yellow)
											} else if currentUser && message.ackError > 0 {
												Text("\(ackErrorVal?.display ?? "Empty Ack Error")").fixedSize(horizontal: false, vertical: true)
													.font(.caption2).foregroundColor(.red)
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
											try context.save()
											Logger.data.info("📖 [App] Read message \(message.messageId) ")
											appState.unreadDirectMessages = user.unreadMessages

										} catch {
											Logger.data.error("Failed to read message \(message.messageId): \(error.localizedDescription)")
										}
									}
								}
							}
						}
					}
				}
				.padding([.top])
				.scrollDismissesKeyboard(.immediately)
				.onAppear {
					if user.messageList.count > 0 {
						scrollView.scrollTo(user.messageList.last!.messageId)
					}
				}
				.onChange(of: user.messageList, perform: { _ in
					if user.messageList.count > 0 {
						scrollView.scrollTo(user.messageList.last!.messageId)
					}
				})
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
