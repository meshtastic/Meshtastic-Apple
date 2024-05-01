//
//  MeshtasticAppDelegate.swift
//  Meshtastic
//
//  Created by Ben on 8/20/23.
//

import SwiftUI

class MeshtasticAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
	
	var bleManager: BLEManager?
	


	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		print("🚀 Meshtstic Apple App launched!")
		// Default User Default Values
		UserDefaults.standard.register(defaults: ["blockRangeTest" : true])
		UserDefaults.standard.register(defaults: ["meshMapRecentering" : true])
		UserDefaults.standard.register(defaults: ["meshMapShowNodeHistory" : true])
		UserDefaults.standard.register(defaults: ["meshMapShowRouteLines" : true])
		UNUserNotificationCenter.current().delegate = self
		if #available(iOS 17.0, macOS 14.0, *) {
			let locationsHandler = LocationsHandler.shared
			locationsHandler.startLocationUpdates()

			// If a background activity session was previously active, reinstantiate it after the background launch.
			if locationsHandler.backgroundActivity {
				locationsHandler.backgroundActivity = true
			}
		}
		return true
	}
	
	func addBleManager(bleManager: BLEManager){
		self.bleManager = bleManager
	}
	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
	}
	// This method is called when user clicked on the notification
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		let userInfo = response.notification.request.content.userInfo
		
		
		
		if (bleManager != nil){
			switch response.actionIdentifier {
			case UNNotificationDefaultActionIdentifier:
				
				break
				
			case "messageNotification.thumbsUpAction":
				let tapbackResponse = bleManager!.sendMessage(
					message: Tapbacks.thumbsUp.emojiString,
					toUserNum:  userInfo["userNum"] as? Int64 ?? 0,
					channel: userInfo["channel"] as! Int32,
					isEmoji: true,
					replyID: userInfo["messageId"] as! Int64
				)
				
				print("Tapback Response sent")
				
				break
			case"messageNotification.thumbsDownAction":
				
				let tapbackResponse = bleManager!.sendMessage(
					message: Tapbacks.thumbsDown.emojiString,
					toUserNum:  userInfo["userNum"] as? Int64 ?? 0,
					channel: userInfo["channel"] as! Int32,
					isEmoji: true,
					replyID: userInfo["messageId"] as! Int64
				)
				
				print("Tapback Response sent")
				break
				
				
			case "messageNotification.replyInputAction":
				if let userInput = (response as? UNTextInputNotificationResponse)?.userText {
					let tapbackResponse = bleManager!.sendMessage(
						message: userInput,
						toUserNum:  userInfo["userNum"] as? Int64 ?? 0,
						channel: userInfo["channel"] as! Int32,
						isEmoji: false,
						replyID: userInfo["messageId"] as! Int64
					)
				}
			default:
				break
			}
		}
		
		
		let targetValue = userInfo["target"] as? String
		AppState.shared.navigationPath = userInfo["path"] as? String
		print("\(AppState.shared.navigationPath ?? "EMPTY")")
		if targetValue == "map" {
			AppState.shared.tabSelection = Tab.map
		} else if targetValue == "message" {
			AppState.shared.tabSelection = Tab.messages
		} else if targetValue == "node" {
			AppState.shared.tabSelection = Tab.nodes
		}
		completionHandler()
	}
	
	
}

