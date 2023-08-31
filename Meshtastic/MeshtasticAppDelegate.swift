//
//  MeshtasticAppDelegate.swift
//  Meshtastic
//
//  Created by Ben on 8/20/23.
//

import SwiftUI

class MeshtasticAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		print("🚀 Meshtstic Apple App launched!")
		UserDefaults.standard.register(defaults: ["blockRangeTest" : true])
		UNUserNotificationCenter.current().delegate = self
		return true
	}
	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
	}
	// This method is called when user clicked on the notification
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		let userInfo = response.notification.request.content.userInfo
		let targetValue = userInfo["target"] as? String
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
