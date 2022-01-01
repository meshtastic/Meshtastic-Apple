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
	
	@State var mergedMessageList: NSMutableOrderedSet?

    var body: some View {

//		HStack {

			VStack {
				
			//	List {

					ScrollViewReader { scrollView in

						ScrollView {
							// Use fetched property
							let allMessages = user.value(forKey: "allMessages")
								as! [MessageEntity]
							
							if allMessages.count > 0 {
								
								
								let mergedMessageList =  user.receivedMessages!.mutableCopy() as? NSMutableOrderedSet
								//mergedMessageList?.union(user.sentMessages!)
							 
							//	mergedMessageList?.append(<#T##Self.Output#>).addObjects(from: user.sentMessages!.mutableCopy() as! [Any])
							
								ForEach( user.receivedMessages?.array as! [MessageEntity], id: \.self) { (message: MessageEntity) in
									
							//		HStack {
										let currentUser: Bool = (bleManager.connectedPeripheral == nil) ? false : ((bleManager.connectedPeripheral != nil && bleManager.connectedPeripheral.num == message.fromUser?.num) ? true : false )
										
										
										if message.toUser!.num == Int64(bleManager.broadcastNodeNum) || ((bleManager.connectedPeripheral) != nil && bleManager.connectedPeripheral.num == message.fromUser?.num) ? true : true {
											
											
											HStack (alignment: .top) {
											
												if currentUser { Spacer(minLength:50) }
												
												if !currentUser {
												
													CircleText(text: (message.fromUser?.shortName ?? "???"), color: currentUser ? .accentColor : Color(.darkGray)).padding(.all, 5)
														.gesture(LongPressGesture(minimumDuration: 2).onEnded {_ in

															print("I want to delete message: \(message.messageId)")
															self.showDeleteMessageAlert = true
															self.deleteMessageId = message.messageId
															print(deleteMessageId)
													})
												}
												
												VStack(alignment: currentUser ? .trailing : .leading) {
													
													Text(message.messagePayload ?? "EMPTY MESSAGE")
													.textSelection(.enabled)
													.padding(10)
													.foregroundColor(.white)
													.background(currentUser ? Color.blue : Color(.darkGray))
													.cornerRadius(15)
													
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
												if !currentUser {
													Spacer(minLength:50)
												}
											}
											.padding(.trailing)
											.frame(maxWidth: .infinity)
										}
								//	}
								}
								.listRowSeparator(.hidden)
							}
						}
						.onAppear(perform: {
							
							self.bleManager.context = context
							if mergedMessageList?.count ?? 0 > 0 {
								scrollView.scrollTo((mergedMessageList![mergedMessageList!.count-1] as AnyObject).id, anchor: .bottom)
							}
						})
					}
					
			//	}
			//	.padding(.top)
				
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
						if bleManager.sendMessage(message: typingMessage, toUserNum: user.num) {
							typingMessage = ""
							focusedField = nil
						}

					}) {
						Image(systemName: "arrow.up.circle.fill").font(.largeTitle).foregroundColor(.blue)
					}

				}
				.padding(.all, 15)
			}
//		}
		.navigationViewStyle(.stack)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {

				HStack {

					CircleText(text: user.shortName ?? "???", color: .blue).fixedSize()
					Text(user.longName ?? "Unknown").foregroundColor(.gray).font(.caption2).fixedSize()
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
