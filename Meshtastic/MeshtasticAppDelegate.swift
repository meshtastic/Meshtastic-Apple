//
//  MeshtasticAppDelegate.swift
//  Meshtastic
//
//  Created by Ben on 8/20/23.
//

#if os(iOS)
import Intents
import SwiftData
import SwiftUI
import OSLog

class MeshtasticAppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {

	var router: Router?

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
		guard NSClassFromString("XCTestCase") == nil && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
			return true
		}
		Logger.services.info("🚀 [App] Meshtstic Apple App launched!")
		// Default User Default Values
		UserDefaults.standard.register(defaults: ["meshMapRecentering": true])
		UserDefaults.standard.register(defaults: ["meshMapShowNodeHistory": true])
		UserDefaults.standard.register(defaults: ["meshMapShowRouteLines": true])
		UNUserNotificationCenter.current().delegate = self
		let locationsHandler = LocationsHandler.shared
		locationsHandler.startLocationUpdates()
		// If a background activity session was previously active, reinstantiate it after the background launch.
		if locationsHandler.backgroundActivity {
			locationsHandler.backgroundActivity = true
		}
		// Initialize TAK Server if enabled
		Task { @MainActor in
			TAKServerManager.shared.initializeOnStartup()
		}
		// Request Siri authorization so intent donations work and CarPlay messaging is available.
		#if !targetEnvironment(macCatalyst)
		INPreferences.requestSiriAuthorization { status in
			Logger.services.info("Siri authorization status: \(String(describing: status))")
		}
		#endif
		return true
	}

	// MARK: - SiriKit Intent Handling

	/// Routes incoming SiriKit intents to the appropriate handler for CarPlay and Siri messaging support.
	func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
		IntentHandler().handler(for: intent)
	}

	// MARK: - CarPlay Mark As Read

	/// Marks all unread messages in a CarPlay conversation as read after Siri reads them aloud.
	private func markCarPlayMessagesAsRead(conversationId: String) {
		let context = PersistenceController.shared.context
		do {
			if conversationId.hasPrefix("dm-"), let nodeNum = Int64(conversationId.replacingOccurrences(of: "dm-", with: "")) {
				let descriptor = FetchDescriptor<MessageEntity>(
					predicate: #Predicate { message in
						message.read == false && message.fromUser?.num == nodeNum
					}
				)
				let messages = try context.fetch(descriptor)
				for message in messages {
					message.read = true
				}
			} else if conversationId.hasPrefix("channel-"), let channelIndex = Int32(conversationId.replacingOccurrences(of: "channel-", with: "")) {
				let descriptor = FetchDescriptor<MessageEntity>(
					predicate: #Predicate { message in
						message.read == false && message.channel == channelIndex
					}
				)
				let messages = try context.fetch(descriptor)
				for message in messages where message.toUser == nil {
					message.read = true
				}
			}
			if context.hasChanges {
				try context.save()
				Logger.services.info("🚗 [CarPlay] Marked messages as read for \(conversationId, privacy: .public)")
			}
		} catch {
			Logger.services.error("🚗 [CarPlay] Failed to mark messages as read: \(error.localizedDescription, privacy: .public)")
		}
	}

	// Lets us show the notification in the app in the foreground
	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		completionHandler([.list, .banner, .sound])
	}

	// This method is called when a user clicks on the notification
	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		let userInfo = response.notification.request.content.userInfo

		switch response.actionIdentifier {
		case UNNotificationDefaultActionIdentifier:
			// When Siri finishes reading a CarPlay message aloud, the notification
			// response arrives here. Mark all unread messages in that conversation as read.
			if userInfo["carplay_repost"] as? Bool == true,
			   let threadId = response.notification.request.content.threadIdentifier as String? {
				markCarPlayMessagesAsRead(conversationId: threadId)
			}
		case "messageNotification.thumbsUpAction":
			if let channel = userInfo["channel"] as? Int32,
			   let replyID = userInfo["messageId"] as? Int64 {
				Task {
					do {
						try await AccessoryManager.shared.sendMessage(
							message: Tapbacks.thumbsUp.emojiString,
							toUserNum: userInfo["userNum"] as? Int64 ?? 0,
							channel: channel,
							isEmoji: true,
							replyID: replyID
						)
						Logger.services.info("Tapback response sent")
					} catch {
						Logger.services.error("Failed to retrieve channel or messageId from userInfo")
					}
				}
			}
		case "messageNotification.thumbsDownAction":
			if let channel = userInfo["channel"] as? Int32,
			   let replyID = userInfo["messageId"] as? Int64 {
				Task {
					do {
						try await AccessoryManager.shared.sendMessage(
							message: Tapbacks.thumbsDown.emojiString,
							toUserNum: userInfo["userNum"] as? Int64 ?? 0,
							channel: channel,
							isEmoji: true,
							replyID: replyID
						)
						Logger.services.info("Tapback response sent")
					} catch {
						Logger.services.error("Failed to retrieve channel or messageId from userInfo")
					}
				}
			}
		case "messageNotification.replyInputAction":
			if let userInput = (response as? UNTextInputNotificationResponse)?.userText,
			   let channel = userInfo["channel"] as? Int32,
			   let replyID = userInfo["messageId"] as? Int64 {
				Task {
					do {
						try await AccessoryManager.shared.sendMessage(
							message: userInput,
							toUserNum: userInfo["userNum"] as? Int64 ?? 0,
							channel: channel,
							isEmoji: false,
							replyID: replyID
						)

						Logger.services.info("Actionable notification reply sent")
					} catch {
						Logger.services.error("Failed to retrieve user input, channel, or messageId from userInfo")
					}
				}
			}
		default:
			break
		}

		if let targetValue = userInfo["target"] as? String,
		   let deepLink = userInfo["path"] as? String,
		   let url = URL(string: deepLink) {
			Logger.services.info("userNotificationCenter didReceiveResponse handling deeplink: \(targetValue, privacy: .public) \(deepLink, privacy: .public)")
			router?.route(url: url)
		} else {
			Logger.services.error("Failed to handle notification response: \(userInfo, privacy: .public)")
		}
		completionHandler()
	}
}
#endif
