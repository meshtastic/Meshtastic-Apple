import CoreData
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct ChannelMessageList: View {
	@StateObject
	var appState = AppState.shared
	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager
	@FocusState
	var messageFieldFocused: Bool
	@ObservedObject
	var myInfo: MyInfoEntity
	@ObservedObject
	var channel: ChannelEntity

	@AppStorage("preferredPeripheralNum")
	private var preferredPeripheralNum = -1
	@State
	private var replyMessageId: Int64 = 0

	private var screenTitle: String {
		if let name = channel.name, !name.isEmpty {
			name.camelCaseToWords()
		}
		else {
			if channel.role == 1 {
				"Primary Channel"
			}
			else {
				"Channel #\(channel.index)"
			}
		}
	}

	var body: some View {
		VStack {
			ScrollViewReader { scrollView in
				ScrollView {
					messageList
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
				.onChange(of: channel.allPrivateMessages, initial: true) {
					if channel.allPrivateMessages.count > 0 {
						scrollView.scrollTo(channel.allPrivateMessages.last!.messageId)
					}
				}
			}

			TextMessageField(
				destination: .channel(channel),
				onSubmit: {
					context.refresh(channel, mergeChanges: true)
				},
				replyMessageId: $replyMessageId,
				isFocused: $messageFieldFocused
			)
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				Text(screenTitle)
					.font(.headline)
			}

			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {
					ConnectedDevice(
						ble: bleManager,
						mqttProxyConnected: bleManager.mqttProxyConnected && (channel.uplinkEnabled || channel.downlinkEnabled),
						mqttUplinkEnabled: channel.uplinkEnabled,
						mqttDownlinkEnabled: channel.downlinkEnabled,
						mqttTopic: bleManager.mqttManager.topic
					)
				}
			}
		}
	}

	@ViewBuilder
	private var messageList: some View {
		ForEach(channel.allPrivateMessages) { message in
			let currentUser = (Int64(preferredPeripheralNum) == message.fromUser?.num ? true : false)

			if message.replyID > 0 {
				let messageReply = channel.allPrivateMessages.first(where: {
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
						.imageScale(.large).foregroundColor(.accentColor)
						.padding(.trailing)
				}
			}

			HStack(alignment: .bottom) {
				if currentUser {
					Spacer(minLength: 50)
				}
				else {
					Avatar(
						message.fromUser?.shortName ?? "?",
						background: Color(UIColor(hex: UInt32(message.fromUser?.num ?? 0))),
						size: 44
					)
					.padding(.all, 5)
					.offset(y: -7)
				}

				VStack(alignment: currentUser ? .trailing : .leading) {
					let isDetectionSensorMessage = message.portNum == Int32(PortNum.detectionSensorApp.rawValue)

					if !currentUser && message.fromUser != nil {
						Text(
							"\(message.fromUser?.longName ?? "unknown".localized ) (\(message.fromUser?.userId ?? "?"))"
						)
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

						let badge = appState.unreadChannelMessages + appState.unreadDirectMessages
						UNUserNotificationCenter.current().setBadgeCount(badge)

						context.refresh(myInfo, mergeChanges: true)
					}

					HStack {
						if currentUser && message.receivedACK {
							// Ack Received
							Text("Acknowledged")
								.font(.caption2)
								.foregroundColor(.gray)
						} else if currentUser && message.ackError == 0 {
							// Empty Error
							Text("Waiting to be acknowledged. . .")
								.font(.caption2)
								.foregroundColor(.orange)
						} else if currentUser && message.ackError > 0 {
							let ackErrorVal = RoutingError(rawValue: Int(message.ackError))

							Text("\(ackErrorVal?.display ?? "Empty Ack Error")")
								.fixedSize(horizontal: false, vertical: true)
								.font(.caption2)
								.foregroundColor(.red)
						} else if isDetectionSensorMessage {
							let messageDate = message.timestamp
							Text(" \(messageDate.formattedDate(format: MessageText.dateFormatString))").font(.caption2).foregroundColor(.gray)
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
				if !message.read {
					message.read = true

					do {
						try context.save()

						Logger.data.info("📖 [App] Read message \(message.messageId) ")

						appState.unreadChannelMessages = myInfo.unreadMessages

						let badge = appState.unreadChannelMessages + appState.unreadDirectMessages
						UNUserNotificationCenter.current().setBadgeCount(badge)

						context.refresh(myInfo, mergeChanges: true)
					} catch {
						Logger.data.error("Failed to read message \(message.messageId): \(error.localizedDescription)")
					}
				}
			}
		}
	}
}
