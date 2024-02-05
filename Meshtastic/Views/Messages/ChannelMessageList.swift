//
//  UserMessageList.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import SwiftUI
import CoreData

struct ChannelMessageList: View {
	@StateObject var appState = AppState.shared
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	// Keyboard State
	@FocusState var messageFieldFocused: Bool

	@ObservedObject var myInfo: MyInfoEntity
	@ObservedObject var channel: ChannelEntity
	@State var showDeleteMessageAlert = false
	@State private var deleteMessageId: Int64 = 0
	@State private var replyMessageId: Int64 = 0
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1

	var body: some View {
		VStack {
			let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmmssa", options: 0, locale: Locale.current)
			let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mm:ss a")
			ScrollViewReader { scrollView in
				ScrollView {
					LazyVStack {
						ForEach( channel.allPrivateMessages ) { (message: MessageEntity) in
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
							HStack(alignment: .top) {
								if currentUser { Spacer(minLength: 50) }
								if !currentUser {
									CircleText(text: message.fromUser?.shortName ?? "?", color: Color(UIColor(hex: UInt32(message.fromUser?.num ?? 0))), circleSize: 44)
										.padding(.all, 5)
										.offset(y: -5)
								}
								VStack(alignment: currentUser ? .trailing : .leading) {
									let markdownText: LocalizedStringKey =  LocalizedStringKey.init(message.messagePayloadMarkdown ?? (message.messagePayload ?? "EMPTY MESSAGE"))
									let linkBlue = Color(red: 0.4627, green: 0.8392, blue: 1) /* #76d6ff */
									let isDetectionSensorMessage = message.portNum == Int32(PortNum.detectionSensorApp.rawValue)
									Text(markdownText)
										.tint(linkBlue)
										.padding(10)
										.foregroundColor(.white)
										.background(currentUser ? .accentColor : Color(.gray))
										.cornerRadius(15)
										.overlay(
											VStack {
												if #available(iOS 17.0, macOS 14.0, *) {
													isDetectionSensorMessage ? Image(systemName: "sensor.fill")
														.padding()
														.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
														.foregroundStyle(Color.orange)
														.symbolRenderingMode(.multicolor)
														.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
														.offset(x: 20, y: -20)
													: nil
												} else {
													isDetectionSensorMessage ? Image(systemName: "sensor.fill")
														.padding()
														.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
														.foregroundStyle(Color.orange)
														.offset(x: 20, y: -20)
													: nil
												}
											}
										)
										.contextMenu {
											VStack {
												Text("channel")+Text(": \(message.channel)")
											}
											Menu("tapback") {
												ForEach(Tapbacks.allCases) { tb in
													Button(action: {
														if bleManager.sendMessage(message: tb.emojiString, toUserNum: 0, channel: channel.index, isEmoji: true, replyID: message.messageId) {
															print("Sent \(tb.emojiString) Tapback")
															self.context.refresh(channel, mergeChanges: true)
														} else { print("\(tb.emojiString) Tapback Failed") }

													}) {
														Text(tb.description)
														let image = tb.emojiString.image()
														Image(uiImage: image!)
													}
												}
											}
											Button(action: {
												self.replyMessageId = message.messageId
												self.messageFieldFocused = true
												print("I want to reply to \(message.messageId)")
											}) {
												Text("reply")
												Image(systemName: "arrowshape.turn.up.left.2.fill")
											}
											Button(action: {
												UIPasteboard.general.string = message.messagePayload
											}) {
												Text("copy")
												Image(systemName: "doc.on.doc")
											}
											Menu("message.details") {
												VStack {
													let messageDate = Date(timeIntervalSince1970: TimeInterval(message.messageTimestamp))
													Text(" \(messageDate.formattedDate(format: dateFormatString))").foregroundColor(.gray)
												}
												if !currentUser {
													VStack {
														Text("SNR \(String(format: "%.2f", message.snr)) dB")
													}
												}
												if currentUser && message.receivedACK {
													VStack {
														Text("received.ack")+Text(" \(message.receivedACK ? "✔️" : "")")
													}
												} else if currentUser && message.ackError == 0 {
													// Empty Error
													Text("waiting")
												} else if currentUser && message.ackError > 0 {
													let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
													Text("\(ackErrorVal?.display ?? "Empty Ack Error")").fixedSize(horizontal: false, vertical: true)
												}
												if currentUser {
													VStack {
														let ackDate = Date(timeIntervalSince1970: TimeInterval(message.ackTimestamp))
														let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())
														if ackDate >= sixMonthsAgo! {
															Text("Ack Time: \(ackDate.formattedDate(format: "h:mm:ss a"))").foregroundColor(.gray)
														} else {
															Text("unknown.age").foregroundColor(.gray)
														}
													}
												}
												if message.ackSNR != 0 {
													VStack {
														Text("Ack SNR: \(String(format: "%.2f", message.ackSNR)) dB")
															.foregroundColor(.gray)
													}
												}
											}
											Divider()
											Button(role: .destructive, action: {
												self.showDeleteMessageAlert = true
												self.deleteMessageId = message.messageId
												print(deleteMessageId)
											}) {
												Text("delete")
												Image(systemName: "trash")
											}
										}
									let tapbacks = message.value(forKey: "tapbacks") as? [MessageEntity] ?? []
									if tapbacks.count > 0 {
										VStack(alignment: .trailing) {
											HStack {
												ForEach( tapbacks ) { (tapback: MessageEntity) in
													VStack {
														let image = tapback.messagePayload!.image(fontSize: 20)
														Image(uiImage: image!).font(.caption)
														Text("\(tapback.fromUser?.shortName ?? "?")")
															.font(.caption2)
															.foregroundColor(.gray)
															.fixedSize()
															.padding(.bottom, 1)
													}
													.onAppear {
														if !tapback.read {
															tapback.read = true
															do {
																try context.save()
																print("📖 Read message \(message.messageId) ")
																appState.unreadChannelMessages = myInfo.unreadMessages
																UIApplication.shared.applicationIconBadgeNumber = appState.unreadChannelMessages + appState.unreadDirectMessages
																context.refresh(myInfo, mergeChanges: true)
															} catch {
																print("Failed to read tapback \(tapback.messageId)")
															}
														}
													}
												}
											}
											.padding(10)
											.overlay(
												RoundedRectangle(cornerRadius: 18)
													.stroke(Color.gray, lineWidth: 1)
											)
										}
									}
					
									HStack {
										if currentUser && message.receivedACK {
											// Ack Received
											Text("Acknowledged").font(.caption2).foregroundColor(.gray)
										} else if currentUser && message.ackError == 0 {
											// Empty Error
											Text("Waiting to be acknowledged. . .").font(.caption2).foregroundColor(.orange)
										} else if currentUser && message.ackError > 0 {
											let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
											Text("\(ackErrorVal?.display ?? "Empty Ack Error")").fixedSize(horizontal: false, vertical: true)
												.font(.caption2).foregroundColor(.red)
										} else if isDetectionSensorMessage {
											let messageDate = message.timestamp
											Text(" \(messageDate.formattedDate(format: dateFormatString))").font(.caption2).foregroundColor(.gray)
										}
									}
								}
								.padding(.bottom)
								.id(channel.allPrivateMessages.firstIndex(of: message))

								if currentUser && message.ackError > 0 {
									RetryButton(message: message)
								}

								if !currentUser {
									Spacer(minLength: 50)
								}
							}
							.padding([.leading, .trailing])
							.frame(maxWidth: .infinity)
							.id(message.messageId)
							.alert(isPresented: $showDeleteMessageAlert) {
								Alert(title: Text("Are you sure you want to delete this message?"), message: Text("This action is permanent."), primaryButton: .destructive(Text("Delete")) {
									print("OK button tapped")
									if deleteMessageId > 0 {
										let message = channel.allPrivateMessages.first(where: { $0.messageId == deleteMessageId })
										context.delete(message!)
										do {
											try context.save()
											deleteMessageId = 0
										} catch {
											print("Failed to delete message \(deleteMessageId)")
										}
									}
								}, secondaryButton: .cancel())
							}
							.onAppear {
								if !message.read {
									message.read = true
									do {
										try context.save()
										print("📖 Read message \(message.messageId) ")
										appState.unreadChannelMessages = myInfo.unreadMessages
										UIApplication.shared.applicationIconBadgeNumber = appState.unreadChannelMessages + appState.unreadDirectMessages
										context.refresh(myInfo, mergeChanges: true)
									} catch {
										print("Failed to read message \(message.messageId)")
									}
								}
							}
						}
					}
				}
				.padding([.top])
				.scrollDismissesKeyboard(.immediately)
				.onAppear {
					if self.bleManager.context == nil {
						self.bleManager.context = context
					}
					if channel.allPrivateMessages.count > 0 {
						scrollView.scrollTo(channel.allPrivateMessages.last!.messageId)
					}
				}
				.onChange(of: channel.allPrivateMessages, perform: { _ in
					if channel.allPrivateMessages.count > 0 {
						scrollView.scrollTo(channel.allPrivateMessages.last!.messageId)
					}
				})
			}
			
			TextMessageField(
				destination: .channel(channel.index),
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
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
				}
			}
		}
	}
}
