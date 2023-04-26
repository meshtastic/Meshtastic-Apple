//
//  UserMessageList.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import SwiftUI
import CoreData

struct UserMessageList: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	enum Field: Hashable {
		case messageText
	}
	// Keyboard State
	@State var typingMessage: String = ""
	@State private var totalBytes = 0
	var maxbytes = 228
	@FocusState var focusedField: Field?
	// View State Items
	@ObservedObject var user: UserEntity
	@State var showDeleteMessageAlert = false
	@State private var deleteMessageId: Int64 = 0
	@State private var replyMessageId: Int64 = 0
	@State private var sendPositionWithMessage: Bool = false

	var body: some View {
		NavigationStack {
			let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmmss", options: 0, locale: Locale.current)
			let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mm:ss:a")
			ScrollViewReader { scrollView in
				ScrollView {
					LazyVStack {
						ForEach( user.messageList ) { (message: MessageEntity) in
							if user.num != bleManager.connectedPeripheral?.num ?? -1 {
								let currentUser: Bool = (bleManager.connectedPeripheral?.num ?? 0 == message.fromUser?.num ?? -1 ? true : false)

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
													self.focusedField = .messageText
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
															Text("\(tapback.fromUser?.shortName ?? "????")")
																.font(.caption2)
																.foregroundColor(.gray)
																.fixedSize()
																.padding(.bottom, 1)
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
													Text("Implicit ACK from Unknown Node").font(.caption2).foregroundColor(.orange)
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
							}
						}
					}
				}
				.padding([.top])
				.scrollDismissesKeyboard(.immediately)
				.onAppear(perform: {
					self.bleManager.context = context
					if user.messageList.count > 0 {
						scrollView.scrollTo(user.messageList.last!.messageId)
					}
				})
				.onChange(of: user.messageList, perform: { _ in
					if user.messageList.count > 0 {
						scrollView.scrollTo(user.messageList.last!.messageId)
					}
				})
			}
			#if targetEnvironment(macCatalyst)
			HStack {
				Spacer()
				Button {
					let userLongName = bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown"
					sendPositionWithMessage = true

					if userSettings.meshtasticUsername.count > 0 {
						typingMessage =  "📍 " + userSettings.meshtasticUsername + " has shared their position with you from node " + userLongName + " and requested a response with your position."
					} else {
						typingMessage =  "📍 " + userLongName + " has shared their position and requested a response with your position."
					}

				} label: {
					Text("share.position")
					Image(systemName: "mappin.and.ellipse")
						.symbolRenderingMode(.hierarchical)
						.imageScale(.large).foregroundColor(.accentColor)
				}
				ProgressView("\(NSLocalizedString("bytes", comment: "")): \(totalBytes) / \(maxbytes)", value: Double(totalBytes), total: Double(maxbytes))
					.frame(width: 130)
					.padding(5)
					.font(.subheadline)
					.accentColor(.accentColor)
					.padding(.trailing)
			}
			#endif

			HStack(alignment: .top) {
				ZStack {
					TextField("message", text: $typingMessage, axis: .vertical)
						.onChange(of: typingMessage, perform: { value in
							totalBytes = value.utf8.count
							// Only mess with the value if it is too big
							if totalBytes > maxbytes {
								let firstNBytes = Data(typingMessage.utf8.prefix(maxbytes))
								if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
									// Set the message back to the last place where it was the right size
									typingMessage = maxBytesString
								} else {
									print("not a valid UTF-8 sequence")
								}
							}
						})
						.keyboardType(.default)
						.toolbar {
							ToolbarItemGroup(placement: .keyboard) {
								Button("dismiss.keyboard") {
									focusedField = nil
								}
								.font(.subheadline)
								Spacer()
								Button {
									let userLongName = bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown"
									sendPositionWithMessage = true

									if UserDefaults.meshtasticUsername.count > 0 {
										typingMessage =  "📍 " + UserDefaults.meshtasticUsername + " has shared their position with you from node " + userLongName + " and requested a response with your position."
									} else {
										typingMessage =  "📍 " + userLongName + " has shared their position and requested a response with your position."
									}

								} label: {
									Image(systemName: "mappin.and.ellipse")
										.symbolRenderingMode(.hierarchical)
										.imageScale(.large).foregroundColor(.accentColor)
								}
								ProgressView("\(NSLocalizedString("bytes", comment: "")): \(totalBytes) / \(maxbytes)", value: Double(totalBytes), total: Double(maxbytes))
									.frame(width: 130)
									.padding(5)
									.font(.subheadline)
									.accentColor(.accentColor)
							}
						}
						.padding(.horizontal, 8)
						.focused($focusedField, equals: .messageText)
						.multilineTextAlignment(.leading)
						.frame(minHeight: 50)
						.keyboardShortcut(.defaultAction)
						.onSubmit {
						#if targetEnvironment(macCatalyst)
							if bleManager.sendMessage(message: typingMessage, toUserNum: user.num, channel: 0, isEmoji: false, replyID: replyMessageId) {
								typingMessage = ""
								focusedField = nil
								replyMessageId = 0
								if sendPositionWithMessage {
									if bleManager.sendPosition(destNum: user.num, wantResponse: true, smartPosition: false) {
										print("Location Sent")
									}
								}
							}
						#endif
						}
					Text(typingMessage).opacity(0).padding(.all, 0)
				}
				.overlay(RoundedRectangle(cornerRadius: 20).stroke(.tertiary, lineWidth: 1))
				.padding(.bottom, 15)
				Button(action: {
					if bleManager.sendMessage(message: typingMessage, toUserNum: user.num, channel: 0, isEmoji: false, replyID: replyMessageId) {
						typingMessage = ""
						focusedField = nil
						replyMessageId = 0
						if sendPositionWithMessage {
							if bleManager.sendPosition(destNum: user.num, wantResponse: true, smartPosition: false) {
								print("Location Sent")
							}
						}
					}
				}) {
					Image(systemName: "arrow.up.circle.fill").font(.largeTitle).foregroundColor(.accentColor)
				}
			}
			.padding(.all, 15)
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				HStack {
					CircleText(text: user.shortName ?? "???", color: Color(UIColor(hex: UInt32(user.num))), circleSize: 44, fontSize: 14, textColor: UIColor(hex: UInt32(user.num)).isLight() ? .black : .white ).fixedSize()
					Text(user.longName ?? NSLocalizedString("unknown", comment: "Unknown")).font(.headline)
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
				}
			}
		}
	}
}
