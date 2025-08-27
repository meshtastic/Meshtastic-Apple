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
	@EnvironmentObject var accessoryManager: AccessoryManager
	// Keyboard State
	@FocusState var messageFieldFocused: Bool
	@ObservedObject var myInfo: MyInfoEntity
	@ObservedObject var channel: ChannelEntity
	@State private var replyMessageId: Int64 = 0
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
	// Scroll state
	@State private var showScrollToBottomButton = false
	@State private var hasReachedBottom = false

	@State private var messageToHighlight: Int64 = 0
	
	@FetchRequest private var allPrivateMessages: FetchedResults<MessageEntity>
	
	init(myInfo: MyInfoEntity, channel: ChannelEntity) {
		self.myInfo = myInfo
		self.channel = channel
		
		// Configure fetch request here
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

	var body: some View {
		VStack {
			ScrollViewReader { scrollView in
				ZStack(alignment: .bottomTrailing) {
					ScrollView {
						LazyVStack {
							ForEach(allPrivateMessages) { message in
								// Get the previous message, if it exists
								let thisMessageIndex = allPrivateMessages.firstIndex(of: message) ?? 0
								let previousMessage =  thisMessageIndex > 0 ? allPrivateMessages[thisMessageIndex - 1] : nil
								let currentUser: Bool = (Int64(preferredPeripheralNum) == message.fromUser?.num ? true : false)
								if message.displayTimestamp(aboveMessage: previousMessage) {
									Text(message.timestamp.formatted(date: .abbreviated, time: .shortened))
										.font(.caption)
										.foregroundColor(.gray)
								}
								if message.replyID > 0 {
									let messageReply = allPrivateMessages.first(where: { $0.messageId == message.replyID })
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
											Text("\(message.fromUser?.longName ?? "Unknown".localized ) (\(message.fromUser?.userId ?? "?"))")
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
									.id(allPrivateMessages.firstIndex(of: message))

									if !currentUser {
										Spacer(minLength: 50)
									}
								}
//								.overlay {
//									RoundedRectangle(cornerRadius: 18)
//										.stroke(.blue, lineWidth: 2)
//										.opacity(((messageToHighlight  == message.messageId) || (replyMessageId == message.messageId)) ? 1 : 0)
//								}
								.padding([.leading, .trailing])
								.frame(maxWidth: .infinity)
								.id(message.messageId)
								.onAppear {
										if !message.read {
											message.read = true
											do {
												for unreadMessage in allPrivateMessages.filter({ !$0.read }) {
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
										if message.messageId == allPrivateMessages.last?.messageId {
											hasReachedBottom = true
											showScrollToBottomButton = false
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
						DispatchQueue.main.async {
							if channel.unreadMessages == 0 {
								withAnimation {
									scrollView.scrollTo("bottomAnchor", anchor: .bottom)
									hasReachedBottom = true
								}
							} else {
								if let firstUnreadMessageId = allPrivateMessages.first(where: { !$0.read })?.messageId {
									withAnimation {
										scrollView.scrollTo(firstUnreadMessageId, anchor: .top)
										showScrollToBottomButton = true
									}
								}
							}
						}
					}
					.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
						withAnimation {
							scrollView.scrollTo("bottomAnchor", anchor: .bottom)
							hasReachedBottom = true
							showScrollToBottomButton = false
						}
					}
					.onChange(of: allPrivateMessages.count) {
						if hasReachedBottom {
							withAnimation {
								scrollView.scrollTo("bottomAnchor", anchor: .bottom)
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
					Text(String(channel.name ?? "Unknown".localized).camelCaseToWords()).font(.headline)
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {
					ConnectedDevice(
						deviceConnected: accessoryManager.isConnected,
						name: accessoryManager.activeConnection?.device.shortName ?? "?",
						// mqttProxyConnected defaults to false, so if it's not enabled it will still be false
						mqttProxyConnected: accessoryManager.mqttProxyConnected && (channel.uplinkEnabled || channel.downlinkEnabled),
						mqttUplinkEnabled: channel.uplinkEnabled,
						mqttDownlinkEnabled: channel.downlinkEnabled,
						mqttTopic: accessoryManager.mqttManager.topic
					)
				}
			}
		}
	}
}

