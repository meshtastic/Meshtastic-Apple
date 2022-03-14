//
//  UserMessageList.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import SwiftUI
import CoreData

struct UserMessageList: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
	
	enum Field: Hashable {
		case messageText
	}
	// Keyboard State
	@State var typingMessage: String = ""
	@State private var totalBytes = 0
	var maxbytes = 228
	@State var lastTypingMessage = ""
	@FocusState var focusedField: Field?

	@ObservedObject var user: UserEntity
	
	@State var showDeleteMessageAlert = false
	@State private var deleteMessageId: Int64 = 0
	@State private var replyMessageId: Int64 = 0
	@State private var sendPositionWithMessage: Bool = false
	
	@State var messageCount = 0

    var body: some View {
		
		let firmwareVersion = bleManager.lastConnnectionVersion
		let minimumVersion = "1.2.52"
		let hasTapbackSupport = minimumVersion.compare(firmwareVersion, options: .numeric) == .orderedAscending || minimumVersion.compare(firmwareVersion, options: .numeric) == .orderedSame
		
		VStack {
			
			let allMessages = user.value(forKey: "allMessages") as! [MessageEntity]

			ScrollViewReader { scrollView in

				ScrollView {
					
					if allMessages.count > 0 {
						
						HStack{
						// Padding at the top of the message list
						}.padding(.bottom)
						
						ForEach( allMessages ) { (message: MessageEntity) in
							
								let currentUser: Bool = (bleManager.connectedPeripheral == nil) ? false : ((bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.num == message.fromUser?.num) ? true : false )
								
								if message.toUser!.num == Int64(bleManager.broadcastNodeNum) || ((bleManager.connectedPeripheral) != nil && bleManager.connectedPeripheral.num == message.fromUser?.num) ? true : true {
									
									if message.replyID > 0 {
										
										let messageReply = allMessages.first(where: { $0.messageId == message.replyID })
										
										HStack {

											Text(messageReply?.messagePayload ?? "EMPTY MESSAGE").foregroundColor(.blue).font(.caption2)
												.padding(10)
												.overlay(
													RoundedRectangle(cornerRadius: 18)
														.stroke(Color.blue, lineWidth: 0.5)
											)
											Image(systemName: "arrowshape.turn.up.left.fill")
												.symbolRenderingMode(.hierarchical)
												.imageScale(.large).foregroundColor(.blue)
												.padding(.trailing)
										}
									}
									
									HStack (alignment: .top) {
									
										if currentUser { Spacer(minLength:50) }
										
										if !currentUser {
											CircleText(text: message.fromUser?.shortName ?? "???", color: currentUser ? .accentColor : Color(.darkGray), circleSize: 36, fontSize: 16).padding(.all, 5)
										}
										
										VStack(alignment: currentUser ? .trailing : .leading) {
											
											Text(message.messagePayload ?? "EMPTY MESSAGE")
											.padding(10)
											.foregroundColor(.white)
											.background(currentUser ? Color.blue : Color(.darkGray))
											.cornerRadius(15)
											.contextMenu {
												
												if hasTapbackSupport {
												
													Menu("Tapback response") {
														
														Button(action: {
															
															if bleManager.sendMessage(message: "❤️", toUserNum: user.num, isTapback: true, replyID: message.messageId) {
																
																print("Sent ❤️ Tapback")
																self.context.refresh(user, mergeChanges: true)
																
															} else { print("❤️ Tapback Failed") }
															
														}) {
															Text("Heart")
															let image = "❤️".image()
															Image(uiImage: image!)
														}
														Button(action: {
															
															if bleManager.sendMessage(message: "👍", toUserNum: user.num, isTapback: true, replyID: message.messageId) {
																
																print("Sent 👍 Tapback")
																self.context.refresh(user, mergeChanges: true)
																
															} else { print("👍 Tapback Failed")}
															
														}) {
															Text("Thumbs Up")
															let image = "👍".image()
															Image(uiImage: image!)
														}
														Button(action: {
															
															if bleManager.sendMessage(message: "👎", toUserNum: user.num, isTapback: true, replyID: message.messageId) {
																
																print("Sent 👎 Tapback")
																self.context.refresh(user, mergeChanges: true)
																
															} else { print("👎 Tapback Failed") }
															
														}) {
															Text("Thumbs Down")
															let image = "👎".image()
															Image(uiImage: image!)
														}
														Button(action: {
															
															if bleManager.sendMessage(message: "🤣", toUserNum: user.num, isTapback: true, replyID: message.messageId) {
																
																print("Sent 🤣 Tapback")
																self.context.refresh(user, mergeChanges: true)
																
															} else { print("🤣 Tapback Failed") }
															
														}) {
															Text("HaHa")
															let image = "🤣".image()
															Image(uiImage: image!)
														}
														Button(action: {
									
															if bleManager.sendMessage(message: "‼️", toUserNum: user.num, isTapback: true, replyID: message.messageId) {
																
																print("Sent ‼️ Tapback")
																self.context.refresh(user, mergeChanges: true)
																
															} else { print("‼️ Tapback Failed") }
															
														}) {
															Text("Exclamation Mark")
															let image = "‼️".image()
															Image(uiImage: image!)
														}
														Button(action: {
															
															if bleManager.sendMessage(message: "❓", toUserNum: user.num, isTapback: true, replyID: message.messageId) {
																
																print("Sent ❓ Tapback")
																self.context.refresh(user, mergeChanges: true)
																
															} else { print("❓ Tapback Failed") }
															
														}) {
															Text("Question Mark")
															let image = "❓".image()
															Image(uiImage: image!)
														}
														Button(action: {
														
															if bleManager.sendMessage(message: "💩", toUserNum: user.num, isTapback: true, replyID: message.messageId) {
																
																print("Sent 💩 Tapback")
																self.context.refresh(user, mergeChanges: true)
																
															} else { print("💩 Tapback Failed") }
															
														}) {
															Text("Poop")
															let image = "💩".image()
															Image(uiImage: image!)
														}
													}
													Button(action: {
														self.replyMessageId = message.messageId
														self.focusedField = .messageText
			
														print("I want to reply to \(message.messageId)")
													}) {
														Text("Reply")
														Image(systemName: "arrowshape.turn.up.left.2.fill")
													}
												}
												Button(action: {
													UIPasteboard.general.string = message.messagePayload
												}) {
													Text("Copy")
													Image(systemName: "doc.on.doc")
												}
												Menu("Message Details") {
													
													VStack {
														
														let messageDate = Date(timeIntervalSince1970: TimeInterval(message.messageTimestamp))

														Text("Sent \(messageDate, style: .date) \(messageDate, style: .time)").font(.caption2).foregroundColor(.gray)
													}
													
													VStack {
																
														Text("Received ACK: \(message.receivedACK ? "✔️" : "")")
														
													}
													if message.receivedACK {
														VStack {
															
															let ackDate = Date(timeIntervalSince1970: TimeInterval(message.ackTimestamp))
															Text("ACK \(ackDate, style: .date) \(ackDate, style: .time)").font(.caption2).foregroundColor(.gray)
														}
													}
													if message.ackSNR != 0 {
														VStack {
															
															Text("ACK SNR \(String(message.ackSNR))")
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
													Text("Delete")
													Image(systemName: "trash")
												}
											}
											
											if hasTapbackSupport {
											
												let tapbacks = message.value(forKey: "tapbacks") as! [MessageEntity]
												
											
												if tapbacks.count > 0 {
													
													VStack (alignment: .trailing) {

														HStack  {
															
															ForEach( tapbacks ) { (tapback: MessageEntity) in
															
																VStack {
																	
																	let image = tapback.messagePayload!.image(fontSize: 20)
																	Image(uiImage: image!).font(.caption)
																	Text("\(tapback.fromUser?.shortName ?? "???")")
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
											}
											
											HStack {

												let time = Int32(message.messageTimestamp)
												let messageDate = Date(timeIntervalSince1970: TimeInterval(time))
												let showUntil = Date().addingTimeInterval(3600)
												
												if messageDate <= showUntil && message.receivedACK {

													Text("Delivered").font(.caption2).foregroundColor(.gray)
												}
											}
											
										}
										.padding(.bottom)
										.id(allMessages.firstIndex(of: message))
										
										if !currentUser {
											Spacer(minLength:50)
										}
									}
									.padding([.leading, .trailing])
									.frame(maxWidth: .infinity)
									.alert(isPresented: $showDeleteMessageAlert) {
										Alert(title: Text("Are you sure you want to delete this message?"), message: Text("This action is permanent."),
										primaryButton: .destructive(Text("Delete")) {
										print("OK button tapped")
										if deleteMessageId > 0 {

											let message = allMessages.first(where: { $0.messageId == deleteMessageId })

											context.delete(message!)
											do {
												try context.save()

												deleteMessageId = 0

											} catch {
													print("Failed to delete message \(deleteMessageId)")
											}
										}
									},
									secondaryButton: .cancel()
									)
								}
							}
						}
						.listRowSeparator(.hidden)
					}
				}
				.onAppear(perform: {
					
					self.bleManager.context = context
					self.bleManager.userSettings = userSettings
				
					if allMessages.count > 1 {
						
						withAnimation(Animation.spring().delay(1)) {
							scrollView.scrollTo(allMessages.firstIndex(of: allMessages.last! ), anchor: .bottom)
						}
					}
				})
				.onChange(of: allMessages.count, perform: { count in
					
					if count > 1 {
					
						withAnimation(Animation.spring().delay(1)) {
							scrollView.scrollTo(allMessages.firstIndex(of: allMessages.last! ), anchor: .bottom)
						}
					}
				})
			}
				
			
			HStack(alignment: .top) {

				ZStack {

					let kbType = UIKeyboardType(rawValue: UserDefaults.standard.object(forKey: "keyboardType") as? Int ?? 0)
					TextEditor(text: $typingMessage)
						.onChange(of: typingMessage, perform: { value in

							let size = value.utf8.count
							totalBytes = size
							if totalBytes <= maxbytes {
								// Allow the user to type
								lastTypingMessage = typingMessage
							} else {
								// Set the message back and remove the bytes over the count
								self.typingMessage = lastTypingMessage
							}
						})
						.keyboardType(kbType!)
						.toolbar {
							ToolbarItemGroup(placement: .keyboard) {

								Button("Dismiss Keyboard") {
									focusedField = nil
								}
								.font(.subheadline)

								Spacer()
								
								Button {
									let userLongName = bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown"
									sendPositionWithMessage = true
									if user.num == bleManager.broadcastNodeNum {
										
										if userSettings.meshtasticUsername.count > 0 {
										
											typingMessage =  "📍 " + userSettings.meshtasticUsername + " has shared their position with the mesh from node " + userLongName
										} else {
											
											typingMessage =  "📍 " + userLongName + " has shared their position with the mesh."
											
										}
										
									} else {
										
										if userSettings.meshtasticUsername.count > 0 {
											
											typingMessage =  "📍 " + userSettings.meshtasticUsername + " has shared their position with you from node " + userLongName
											
										} else {
											
											typingMessage =  "📍 " + userLongName + " has shared their position with you."
										}
									}
								} label: {
									Image(systemName: "mappin.and.ellipse")
										.symbolRenderingMode(.hierarchical)
										.imageScale(.large).foregroundColor(.accentColor)
								}

								ProgressView("Bytes: \(totalBytes) / \(maxbytes)", value: Double(totalBytes), total: Double(maxbytes))
									.frame(width: 130)
									.padding(5)
									.font(.subheadline)
									.accentColor(.accentColor)
							}
						}
						.padding(.horizontal, 8)
						.focused($focusedField, equals: .messageText)
						.multilineTextAlignment(.leading)
						.frame(minHeight: 100, maxHeight: 160)

					Text(typingMessage).opacity(0).padding(.all, 0)

				}
				.overlay(RoundedRectangle(cornerRadius: 20).stroke(.tertiary, lineWidth: 1))
				.padding(.bottom, 15)

				Button(action: {
					if bleManager.sendMessage(message: typingMessage, toUserNum: user.num, isTapback: false, replyID: replyMessageId) {
						typingMessage = ""
						focusedField = nil
						replyMessageId = 0
						if sendPositionWithMessage {
							if bleManager.sendPosition(destNum: user.num, wantResponse: false) {
								print("Position Sent")
							}
						}
					}

				}) {
					Image(systemName: "arrow.up.circle.fill").font(.largeTitle).foregroundColor(.blue)
				}

			}
			.padding(.all, 15)
		}

		.navigationViewStyle(.stack)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {

				HStack {

					CircleText(text: user.shortName ?? "???", color: .blue, circleSize: 42, fontSize: 20).fixedSize()
					Text(user.longName ?? "Unknown").font(.headline).fixedSize()
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {

					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "???")
				}
			}
		}
    }
}
