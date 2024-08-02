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
		if let targetValue = userInfo["target"] as? String,
		   let deepLink = userInfo["path"] as? String,
		   let url = URL(string: deepLink) {
			Logger.services.info("🔔 userNotificationCenter didReceiveResponse \(targetValue) \(deepLink)")
			router?.route(url: url)
		} else {
			Logger.services.error("💥 Failed to handle notification response: \(userInfo)")
		}

		completionHandler()
	}
}
