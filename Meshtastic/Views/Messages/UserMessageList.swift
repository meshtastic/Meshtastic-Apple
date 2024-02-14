//
//  UserMessageList.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import SwiftUI
import CoreData

struct UserMessageList: View {
	@StateObject var appState = AppState.shared
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	// Keyboard State
	@FocusState var messageFieldFocused: Bool
	// View State Items
	@ObservedObject var user: UserEntity
	@State var showDeleteMessageAlert = false
	@State private var deleteMessageId: Int64 = 0
	@State private var replyMessageId: Int64 = 0

	var body: some View {
		VStack {
			let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmmss", options: 0, locale: Locale.current)
			let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mm:ss:a")
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
										let markdownText: LocalizedStringKey =  LocalizedStringKey.init(message.messagePayloadMarkdown ?? (message.messagePayload ?? "EMPTY MESSAGE"))

										let linkBlue = Color(red: 0.4627, green: 0.8392, blue: 1) /* #76d6ff */
										Text(markdownText)
											.tint(linkBlue)
											.padding(10)
											.foregroundColor(.white)
											.background(currentUser ? .accentColor : Color(.gray))
											.cornerRadius(15)
											.contextMenu {
												VStack {
													Text("channel")+Text(": \(message.channel)")
												}
												Menu("tapback") {
													ForEach(Tapbacks.allCases) { tb in
														Button(action: {
															if bleManager.sendMessage(message: tb.emojiString, toUserNum: user.num, channel: 0, isEmoji: true, replyID: message.messageId) {
																print("Sent \(tb.emojiString) Tapback")
																self.context.refresh(user, mergeChanges: true)
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
														Text("\(messageDate.formattedDate(format: dateFormatString))").foregroundColor(.gray)
													}
													if !currentUser {
														VStack {
															Text("SNR \(String(format: "%.2f", message.snr)) dB")
														}
													}
													if currentUser && message.receivedACK {
														VStack {
															Text("received.ack")+Text(" \(message.receivedACK ? "✔️" : "")")
															Text("received.ack.real")+Text(" \(message.realACK ? "✔️" : "")")
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
																Text("Ack Time: \(ackDate.formattedDate(format: "h:mm:ss.SSSS  a"))").foregroundColor(.gray)
															} else {
																Text("unknown.age").font(.caption2).foregroundColor(.gray)
															}
														}
													}
													if message.ackSNR != 0 {
														VStack {
															Text("Ack SNR: \(String(format: "%.2f", message.ackSNR)) dB")
																.font(.caption2)
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
																	print("📖 Read tapback \(tapback.messageId) ")
																	appState.unreadDirectMessages = user.unreadMessages
																	UIApplication.shared.applicationIconBadgeNumber = appState.unreadChannelMessages + appState.unreadDirectMessages

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
											let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
											if currentUser && message.receivedACK {
												// Ack Received
												if message.realACK {
													Text("\(ackErrorVal?.display ?? "Empty Ack Error")").font(.caption2).foregroundColor(.gray)
												} else {
													Text("Implicit ACK from another node").font(.caption2).foregroundColor(.orange)
												}
											} else if currentUser && message.ackError == 0 {
												// Empty Error
												Text("Waiting to be acknowledged. . .").font(.caption2).foregroundColor(.orange)
											} else if currentUser && message.ackError > 0 {
												Text("\(ackErrorVal?.display ?? "Empty Ack Error")").fixedSize(horizontal: false, vertical: true)
													.font(.caption2).foregroundColor(.red)
											}
										}
									}
									.padding(.bottom)
									.id(user.messageList.firstIndex(of: message))

									if currentUser && (message.receivedACK && !message.realACK) {
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
										if deleteMessageId > 0 {
											let message = user.messageList.first(where: { $0.messageId == deleteMessageId })
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
											appState.unreadDirectMessages = user.unreadMessages
											UIApplication.shared.applicationIconBadgeNumber = appState.unreadChannelMessages + appState.unreadDirectMessages

										} catch {
											print("Failed to read message \(message.messageId)")
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
					if self.bleManager.context == nil {
						self.bleManager.context = context
					}
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
				destination: .user(user.num),
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
