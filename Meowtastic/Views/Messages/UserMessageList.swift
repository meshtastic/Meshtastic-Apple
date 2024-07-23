import SwiftUI
import CoreData
import OSLog

struct UserMessageList: View {
	@StateObject
	var appState = AppState.shared
	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager
	@FocusState
	var messageFieldFocused: Bool
	@ObservedObject
	var user: UserEntity

	@State
	private var replyMessageId: Int64 = 0

	var body: some View {
		VStack {
			ScrollViewReader { scrollView in
				messageList
					.padding([.top])
					.scrollDismissesKeyboard(.immediately)
					.onChange(of: user.messageList, initial: true) {
						if let messageId = user.messageList?.last?.messageId {
							scrollView.scrollTo(messageId)
						}
					}
			}

			TextMessageField(
				destination: .user(user),
				onSubmit: {
					context.refresh(user, mergeChanges: true)
				},
				replyMessageId: $replyMessageId,
				isFocused: $messageFieldFocused
			)
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				if let name = user.longName {
					Text(name)
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ConnectedDevice(ble: bleManager)
			}
		}
	}

	@ViewBuilder
	private var messageList: some View {
		if let messageList = user.messageList {
			List(messageList) { message in
				if user.num != bleManager.connectedPeripheral?.num ?? -1 {
					let currentUser = (Int64(UserDefaults.preferredPeripheralNum) == message.fromUser?.num ?? -1 ? true : false)
					
					if message.replyID > 0 {
						let messageReply = messageList.first(where: {
							$0.messageId == message.replyID
						})
						
						HStack {
							Text(messageReply?.messagePayload ?? "EMPTY MESSAGE")
								.foregroundColor(.accentColor)
								.font(.caption2)
								.padding(10)
								.overlay(
									RoundedRectangle(cornerRadius: 18)
										.stroke(Color.blue, lineWidth: 0.5)
								)
							
							Image(systemName: "arrowshape.turn.up.left.fill")
								.symbolRenderingMode(.hierarchical)
								.imageScale(.large)
								.foregroundColor(.accentColor)
								.padding(.trailing)
						}
					}
					
					HStack(alignment: .top) {
						if currentUser {
							Spacer(minLength: 50)
						}
						
						VStack(alignment: currentUser ? .trailing : .leading) {
							HStack {
								MessageView(
									message: message,
									originalMessage: nil,
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
								
								let badge = appState.unreadChannelMessages + appState.unreadDirectMessages
								UNUserNotificationCenter.current().setBadgeCount(badge)
							}
							
							HStack {
								let ackErrorVal = RoutingError(rawValue: Int(message.ackError))
								
								if currentUser && message.receivedACK {
									// Ack Received
									if message.realACK {
										Text("\(ackErrorVal?.display ?? "Empty Ack Error")")
											.font(.caption2)
											.foregroundColor(.gray)
									} else {
										Text("Acknowledged by another node")
											.font(.caption2)
											.foregroundColor(.orange)
									}
								} else if currentUser && message.ackError == 0 {
									// Empty Error
									Text("Waiting to be acknowledged. . .")
										.font(.caption2)
										.foregroundColor(.yellow)
								} else if currentUser && message.ackError > 0 {
									Text("\(ackErrorVal?.display ?? "Empty Ack Error")")
										.fixedSize(horizontal: false, vertical: true)
										.font(.caption2)
										.foregroundColor(.red)
								}
							}
						}
						.padding(.bottom)
						.id(messageList.firstIndex(of: message))
						
						if !currentUser {
							Spacer(minLength: 50)
						}
					}
					.padding([.leading, .trailing])
					.frame(maxWidth: .infinity)
					.id(message.messageId)
					.onAppear {
						guard !message.read else {
							return
						}
						
						message.read = true
						try? context.save()
						
						appState.unreadDirectMessages = user.unreadMessages
						
						let badge = appState.unreadChannelMessages + appState.unreadDirectMessages
						UNUserNotificationCenter.current().setBadgeCount(badge)
					}
				}
			}
		}
		else {
			EmptyView()
		}
	}
}
