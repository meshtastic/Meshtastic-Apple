//
//  UserMessageList.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import CoreData
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct ChannelMessageList: View {
	@EnvironmentObject var appState: AppState
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	// Keyboard State
	@FocusState var messageFieldFocused: Bool
	@ObservedObject var myInfo: MyInfoEntity
	@ObservedObject var channel: ChannelEntity
	@State private var replyMessageId: Int64 = 0
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
	// Scroll state
	@State private var showScrollToBottomButton = false
	@State private var hasReachedBottom = false
	@State private var gotFirstUnreadMessage: Bool = false

	var body: some View {
		VStack {
			ScrollViewReader { scrollView in
				ZStack(alignment: .bottomTrailing) {
					ScrollView {
						LazyVStack {
							ForEach(channel.allPrivateMessages) { (message: MessageEntity) in
								let currentUser: Bool = (Int64(preferredPeripheralNum) == message.fromUser?.num ? true : false)
								if message.replyID > 0 {
									let messageReply = channel.allPrivateMessages.first(where: { $0.messageId == message.replyID })
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
								HStack(alignment: .bottom) {
									if currentUser { Spacer(minLength: 50) }
									if !currentUser {
										CircleText(text: message.fromUser?.shortName ?? "?", color: Color(UIColor(hex: UInt32(message.fromUser?.num ?? 0))), circleSize: 44, node: getNodeInfo(id: Int64(message.fromUser?.num ?? 0), context: context))
											.padding(.all, 5)
											.offset(y: -7)
									}

									VStack(alignment: currentUser ? .trailing : .leading) {
										let isDetectionSensorMessage = message.portNum == Int32(PortNum.detectionSensorApp.rawValue)

										if !currentUser && message.fromUser != nil {
											Text("\(message.fromUser?.longName ?? "unknown".localized ) (\(message.fromUser?.userId ?? "?"))")
												.font(.caption)
												.foregroundColor(.gray)
												.offset(y: 8)
										}

										HStack {
											MessageText(
												message: message,
												tapBackDestination: .channel(channel),
												isCurrentUser: currentUser
											) {
												self.replyMessageId = message.messageId
												self.messageFieldFocused = true
											}

											if currentUser && message.canRetry {
												RetryButton(message: message, destination: .channel(channel))
											}
										}

										TapbackResponses(message: message) {
											appState.unreadChannelMessages = myInfo.unreadMessages
											context.refresh(myInfo, mergeChanges: true)
										}

										HStack {
											let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
											if currentUser && message.receivedACK {
												Text("\(ackErrorVal?.display ?? "Empty Ack Error")").fixedSize(horizontal: false, vertical: true)
													.foregroundStyle(ackErrorVal?.color ?? Color.red)
													.font(.caption2)
											} else if currentUser && message.ackError == 0 {
												// Empty Error
												Text("Waiting to be acknowledged. . .").font(
													.caption2)
													.foregroundColor(.orange)
											} else if currentUser && !isDetectionSensorMessage {
												Text("\(ackErrorVal?.display ?? "Empty Ack Error")").fixedSize(horizontal: false, vertical: true)
													.foregroundStyle(ackErrorVal?.color ?? Color.red)
													.font(.caption2)
											}
										}
									}
									.padding(.bottom)
									.id(channel.allPrivateMessages.firstIndex(of: message))

									if !currentUser {
										Spacer(minLength: 50)
									}
								}
								.padding([.leading, .trailing])
								.frame(maxWidth: .infinity)
								.id(message.messageId)
								.onAppear {
									if gotFirstUnreadMessage {
										if !message.read {
											message.read = true
											do {
												for unreadMessage in channel.allPrivateMessages.filter({ !$0.read }) {
													unreadMessage.read = true
												}
												try context.save()
												Logger.data.info("📖 [App] Read message \(message.messageId, privacy: .public) ")
												appState.unreadChannelMessages = myInfo.unreadMessages
												context.refresh(myInfo, mergeChanges: true)
											} catch {
												Logger.data.error("Failed to read message \(message.messageId, privacy: .public): \(error.localizedDescription, privacy: .public)")
											}
										}
										// Check if we've reached the bottom message
										if message.messageId == channel.allPrivateMessages.last?.messageId {
											hasReachedBottom = true
											showScrollToBottomButton = false
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
						if let firstUnreadMessageId = channel.allPrivateMessages.first(where: { !$0.read })?.messageId {
							withAnimation {
								scrollView.scrollTo(firstUnreadMessageId, anchor: .top)
								showScrollToBottomButton = true
							}
						} else {
							// If no unread messages, scroll to bottom
							withAnimation {
								scrollView.scrollTo(channel.allPrivateMessages.last?.messageId ?? 0, anchor: .bottom)
								hasReachedBottom = true
							}
						}
						gotFirstUnreadMessage = true
					}
					.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
						withAnimation {
							scrollView.scrollTo(channel.allPrivateMessages.last?.messageId ?? 0, anchor: .bottom)
							hasReachedBottom = true
							showScrollToBottomButton = false
						}
					}
					.onChange(of: channel.allPrivateMessages) {
						if hasReachedBottom {
							withAnimation {
								scrollView.scrollTo(channel.allPrivateMessages.last?.messageId ?? 0, anchor: .bottom)
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
				destination: .channel(channel),
				replyMessageId: $replyMessageId,
				isFocused: $messageFieldFocused
			) {
				context.refresh(channel, mergeChanges: true)
			}
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				HStack {
					CircleText(text: String(channel.index), color: .accentColor, circleSize: 44).fixedSize()
					Text(String(channel.name ?? "unknown".localized).camelCaseToWords()).font(.headline)
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?",

						// mqttProxyConnected defaults to false, so if it's not enabled it will still be false
						mqttProxyConnected: bleManager.mqttProxyConnected && (channel.uplinkEnabled || channel.downlinkEnabled),
						mqttUplinkEnabled: channel.uplinkEnabled,
						mqttDownlinkEnabled: channel.downlinkEnabled,
						mqttTopic: bleManager.mqttManager.topic
					)
				}
			}
		}
	}
}
