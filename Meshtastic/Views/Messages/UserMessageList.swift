//
//  UserMessageList.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 12/24/21.
//

import SwiftUI
import SwiftData
import OSLog
import MeshtasticProtobufs // Added to ensure RoutingError is accessible if needed

struct UserMessageList: View {
	@EnvironmentObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.scenePhase) var scenePhase
	@Environment(\.modelContext) private var context
	@FocusState var messageFieldFocused: Bool
	@Bindable var user: UserEntity
	@State private var replyMessageId: Int64 = 0
	@State private var messageToHighlight: Int64 = 0
	@State private var redrawTapbacksTrigger = UUID()
	@AppStorage("preferredPeripheralNum") private var preferredPeripheralNum = -1
	@State private var tapbackTargetMessage: MessageEntity?
	@State private var tapbackText = ""
	@FocusState var tapbackFocused: Bool
	@Query private var allPrivateMessages: [MessageEntity]

	init(user: UserEntity) {
		self.user = user
		let userNum = user.num
		let detectionSensorPortNum: Int32 = 10
		_allPrivateMessages = Query(
			filter: #Predicate<MessageEntity> {
				($0.fromUser?.num == userNum || $0.toUser?.num == userNum)
				&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
			},
			sort: \MessageEntity.messageTimestamp
		)
	}

	func handleInteractionComplete() {
		markMessagesAsRead()
		redrawTapbacksTrigger = UUID()
	}

	func markMessagesAsRead() {
		do {
			for unreadMessage in allPrivateMessages.filter({ !$0.read }) {
				unreadMessage.read = true
			}
			try context.save()
			Logger.data.info("📖 [App] All unread direct messages marked as read for user \(user.num, privacy: .public).")

			if let connectedPeripheralNum = accessoryManager.activeDeviceNum,
			   let connectedNode = getNodeInfo(id: connectedPeripheralNum, context: context),
			   let connectedUser = connectedNode.user {
				appState.unreadDirectMessages = connectedUser.unreadMessages(context: context, skipLastMessageCheck: true) // skipLastMessageCheck=true because we don't update lastMessage on our own connected node
			}
		} catch {
			Logger.data.error("Failed to read direct messages: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func routerIsShowingThisUser() -> Bool {
		guard appState.router.selectedTab == .messages else { return false }
		return scenePhase == .active
	}

	private func processTapback() {
		guard !tapbackText.isEmpty, let target = tapbackTargetMessage else { return }
		let emojiToSend = tapbackText
		let destination = MessageDestination.user(user)

		Task {
			do {
				try await accessoryManager.sendMessage(
					message: emojiToSend,
					toUserNum: destination.userNum,
					channel: destination.channelNum,
					isEmoji: true,
					replyID: target.messageId
				)
			} catch {
				Logger.services.warning("Failed to send tapback.")
			}
		}

		tapbackText = ""
		tapbackFocused = false
		tapbackTargetMessage = nil
	}

	var body: some View {
		// Cast user.messageList to an array for easier indexing and ForEach.
		let messages: [MessageEntity] = Array(allPrivateMessages)

		// Precompute previous message
		let previousByID: [Int64: MessageEntity?] = {
			var dict = [Int64: MessageEntity?]()
			var prev: MessageEntity?
			for m in messages { dict[m.messageId] = prev; prev = m }
			return dict
		}()

		VStack {
			ScrollViewReader { scrollView in
				ScrollView {
					LazyVStack {
						ForEach(messages, id: \.messageId) { message in
							let previousMessage: MessageEntity? = previousByID[message.messageId] ?? nil
							
							UserMessageRow(
								message: message,
								allMessages: messages,
								previousMessage: previousMessage,
								preferredPeripheralNum: preferredPeripheralNum,
								user: user,
								replyMessageId: $replyMessageId,
								messageFieldFocused: $messageFieldFocused,
								messageToHighlight: $messageToHighlight,
								scrollView: scrollView,
								onInteractionComplete: handleInteractionComplete,
								onTapback: { message in
									tapbackFocused = false
									tapbackTargetMessage = message
									DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
										tapbackFocused = true
										#if targetEnvironment(macCatalyst)
										DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
											if let nsApp = NSClassFromString("NSApplication")?.value(forKeyPath: "sharedApplication") as? NSObject {
												let selector = NSSelectorFromString("orderFrontCharacterPalette:")
												if nsApp.responds(to: selector) {
													nsApp.perform(selector, with: nil)
												}
											}
										}
										#endif
									}
								}
							)
							.onAppear {
								// Only mark as read if the app is in the foreground
								if !message.read && UIApplication.shared.applicationState == .active {
									message.read = true
									LocalNotificationManager().cancelNotificationForMessageId(message.messageId)
									// Race condition, sometimes the app doesn't update unread count if we run this too early
									// So, run it in the main queue after everything saves and stabilizes
									DispatchQueue.main.async {
										markMessagesAsRead()
										scrollView.scrollTo("bottomAnchor", anchor: .bottom)
									}
								}
							}

						}
						// Invisible spacer to detect reaching bottom
						Color.clear
							.frame(height: 1)
							.id("bottomAnchor")
					}
				}
				.defaultScrollAnchor(.bottom)
				.defaultScrollAnchorBottomSizeChanges()
				.scrollDismissesKeyboard(.immediately)
				.onAppear {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
						scrollView.scrollTo("bottomAnchor", anchor: .bottom)
					}
				}
				.onChange(of: messageFieldFocused) {
					if messageFieldFocused {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
							scrollView.scrollTo("bottomAnchor", anchor: .bottom)
						}
					}
				}
				.onChange(of: tapbackFocused) {
					if tapbackFocused, let target = tapbackTargetMessage {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
							withAnimation {
								scrollView.scrollTo(target.messageId, anchor: .center)
							}
						}
					}
				}
				.background {
					TextField("", text: $tapbackText)
						.keyboardType(.emoji)
						.focused($tapbackFocused)
						.frame(width: 1, height: 1)
						.opacity(0.01)
						.allowsHitTesting(false)
						.onChange(of: tapbackText) {
							processTapback()
						}
				}
			}
			TextMessageField(
				destination: .user(user),
				replyMessageId: $replyMessageId,
				isFocused: $messageFieldFocused
			)
			.fixedSize(horizontal: false, vertical: true)
		}
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			if !user.keyMatch {
				ToolbarItem(placement: .bottomBar) {
					VStack {
						HStack {
							Image(systemName: "key.slash.fill")
								.symbolRenderingMode(.multicolor)
								.foregroundStyle(.red)
								.font(.caption2)
							Text("There is an issue with this contact's public key.")
								.foregroundStyle(.secondary)
								.font(.caption2)
						}
						Link(destination: URL(string: "meshtastic:///nodes?nodenum=\(user.num)")!) {
							Text("Details...")
								.font(.caption2)
								.offset(y: -15)
						}
					}
					.offset(y: -15)
				}
			}
			ToolbarItem(placement: .principal) {
				HStack {
					CircleText(text: user.shortName ?? "?", color: Color(UIColor(hex: UInt32(user.num))), circleSize: 44)
					Text(user.longName ?? "Unknown").font(.headline)
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				ZStack {
					ConnectedDevice(
						deviceConnected: accessoryManager.isConnected,
						name: accessoryManager.activeConnection?.device.shortName ?? "?")
				}
			}
		}
	}
}
