//
//  ChannelMessageList.swift
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
	@FocusState var messageFieldFocused: Bool
	@ObservedObject var myInfo: MyInfoEntity
	@ObservedObject var channel: ChannelEntity
	@State private var replyMessageId: Int64 = 0
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
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
	
	var body: some View {
		NavigationStack {
			ScrollViewReader { scrollView in
				ScrollView {
					LazyVStack {
						ForEach(allPrivateMessages) { message in
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
											Task {
												try? await Task.sleep(nanoseconds: 1_000_000_000)
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
											Text("Waiting to be acknowledged. . .").font(.caption2).foregroundColor(.orange)
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
							.padding([.leading, .trailing])
							.frame(maxWidth: .infinity)
							.id(message.messageId)
							.onAppear {
								markMessagesAsRead()
							}
						}
						Color.clear
							.frame(height: 1)
							.id("bottomAnchor")
					}
				}
				.defaultScrollAnchor(.bottom)
				.defaultScrollAnchorBottomSizeChanges()
				.scrollDismissesKeyboard(.immediately)
				.onChange(of: messageFieldFocused) {
					if messageFieldFocused {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
							scrollView.scrollTo("bottomAnchor", anchor: .bottom)
						}
					}
				}
				.safeAreaInset(edge: .bottom) {
					TextMessageField(
						destination: .channel(channel),
						replyMessageId: $replyMessageId,
						isFocused: $messageFieldFocused
					)
					.background(.bar)
				}
			}
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
		}
	}
}
