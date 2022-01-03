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
	
	enum Field: Hashable {
		case messageText
	}
	// Keyboard State
	@State var typingMessage: String = ""
	@State private var totalBytes = 0
	var maxbytes = 228
	@State var lastTypingMessage = ""
	@FocusState var focusedField: Field?

	var user: UserEntity
	
	@State var showDeleteMessageAlert = false
	@State private var deleteMessageId: Int64 = 0
	@State private var replyMessageId: Int64 = 0
	
	@State var messageCount = 0

    var body: some View {

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
												Menu("Tapback response") {
													Button(action: {
													// Send Heart Tapback
													}) {
														Text("Heart")
														let image = "❤️".image()
														Image(uiImage: image!)
													}
													Button(action: {
													// Send Heart Tapback
													}) {
														Text("Thumbs Up")
														let image = "👍".image()
														Image(uiImage: image!)
													}
													Button(action: {
													// Send Heart Tapback
													}) {
														Text("Thumbs Down")
														let image = "👎".image()
														Image(uiImage: image!)
													}
													Button(action: {
													// Send ROFL Tapback
													}) {
														Text("HaHa")
														let image = "🤣".image()
														Image(uiImage: image!)
													}
													Button(action: {
													// Send Heart Tapback
													}) {
														Text("Exclamation Mark")
														let image = "‼️".image()
														Image(uiImage: image!)
													}
													Button(action: {
													// Send Heart Tapback
													}) {
														Text("Question Mark")
														let image = "❓".image()
														Image(uiImage: image!)
													}
													Button(action: {
													// Send Poop Tapback
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
												Button(action: {
													UIPasteboard.general.string = message.messagePayload
												}) {
													Text("Copy")
													Image(systemName: "doc.on.doc")
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
											
											
//											VStack (alignment: .trailing) {
//
//												HStack  {
//													let image = "❤️".image(fontSize: 26)
//													Image(uiImage: image!).font(.caption)
//													CircleText(text: "AKA", color: .blue, circleSize: 28, fontSize: 11)
//												}
//												.padding(0)
//											}

											HStack(spacing: 4) {

												let time = Int32(message.messageTimestamp)
												let messageDate = Date(timeIntervalSince1970: TimeInterval(time))

												if time != 0 {
													Text(messageDate, style: .date).font(.caption2).foregroundColor(.gray)
													Text(messageDate, style: .time).font(.caption2).foregroundColor(.gray)
												} else {
													Text("Unknown").font(.caption2).foregroundColor(.gray)
												}
											}
											.padding(.bottom, 10)
										}
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
				
					messageCount = ((user.sentMessages?.count ?? 0) + (user.receivedMessages?.count ?? 0))
					
					if messageCount > 0 {
						scrollView.scrollTo(allMessages.firstIndex(of: allMessages.last! ), anchor: .bottom)
					}
				})
				.onChange(of: user, perform: { newValue in
					
					messageCount =  ((user.sentMessages?.count ?? 0) + (user.receivedMessages?.count ?? 0))
					
					if messageCount > 0 {
						
						scrollView.scrollTo(allMessages.firstIndex(of: allMessages.last! ), anchor: .bottom)
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
					if bleManager.sendMessage(message: typingMessage, toUserNum: user.num, replyTo: replyMessageId) {
						typingMessage = ""
						focusedField = nil
						replyMessageId = 0
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
		.onAppear(perform: {

			self.bleManager.context = context

		})
    }
}
