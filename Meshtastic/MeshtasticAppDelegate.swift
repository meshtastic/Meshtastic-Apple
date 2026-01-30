//
//  MeshtasticAppDelegate.swift
//  Meshtastic
//
//  Created by Ben on 8/20/23.
//

import SwiftUI
import OSLog

class MeshtasticAppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {

	var router: Router?

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
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
		return true
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
			break
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
